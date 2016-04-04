//
//  Identifyable.swift
//  Pods
//
//  Created by Nils Fischer on 04.04.16.
//
//

import Foundation
import CoreData
import Evergreen
import Freddy
import PromiseKit


public protocol Identifyable: EntityRepresentable {
    
    static var identificationAttributeName: String { get }
    
    static var superentitySharingIdentification: Identifyable.Type? { get }
    
}

public extension Identifyable {
    
    public static var superentitySharingIdentification: Identifyable.Type? {
        return nil
    }
    
}


// MARK: - Stubbing

internal func stub(objectOfEntity entityType: Identifyable.Type, withIdentificationValue identificationValueJSON: JSON, context: NSManagedObjectContext) -> Promise<NSManagedObject> {
    let logger = Evergreen.getLogger("Persist.Stub")
    
    // retrieve identification attribute
    guard let entity = NSEntityDescription.entityForName(entityType.entityName, inManagedObjectContext: context) else {
        return Promise(error: FillError.UnknownEntity(named: entityType.entityName))
    }
    guard let identificationAttributeDescription = entity.attributesByName[entityType.identificationAttributeName] else {
        return Promise(error: FillError.IdentificationAttributeNotFound(named: entityType.identificationAttributeName, entityName: entityType.entityName))
    }
    
    return Promise<NSObject> { fulfill, reject in
        
        // retrieve identification value
        let possibleIdentificationValue: NSObject?
        do {
            possibleIdentificationValue = try identificationValueJSON.transformedTo(identificationAttributeDescription.attributeType)
        } catch {
            reject(error)
            return
        }
        guard let identificationValue = possibleIdentificationValue else {
            reject(FillError.InvalidIdentificationValue(possibleIdentificationValue))
            return
        }
        fulfill(identificationValue)
        
        }.then { identificationValue in
            
            return Promise<NSManagedObject> { fulfill, reject in
                
                context.performBlock {
                    
                    // try to retrieve existing object
                    let identificationEntity: Identifyable.Type
                    if let superentitySharingIdentification = entityType.superentitySharingIdentification {
                        guard let superentity = NSEntityDescription.entityForName(superentitySharingIdentification.entityName, inManagedObjectContext: context) else {
                            reject(FillError.UnknownEntity(named: superentitySharingIdentification.entityName))
                            return
                        }
                        guard entity.isSubentityOf(superentity) || entity.isKindOfEntity(superentity) else {
                            reject(FillError.NotSubentity(named: entity.name ?? "", ofEntityNamed: superentity.name ?? ""))
                            return
                        }
                        // TODO: validate that superentity has the same identification property necessary?
                        identificationEntity = superentitySharingIdentification
                        logger.debug("\(entityType) shares identification with \(superentitySharingIdentification), using for fetch...")
                    } else {
                        identificationEntity = entityType
                    }
                    let fetchRequest = NSFetchRequest(entityName: identificationEntity.entityName)
                    fetchRequest.includesSubentities = true // TODO: is this always good?
                    fetchRequest.includesPendingChanges = true
                    let identificationPredicate = NSPredicate(format: "%K = %@", entityType.identificationAttributeName, identificationValue)
                    fetchRequest.predicate = identificationPredicate
                    let objects: [NSManagedObject]
                    do {
                        objects = try context.executeFetchRequest(fetchRequest) as! [NSManagedObject] // TODO: is this force cast safe and reasonable?
                    } catch {
                        reject(error)
                        return
                    }
                    
                    if objects.count > 0 {
                        
                        // found existing object
                        if objects.count > 1 {
                            logger.warning("Found multiple existing objects of entity \(identificationEntity.entityName) with identification predicate \(identificationPredicate), choosing any: \(objects)")
                        }
                        var object = objects.first!
                        logger.verbose("Found existing object of entity \(identificationEntity.entityName) for representation: \(object)")
                        
                        // make sure the object is of the correct type, and not a stub of a superentity
                        if !object.entity.isKindOfEntity(entity) {
                            logger.debug("Deleting \(object) to replace it with an object of entity \(entityType.entityName)...")
                            guard entity.isSubentityOf(object.entity) else {
                                reject(FillError.NotSubentity(named: entity.name ?? "", ofEntityNamed: object.entity.name ?? ""))
                                return
                            }
                            let replacement = NSEntityDescription.insertNewObjectForEntityForName(entityType.entityName, inManagedObjectContext: context)
                            replacement.setValuesForKeysWithDictionary(object.dictionaryWithValuesForKeys(Array(object.entity.propertiesByName.keys)))
                            context.deleteObject(object)
                            object = replacement
                            logger.debug("Got \(object).")
                        }
                        
                        fulfill(object)
                    } else {
                        
                        // create object
                        // TODO: option to disable stubbing
                        logger.debug("Could not find object of entity \(entityType.entityName) with identification predicate \(identificationPredicate), creating one.")
                        let object = NSEntityDescription.insertNewObjectForEntityForName(entityType.entityName, inManagedObjectContext: context)
                        object.setValue(identificationValue, forKey: entityType.identificationAttributeName)
                        
                        fulfill(object)
                    }
                    
                }
                
            }
            
    }
    
}

private extension NSEntityDescription {
    func isSubentityOf(entity: NSEntityDescription) -> Bool {
        guard let superentity = self.superentity else {
            return false
        }
        if superentity.isKindOfEntity(entity) {
            return true
        }
        return superentity.isSubentityOf(entity)
    }
}
