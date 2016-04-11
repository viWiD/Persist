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

/// - warning: Only call on `context`'s queue using `performBlock`.
internal func stub(objectOfEntity entityType: Identifyable.Type, withIdentificationValue identificationValue: JSON, context: NSManagedObjectContext) throws -> NSManagedObject {
    let logger = Evergreen.getLogger("Persist.Stub")
    
    // retrieve identification value
    let primitiveIdentification = try primitiveIdentificationValue(ofEntity: entityType, fromJSON: identificationValue, context: context)

    // retrieve matching existing objects
    let identificationPredicate = NSPredicate(format: "%K = %@", entityType.identificationAttributeName, primitiveIdentification)
    let objects = try existingObjects(ofEntity: entityType, includingSuperentitySharingIdentification: true, matching: identificationPredicate, context: context)
    
    if objects.count > 0 {
                
        // found existing object
        if objects.count > 1 {
            logger.warning("Found multiple existing objects of entity \(entityType.entityName) with identification value \(identificationValue), choosing any: \(objects)")
        }
        var object = objects.first!
        logger.verbose("Found existing object of entity \(entityType.entityName) for representation: \(object)")
        
        // make sure the object is of the correct type, and not a stub of a superentity
        object = try ensureEntity(entityType.self, forObject: object)

        return object
    } else {
        
        // create object
        // TODO: option to disable stubbing
        logger.debug("Could not find object of entity \(entityType.entityName) with identification value \(identificationValue), creating one.")
        let object = createObject(ofEntity: entityType.self, withPrimitiveIdentificationValue: primitiveIdentification, context: context)
     
        return object
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

/// - warning: Only call on `context`'s queue using `performBlock`.
internal func deleteOrphans(ofEntity entityType: Persistable.Type, onlyKeeping objectsRepresentation: JSON, context: NSManagedObjectContext, scope: NSPredicate?) throws {
    let traceLogger = Evergreen.getLogger("Persist.Trace")
    traceLogger.verbose("Deleting orphans of \(entityType)...")
    let logger = Evergreen.getLogger("Persist.DeleteOrphans")

    // obtain identification values to keep
    let primitiveIdentificationValuesToKeep = try primitiveIdentificationValues(ofEntity: entityType, withRepresentation: objectsRepresentation, context: context)
    logger.verbose("Keeping objects with identification values \(primitiveIdentificationValuesToKeep).")
        
    // retrieve orphans
    var orphanPredicate = NSPredicate(format: "NOT %K IN %@", entityType.identificationAttributeName, primitiveIdentificationValuesToKeep)
    if let scope = scope {
        logger.debug("Limiting orphan deletion to scope \(scope).")
        orphanPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [ scope, orphanPredicate ])
    }
    let orphans = try existingObjects(ofEntity: entityType.self, includingSuperentitySharingIdentification: false, matching: orphanPredicate, context: context)
    
    // delete orphans
    orphans.forEach({ context.deleteObject($0) })
    if orphans.count == 0 {
        logger.debug("No orphans to delete.")
    } else {
        logger.debug("Found and deleted \(orphans.count) orphans.")
    }
}

private func primitiveIdentificationValues(ofEntity entityType: Persistable.Type, withRepresentation objectsRepresentation: JSON, context: NSManagedObjectContext) throws -> [PrimitiveValue] {
    guard let identificationProperty = entityType.identificationProperty else {
        throw FillError.IdentificationPropertyNotFound(ofEntityNamed: entityType.entityName)
    }

    return try objectsRepresentation.map(
        identificationValueTransform: { identificationValue in
            try primitiveIdentificationValue(ofEntity: entityType.self, fromJSON: identificationValue, context:   context)
        },
        propertyValuesTransform: { propertyValues in
            guard let identificationValue = propertyValues[identificationProperty.key] else {
                throw FillError.IdentificationValueNotFound(key: identificationProperty.key)
            }
            return try primitiveIdentificationValue(ofEntity: entityType.self, fromJSON: identificationValue, context: context)
        }
    )
}

private func primitiveIdentificationValue(ofEntity entityType: Identifyable.Type, fromJSON identificationValueJSON: JSON, context: NSManagedObjectContext) throws -> PrimitiveValue {
    guard let entity = NSEntityDescription.entityForName(entityType.entityName, inManagedObjectContext: context) else {
        throw FillError.UnknownEntity(named: entityType.entityName)
    }
    guard let identificationAttribute = entity.attributesByName[entityType.identificationAttributeName] else {
        throw FillError.IdentificationAttributeNotFound(named: entityType.identificationAttributeName, entityName: entityType.entityName)
    }

    let possibleIdentificationValue = try identificationValueJSON.transformedTo(identificationAttribute.attributeType)
    
    guard let identificationValue = possibleIdentificationValue else {
        throw FillError.InvalidIdentificationValue(possibleIdentificationValue)
    }
    
    return identificationValue
}
