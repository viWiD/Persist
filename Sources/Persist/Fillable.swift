//
//  Fillable.swift
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


typealias PrimitiveValue = NSObject


public protocol Fillable: EntityRepresentable {
    
    static var persistableProperties: Set<PropertyMapping> { get }
    
    func setValue(value: JSON, forProperty: PropertyMapping) -> Promise<Void> // TODO: make un-overrideable?
    
}

public enum FillError: ErrorType, CustomStringConvertible {
    // case InvalidObjectType(ofEntityNamed: String)
    case UnknownEntity(named: String)
    case IdentificationAttributeNotFound(named: String, entityName: String)
    case IdentificationPropertyNotFound(ofEntityNamed: String)
    case IdentificationValueNotFound(key: String)
    case InvalidIdentificationValue(NSObject?)
    case PropertyNotFound(named: String)
    case TooManyValues(forRelationshipNamed: String)
    case MissingDestinationEntity(ofRelationshipNamed: String)
    case MissingDestinationEntityName(ofRelationshipNamed: String)
    case MissingEntityClassName(ofEntityNamed: String)
    case NotSubentity(named: String, ofEntityNamed: String)
    case NonIdentifyableType(named: String)
    case NonFillableType(named: String)
    case NonPersistableType(named: String)
    case ContextUnavailable
    
    public var description: String {
        switch self {
        //case .InvalidObjectType(ofEntityNamed: let entityName): return "Object of entity \(entityName) does not match the given \(Persistable.self) type."
        case .UnknownEntity(named: let entityName): return "Unknown entity \(entityName)."
        case .IdentificationAttributeNotFound(named: let name, entityName: let entityName): return "Identification attribute \(name) not found for entity \(entityName)."
        case .IdentificationPropertyNotFound(ofEntityNamed: let entityName): return "Identification property not found for entity \(entityName). Make sure to define a property mapping for its identificationAttributeName."
        case .IdentificationValueNotFound(key: let key): return "Identification value \(key) not found."
        case .InvalidIdentificationValue(let value): return "Invalid identification value \(value)."
        case .PropertyNotFound(named: let name): return "Property \(name) not found."
        case .TooManyValues(forRelationshipNamed: let name): return "Too many values for relationship \(name)"
        case .MissingDestinationEntity(ofRelationshipNamed: let name): return "Relationship \(name) has no destination entity."
        case .MissingDestinationEntityName(ofRelationshipNamed: let name): return "Destination entity for relationship \(name) has no name."
        case .MissingEntityClassName(ofEntityNamed: let entityName): return "Entity \(entityName) has no associated class name"
        case .NotSubentity(named: let entityName, ofEntityNamed: let superentityName): return "Entity \(entityName) is not a subentity of \(superentityName)."
        case .NonIdentifyableType(named: let name): return "\(name) does not conform to \(Identifyable.self)."
        case .NonFillableType(named: let name): return "\(name) does not conform to \(Fillable.self)."
        case .NonPersistableType(named: let name): return "\(name) does not conform to \(Persistable.self)."
        case .ContextUnavailable: return "Context unavailable, was the object deleted from its context?"
        }
    }
}


// MARK - Filling

internal func filledObjects(ofEntity entityType: Fillable.Type, withRepresentation objectsRepresentation: JSON, context: NSManagedObjectContext) -> Promise<[NSManagedObject]> {
    let logger = Evergreen.getLogger("Persist.Trace")
    
    return objectsRepresentation.map(

        identificationValueTransform: { identificationValue in
            logger.verbose("Found \(entityType.self) identification value \(identificationValue).")
            
            guard let identifyableEntityType = entityType as? Identifyable.Type else {
                return Promise(error: FillError.NonIdentifyableType(named: entityType.entityName))
            }
            
            // retrieve stubbed object
            return stub(objectOfEntity: identifyableEntityType, withIdentificationValue: identificationValue, context: context)
        },
        
        propertyValuesTransform: { propertyValues in
            logger.verbose("Found \(entityType.self) dictionary representation: \(objectsRepresentation)")
            
            // retrieve filled object
            return filledObject(ofEntity: entityType.self, withPropertyValues: propertyValues, context: context)
        }
    )
    
}

