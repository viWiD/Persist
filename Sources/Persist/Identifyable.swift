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

internal func stub(objectOfEntity entityType: Identifyable.Type, withIdentificationValue identificationValue: JSON, context: NSManagedObjectContext) -> Promise<NSManagedObject> {
    let logger = Evergreen.getLogger("Persist.Stub")
    
    // retrieve identification value
    return primitiveIdentificationValue(ofEntity: entityType, fromJSON: identificationValue, context: context).then { primitiveIdentificationValue in
        
        return Promise { fulfill, reject in
            context.performBlock {

                // retrieve matching existing objects
                let identificationPredicate = NSPredicate(format: "%K = %@", entityType.identificationAttributeName, primitiveIdentificationValue)
                let objects: [NSManagedObject]
                do {
                    objects = try existingObjects(ofEntity: entityType, includingSuperentitySharingIdentification: true, matching: identificationPredicate, context: context)
                } catch {
                    reject(error)
                    return
                }
                
                if objects.count > 0 {
                            
                    // found existing object
                    if objects.count > 1 {
                        logger.warning("Found multiple existing objects of entity \(entityType.entityName) with identification value \(identificationValue), choosing any: \(objects)")
                    }
                    var object = objects.first!
                    logger.verbose("Found existing object of entity \(entityType.entityName) for representation: \(object)")
                    
                    // make sure the object is of the correct type, and not a stub of a superentity
                    do {
                        object = try ensureEntity(entityType.self, forObject: object)
                    } catch {
                        reject(error)
                        return
                    }
                    
                    fulfill(object)

                } else {
                    
                    // create object
                    // TODO: option to disable stubbing
                    logger.debug("Could not find object of entity \(entityType.entityName) with identification value \(identificationValue), creating one.")
                    let object = createObject(ofEntity: entityType.self, withPrimitiveIdentificationValue: primitiveIdentificationValue, context: context)
                    
                    fulfill(object)
                }
                
            }
        }
    }
    
}

/// - warning: Only call on `context`'s queue using `performBlock`.
private func createObject(ofEntity entityType: Identifyable.Type, withPrimitiveIdentificationValue primitiveIdentificationValue: PrimitiveValue, context: NSManagedObjectContext) -> NSManagedObject {
    let object = NSEntityDescription.insertNewObjectForEntityForName(entityType.entityName, inManagedObjectContext: context)
    object.setValue(primitiveIdentificationValue, forKey: entityType.identificationAttributeName)
    return object
}