private func filledObject(ofEntity entityType: Fillable.Type, withPropertyValues propertyValues: PropertyValues, context: NSManagedObjectContext) -> Promise<NSManagedObject> {
    let logger = Evergreen.getLogger("Persist.Trace")
    
    let object: Promise<NSManagedObject>
    
    if let persistableEntityType = entityType.self as? Persistable.Type {
        
        // entity is identifyable, stub object
        
        // retrieve identification value
        guard let identificationProperty = persistableEntityType.identificationProperty else {
            return Promise(error: FillError.IdentificationPropertyNotFound(ofEntityNamed: persistableEntityType.entityName))
        }
        guard let identificationValue = propertyValues[identificationProperty.key] else {
            return Promise(error: FillError.IdentificationValueNotFound(key: identificationProperty.key))
        }
        
        logger.verbose("\(persistableEntityType.entityName) is identified by its property \(identificationProperty). Found value \(identificationValue), retrieving object...")
        
        // retrieve object
        object = stub(objectOfEntity: persistableEntityType, withIdentificationValue: identificationValue, context: context)
        
    } else {
        
        // entity is not identifyable, just create object
        
        logger.verbose("\(entityType.entityName) is not identifyable, creating object...")
        
        object = Promise { fulfill, reject in
            context.performBlock {
                
                // create object
                let object = NSEntityDescription.insertNewObjectForEntityForName(entityType.entityName, inManagedObjectContext: context)
                
                fulfill(object)
            }
        }
        
    }
    
    return object.then { object in
        
        // fill object with attribute values
        logger.verbose("Got object \(object).")
        guard let fillableObject = object as? Fillable else {
            return Promise(error: FillError.NonFillableType(named: entityType.entityName))
        }
        return fillableObject.fillWith(propertyValues).then {
            return Promise(object)
        }
    }
}


extension Fillable {
    
    // TODO: make public?
    
    internal static var persistablePropertiesByKey: [String: PropertyMapping] {
        return persistableProperties.reduce([:]) { persistablePropertiesByKey, property in
            var persistablePropertiesByKey = persistablePropertiesByKey
            persistablePropertiesByKey[property.key] = property
            return persistablePropertiesByKey
        }
    }
    internal static var persistablePropertiesByName: [String: PropertyMapping] { // TODO: reuse code from above
        return persistableProperties.reduce([:]) { persistablePropertiesByKey, property in
            var persistablePropertiesByKey = persistablePropertiesByKey
            persistablePropertiesByKey[property.name] = property
            return persistablePropertiesByKey
        }
    }
    
    private func fillWith(values: PropertyValues) -> Promise<Void> {
        let fillLogger = Evergreen.getLogger("Persist.Fill")
        let traceLogger = Evergreen.getLogger("Persist.Trace")
        
        traceLogger.verbose("Filling object \(self) with property values \(values)...")
        
        return when(values.map { key, value in
            guard let propertyMapping = Self.persistablePropertiesByKey[key] else {
                fillLogger.debug("No property mapping for key \(key) available, skipping.")
                return Promise()
            }
            
            return self.setValue(value, forProperty: propertyMapping).recover { error in
                fillLogger.warning("Could not set \(value) for property \(propertyMapping), skipping.", error: error)
            }
            }).then {
                traceLogger.verbose("Filled object with attribute values, it is now: \(self)")
                return Promise()
        }
    }
    
}

public extension Fillable where Self: NSManagedObject {
    