/// - warning: Only call on `context`'s queue using `performBlock`.
private func existingObjects(ofEntity entityType: Identifyable.Type, includingSuperentitySharingIdentification: Bool, matching predicate: NSPredicate, context: NSManagedObjectContext) throws -> [NSManagedObject] {
    let logger = Evergreen.getLogger("Persist.Stub")

    guard let entity = NSEntityDescription.entityForName(entityType.entityName, inManagedObjectContext: context) else {
        throw FillError.UnknownEntity(named: entityType.entityName)
    }

    let identificationEntity: Identifyable.Type
    if let superentitySharingIdentification = entityType.superentitySharingIdentification where includingSuperentitySharingIdentification {
        guard let superentity = NSEntityDescription.entityForName(superentitySharingIdentification.entityName, inManagedObjectContext: context) else {
            throw FillError.UnknownEntity(named: superentitySharingIdentification.entityName)
        }
        guard entity.isSubentityOf(superentity) || entity.isKindOfEntity(superentity) else {
            throw FillError.NotSubentity(named: entity.name ?? "", ofEntityNamed: superentity.name ?? "")
        }
        // TODO: validate that superentity has the same identification property necessary?
        identificationEntity = superentitySharingIdentification
        logger.debug("\(entityType) shares identification with \(superentitySharingIdentification), using for fetch...", onceForKey: "notify_superentity_sharing_identification_\(entityType.entityName)")
    } else {
        identificationEntity = entityType
    }
    
    let fetchRequest = NSFetchRequest(entityName: identificationEntity.entityName)
    fetchRequest.includesSubentities = true // TODO: is this always good?
    fetchRequest.includesPendingChanges = true
    fetchRequest.predicate = predicate
    
    return try context.executeFetchRequest(fetchRequest) as! [NSManagedObject] // TODO: is this force cast safe and reasonable?
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

/// - warning: Only call on `object.managedObjectContext`'s queue using `performBlock`.
private func ensureEntity(entityType: EntityRepresentable.Type, forObject object: NSManagedObject) throws -> NSManagedObject {
    let logger = Evergreen.getLogger("Persist.Stub")

    guard let context = object.managedObjectContext else {
        throw FillError.ContextUnavailable
    }
    guard let entity = NSEntityDescription.entityForName(entityType.entityName, inManagedObjectContext: context) else {
        throw FillError.UnknownEntity(named: entityType.entityName)
    }
    
    if object.entity.isKindOfEntity(entity) {
        
        return object
        
    } else {
        
        logger.debug("Deleting \(object) to replace it with an object of entity \(entityType.entityName)...")
        guard entity.isSubentityOf(object.entity) else {
            throw FillError.NotSubentity(named: entity.name ?? "", ofEntityNamed: object.entity.name ?? "")
        }

        let replacement = NSEntityDescription.insertNewObjectForEntityForName(entityType.entityName, inManagedObjectContext: context)
        replacement.setValuesForKeysWithDictionary(object.dictionaryWithValuesForKeys(Array(object.entity.propertiesByName.keys)))
        context.deleteObject(object)
        logger.debug("Got replacement \(object).")

        return replacement
    }

}


// MARK: - Orphans

internal func deleteOrphans(ofEntity entityType: Persistable.Type, onlyKeeping objectsRepresentation: JSON, context: NSManagedObjectContext, scope: NSPredicate?) -> Promise<Void> {
    let traceLogger = Evergreen.getLogger("Persist.Trace")
    traceLogger.verbose("Deleting orphans of \(entityType)...")
    let logger = Evergreen.getLogger("Persist.DeleteOrphans")

    // obtain identification values to keep
    return primitiveIdentificationValues(ofEntity: entityType, withRepresentation: objectsRepresentation, context: context).then { primitiveIdentificationValuesToKeep in
        logger.verbose("Keeping objects with identification values \(primitiveIdentificationValuesToKeep).")
        
        return Promise { fulfill, reject in
            context.performBlock {
                
                // retrieve orphans
                var orphanPredicate = NSPredicate(format: "NOT %K IN %@", entityType.identificationAttributeName, primitiveIdentificationValuesToKeep)
                if let scope = scope {
                    logger.debug("Limiting orphan deletion to scope \(scope).")
                    orphanPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [ scope, orphanPredicate ])
                }
                let orphans: [NSManagedObject]
                do {
                    orphans = try existingObjects(ofEntity: entityType.self, includingSuperentitySharingIdentification: false, matching: orphanPredicate, context: context)
                } catch {
                    reject(error)
                    return
                }
                
                // delete orphans
                orphans.forEach({ context.deleteObject($0) })
                if orphans.count == 0 {
                    logger.debug("No orphans to delete.")
                } else {
                    logger.debug("Found and deleted \(orphans.count) orphans.")
                }
                
                fulfill()
            }
        }
    }
}

private func primitiveIdentificationValues(ofEntity entityType: Persistable.Type, withRepresentation objectsRepresentation: JSON, context: NSManagedObjectContext) -> Promise<[PrimitiveValue]> {
    guard let identificationProperty = entityType.identificationProperty else {
        return Promise(error: FillError.IdentificationPropertyNotFound(ofEntityNamed: entityType.entityName))
    }

    return objectsRepresentation.map(
        identificationValueTransform: { identificationValue in
            primitiveIdentificationValue(ofEntity: entityType.self, fromJSON: identificationValue, context:   context)
        },
        propertyValuesTransform: { propertyValues in
            guard let identificationValue = propertyValues[identificationProperty.key] else {
                return Promise(error: FillError.IdentificationValueNotFound(key: identificationProperty.key))
            }
            return primitiveIdentificationValue(ofEntity: entityType.self, fromJSON: identificationValue, context: context)
        }
    )
}

private func primitiveIdentificationValue(ofEntity entityType: Identifyable.Type, fromJSON identificationValueJSON: JSON, context: NSManagedObjectContext) -> Promise<PrimitiveValue> {
    guard let entity = NSEntityDescription.entityForName(entityType.entityName, inManagedObjectContext: context) else {
        return Promise(error: FillError.UnknownEntity(named: entityType.entityName))
    }
    guard let identificationAttribute = entity.attributesByName[entityType.identificationAttributeName] else {
        return Promise(error: FillError.IdentificationAttributeNotFound(named: entityType.identificationAttributeName, entityName: entityType.entityName))
    }
    let possibleIdentificationValue: PrimitiveValue?
    do {
        possibleIdentificationValue = try identificationValueJSON.transformedTo(identificationAttribute.attributeType)
    } catch {
        return Promise(error: error)
    }
    guard let identificationValue = possibleIdentificationValue else {
        return Promise(error: FillError.InvalidIdentificationValue(possibleIdentificationValue))
    }
    return Promise(identificationValue)
}