    func setValue(value: JSON, forProperty property: PropertyMapping) -> Promise<Void> {
        let logger = Evergreen.getLogger("Persist.Fill.SetValue")
        let traceLogger = Evergreen.getLogger("Persist.Trace")
        traceLogger.verbose("Setting value \(value) for property \(property) of \(self)...")
        
        let object = self as NSManagedObject // workaround for "ambiguous use of setValue:forKey" compiler error
        
        // TODO: split into reasonably small functions
        
        if let attribute = entity.attributesByName[property.name] {
            
            return Promise { fulfill, reject in
                // transform to attribute type
                let newValue: NSObject?
                do {
                    // TODO: use custom transformers
                    newValue = try value.transformedTo(attribute.attributeType)
                    logger.debug("Transformed value \(value) to \(newValue ?? "nil").")
                } catch {
                    logger.error("Could not transform value \(value).", error: error)
                    reject(error)
                    return
                }
                
                guard let context = self.managedObjectContext else {
                    reject(FillError.ContextUnavailable)
                    return
                }
                
                context.performBlock {
                    // assign to attribute
                    if object.valueForKey(attribute.name) as? NSObject != newValue {
                        object.setValue(newValue, forKey: attribute.name)
                        logger.verbose("Attribute \(attribute.name) set to \(newValue).")
                    } else {
                        logger.verbose("Attribute \(attribute.name) is already set to \(newValue).")
                    }
                    fulfill()
                }
            }
            
        } else if let relationship = entity.relationshipsByName[property.name] {
            
            guard let destinationEntity = relationship.destinationEntity else {
                return Promise(error: FillError.MissingDestinationEntity(ofRelationshipNamed: relationship.name))
            }
            guard let destinationEntityName = relationship.destinationEntity?.name else {
                return Promise(error: FillError.MissingDestinationEntityName(ofRelationshipNamed: relationship.name))
            }
            guard let destinationEntityClassName = destinationEntity.managedObjectClassName else {
                return Promise(error: FillError.MissingEntityClassName(ofEntityNamed: destinationEntityName))
            }
            guard let destinationEntityType = NSClassFromString(destinationEntityClassName) as? Fillable.Type else {
                return Promise(error: FillError.NonFillableType(named: destinationEntity.managedObjectClassName))
            }
            
            guard let context = self.managedObjectContext else {
                return Promise(error: FillError.ContextUnavailable)
            }
            
            if destinationEntityType.self is Identifyable.Type || relationship.toMany {
            
                // retrieve destination objects
                return filledObjects(ofEntity: destinationEntityType.self, withRepresentation: value, context: context).then { destinationObjects in
                    Promise { fulfill, reject in
                        context.performBlock {
                            
                            // assign to relationship
                            // TODO: remove as! NSObject force casts
                            // TODO: non-identifyable relationship destinations such as Addresses are created and set here without checking for equality
                            if relationship.toMany {
                                if relationship.ordered {
                                    let newRelationshipValue = NSOrderedSet(array: destinationObjects)
                                    let mutableRelationshipValue = self.mutableOrderedSetValueForKey(relationship.name)
                                    if mutableRelationshipValue != newRelationshipValue {
                                        mutableRelationshipValue.removeAllObjects()
                                        mutableRelationshipValue.addObjectsFromArray(destinationObjects)
                                        logger.verbose("Ordered to-many relationship \(relationship.name) set to \(newRelationshipValue).")
                                    } else {
                                        logger.verbose("Ordered to-many relationship \(relationship.name) is already set to \(newRelationshipValue).")
                                    }
                                } else {
                                    let newRelationshipValue = NSSet(array: destinationObjects)
                                    let mutableRelationshipValue = self.mutableSetValueForKey(relationship.name)
                                    if mutableRelationshipValue != newRelationshipValue {
                                        mutableRelationshipValue.setSet(Set(destinationObjects))
                                        logger.verbose("To-many relationship \(relationship.name) set to \(newRelationshipValue).")
                                    } else {
                                        logger.verbose("To-many relationship \(relationship.name) is already set to \(newRelationshipValue).")
                                    }
                                }
                            } else {
                                guard destinationObjects.count <= 1 else {
                                    reject(FillError.TooManyValues(forRelationshipNamed: relationship.name))
                                    return
                                }
                                let destinationObject = destinationObjects.first
                                if object.valueForKey(relationship.name) as? NSObject != destinationObject {
                                    object.setValue(destinationObject, forKey: relationship.name)
                                    logger.verbose("To-one relationship \(relationship.name) set to \(destinationObject).")
                                } else {
                                    logger.verbose("To-one relationship \(relationship.name) is already set to \(destinationObject).")
                                }
                            }
                            
                            fulfill()
                        }
                    }
                }
                
            } else {
                
                // destination is not Identifyable but to-one, try to just update relationship instead of re-creating
                
                // extract property values
                return value.map(identificationValueTransform: { identificationValue in
                    return Promise(error: FillError.NonIdentifyableType(named: destinationEntityType.entityName))
                }, propertyValuesTransform: { propertyValues -> Promise<PropertyValues> in
                    return Promise(propertyValues)
                }).then { allFoundPropertyValues in
                    
                    guard allFoundPropertyValues.count <= 1 else {
                        return Promise(error: FillError.TooManyValues(forRelationshipNamed: relationship.name))
                    }
                    let destinationPropertyValues = allFoundPropertyValues.first
                    
                    // retrieve existing relationship destination
                    var existingDestinationObject: NSManagedObject?
                    context.performBlockAndWait {
                        existingDestinationObject = object.valueForKey(relationship.name) as? NSManagedObject
                    }
                    
                    if let destinationPropertyValues = destinationPropertyValues {
                        if let fillableDestinationObject = existingDestinationObject as? Fillable where existingDestinationObject?.entity.name == destinationEntityType.entityName {
                            
                            // update existing destination object
                            logger.verbose("Updating existing destination object \(fillableDestinationObject)...")
                            return fillableDestinationObject.fillWith(destinationPropertyValues)
                            
                        } else {
                            
                            // create relationship destination object
                            return filledObject(ofEntity: destinationEntityType.self, withPropertyValues: destinationPropertyValues, context: context).then { destinationObject in
                                context.performBlockAndWait {
                                    
                                    object.setValue(destinationObject, forKey: relationship.name)
                                    
                                }
                            }
                            
                        }
                        
                    } else {
                        return Promise { fulfill, reject in
                            context.performBlock {
                                
                                if object.valueForKey(relationship.name) != nil {
                                    object.setValue(nil, forKey: relationship.name)
                                }
                                fulfill()
                                
                            }
                        }
                    }
                }
                
            }
            
        } else {
            return Promise(error: FillError.PropertyNotFound(named: property.name))
        }
        
    }
    
}
