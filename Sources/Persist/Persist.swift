//
//  Persist.swift
//  uni-hd
//
//  Created by Nils Fischer on 29.03.16.
//  Copyright © 2016 Universität Heidelberg. All rights reserved.
//

import Foundation
import CoreData
import Evergreen
import Result
import Freddy
import PromiseKit


// TODO: separate from Core Data using a `PersistenceProvider` protocol that NSManagedObjectContext conforms to

// TODO: move background execution here using a `ContextProvider` protocol with `newBackgroundContext()` and `mainContext`

// TODO: implement deduplication

protocol EntityRepresentable {
    
    static var entityName: String { get }

}

protocol Identifyable: EntityRepresentable {
    
    static var identificationAttributeName: String { get }
    
}

struct PropertyMapping {
    
    let name: String
    let key: String
    
    init(key: String, name: String) {
        self.name = name
        self.key = key
    }
    
}

func map(propertyNamed propertyName: String, toKey key: String) -> PropertyMapping {
    return PropertyMapping(key: key, name: propertyName)
}
func map(key key: String, toPropertyNamed propertyName: String) -> PropertyMapping {
    return PropertyMapping(key: key, name: propertyName)
}

// TODO: provide shortcut for snake_case mapping

extension PropertyMapping: StringLiteralConvertible {
    
    init(stringLiteral value: StringLiteralType) {
        self.init(key: value, name: value)
    }
    typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        self.init(key: value, name: value)
    }
    typealias UnicodeScalarLiteralType = StringLiteralType
    init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        self.init(key: value, name: value)
    }
    
}

extension PropertyMapping: Hashable, Equatable {
    
    var hashValue: Int {
        return name.hashValue // TODO: is this enough?
    }
    
}

func ==(lhs: PropertyMapping, rhs: PropertyMapping) -> Bool {
    return lhs.name == rhs.name && lhs.key == rhs.key
}



protocol Fillable: EntityRepresentable { // TODO: rename?

    static var persistableProperties: Set<PropertyMapping> { get } // TODO: rename?

    func setValue(value: JSON, forProperty: PropertyMapping) -> Promise<Void> // TODO: make un-overrideable?

}

extension Fillable {
    
    static var persistablePropertiesByKey: [String: PropertyMapping] {
        return persistableProperties.reduce([:]) { persistablePropertiesByKey, property in
            var persistablePropertiesByKey = persistablePropertiesByKey
            persistablePropertiesByKey[property.key] = property
            return persistablePropertiesByKey
        }
    }
    static var persistablePropertiesByName: [String: PropertyMapping] { // TODO: reuse code from above
        return persistableProperties.reduce([:]) { persistablePropertiesByKey, property in
            var persistablePropertiesByKey = persistablePropertiesByKey
            persistablePropertiesByKey[property.name] = property
            return persistablePropertiesByKey
        }
    }
    
    func fillWith(values: [String: JSON]) {
        let mappingLogger = Evergreen.getLogger("Persist.Mapping")
        let logger = Evergreen.getLogger("Persist.Fill")
        
        for (key, value) in values {
            guard let propertyMapping = Self.persistablePropertiesByKey[key] else {
                mappingLogger.debug("No property mapping for key \(key) available, skipping.")
                continue
            }
            
            self.setValue(value, forProperty: propertyMapping).error { error in
                logger.warning("Could not set \(value) for property \(propertyMapping).", error: error)
            }
        }
        
        logger.verbose("Filled object with attribute values, it is now: \(self)")
    }

}

protocol Persistable: Identifyable, Fillable {}

extension Persistable {
    
    static var identificationProperty: PropertyMapping? {
        return persistablePropertiesByName[identificationAttributeName]
    }
    
}


enum PersistError: ErrorType, CustomStringConvertible {
    case Underlying(ErrorType)
    var description: String {
        switch self {
        case .Underlying(let error): return String(error)
        }
    }
}

typealias Completion = (Result<[NSManagedObject], PersistError>) -> Void
typealias ChangesPromise = Promise<[NSManagedObject]>


enum Persist<EntityType: Persistable> {
    
    static func changes(jsonData: NSData, context: NSManagedObjectContext, predicate: NSPredicate? = nil, completion: Completion?) {
        self.changes(jsonData, context: context, predicate: predicate).then { changes -> Void in
            completion?(.Success(changes))
        }.error { error in
            switch error {
            case let error as PersistError:
                completion?(.Failure(error))
            default:
                completion?(.Failure(.Underlying(error))) // TODO: simplify
            }
        }
    }
    
    static func changes(jsonData: NSData, context: NSManagedObjectContext, predicate: NSPredicate? = nil) -> ChangesPromise {
        return Promise<JSON> { fulfill, reject in
            let logger = Evergreen.getLogger("Persist.Parse")
            
            // parse json
            let json: JSON
            do {
                json = try JSON(data: jsonData)
            } catch {
                logger.error("Failed to parse JSON from data.", error: error)
                reject(error)
                return
            }
            logger.verbose("Parsed JSON: \(json)")
            
            fulfill(json)
            
        }.then { json in
            // pass forward
            return self.changes(json, context: context, predicate: predicate)
        }
    }
    
    static func changes(json: JSON, context: NSManagedObjectContext, predicate: NSPredicate? = nil) -> ChangesPromise {
        let logger = Evergreen.getLogger("Persist")

        logger.debug("Persisting changes of entity \(EntityType.self)...")
        
        return filledObjects(ofEntity: EntityType.self, withRepresentation: json, context: context)
        
    }
    
}

private func filledObjects(ofEntity entityType: Fillable.Type, withRepresentation objectsRepresentation: JSON, context: NSManagedObjectContext) -> Promise<[NSManagedObject]> {
    let logger = Evergreen.getLogger("Persist")

    switch objectsRepresentation {
        
    case .Array(let objectRepresentations):
        
        // interpret as array of object representations

        // TODO: delete objects that are not included in objectRepresentations but that match the predicate
        
        logger.verbose("Found array of changes to \(entityType.self), processing each entry: \(objectsRepresentation)")

        // retrieve objects
        return when(objectRepresentations.map { objectsRepresentation in
            filledObjects(ofEntity: entityType.self, withRepresentation: objectsRepresentation, context: context).recover { error -> [NSManagedObject] in
                logger.warning("Failed processing changes \(objectsRepresentation).", error: error)
                return []
            }
        }).then { objects in
            return objects.flatMap({ $0 })
        }
        
    case .Dictionary(let objectRepresentation):
        
        // interpret as object representation

        logger.verbose("Found dictionary representation of change to \(entityType.self): \(objectsRepresentation)") // TODO: just log once before switch?
        
        // retrieve object
        return filledObject(ofEntityNamed: entityType.entityName, withPropertyValues: objectRepresentation, identificationProperty: (entityType.self as? Persistable.Type)?.identificationProperty, context: context).then { object in
            return [ object ]
        }
        
    case .Bool, .Double, .Int, .String:
        
        // interpret as identification key

        logger.verbose("Found identification value \(objectsRepresentation) of change to \(entityType.self).")
        
        guard let identifyableEntityType = entityType as? Identifyable.Type else {
            return Promise(error: FillError.NonIdentifyableType(named: entityType.entityName))
        }

        // retrieve object
        return stub(objectOfEntityNamed: entityType.entityName, withValue: objectsRepresentation, ofIdentificationAttributeNamed: identifyableEntityType.identificationAttributeName, context: context).then { object in
            return [ object ]
        }
        
    case .Null:
        
        // interpret as empty list of object representations
        
        return Promise([])

    }

}


private func filledObject<EntityType: Fillable>(withPropertyValues propertyValues: [String: JSON], context: NSManagedObjectContext) -> Promise<EntityType> {
    return filledObject(ofEntityNamed: EntityType.entityName, withPropertyValues: propertyValues, identificationProperty: (EntityType.self as? Persistable.Type)?.identificationProperty, context: context).then { object in
        guard let object = object as? EntityType else {
            return Promise(error: FillError.InvalidObjectType(ofEntityNamed: EntityType.entityName))
        }
        return Promise(object)
    }
}

private func filledObject(ofEntityNamed entityName: String, withPropertyValues propertyValues: [String: JSON], identificationProperty: PropertyMapping?, context: NSManagedObjectContext) -> Promise<NSManagedObject> {
    
    let object: Promise<NSManagedObject>
    
    if let identificationProperty = identificationProperty {
        
        // entity is identifyable, stub object
        
        // retrieve identification value
        guard let identificationValue = propertyValues[identificationProperty.key] else {
            return Promise(error: FillError.IdentificationValueNotFound(key: identificationProperty.key))
        }
        
        // retrieve object
        object = stub(objectOfEntityNamed: entityName, withValue: identificationValue, ofIdentificationAttributeNamed: identificationProperty.name, context: context)
        
    } else {
        
        // entity is not identifyable, just create object

        object = Promise { fulfill, reject in
            context.performBlock {
                
                // create object
                let object = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: context)
                
                fulfill(object)
            }
        }
        
    }
    
    return object.then { object in
        
        // fill object with attribute values
        guard let fillableObject = object as? Fillable else {
            return Promise(error: FillError.NonFillableType(named: entityName))
        }
        fillableObject.fillWith(propertyValues)
        
        return Promise(object)
    }
}


private func stub<EntityType: Identifyable>(identificationValue identificationValue: JSON, context: NSManagedObjectContext) -> Promise<EntityType> {
    return stub(objectOfEntityNamed: EntityType.entityName, withValue: identificationValue, ofIdentificationAttributeNamed: EntityType.identificationAttributeName, context: context).then { object in
        guard let object = object as? EntityType else {
            return Promise(error: FillError.InvalidObjectType(ofEntityNamed: EntityType.entityName))
        }
        return Promise(object)
    }
}

private func stub(objectOfEntityNamed entityName: String, withValue identificationValueJSON: JSON, ofIdentificationAttributeNamed identificationAttributeName: String, context: NSManagedObjectContext) -> Promise<NSManagedObject> {
    let logger = Evergreen.getLogger("Persist.Stub")
    
    // retrieve identification attribute
    guard let entity = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context) else {
        return Promise(error: FillError.UnknownEntity(named: entityName))
    }
    guard let identificationAttributeDescription = entity.attributesByName[identificationAttributeName] else {
        return Promise(error: FillError.IdentificationAttributeNotFound(named: identificationAttributeName, entityName: entityName))
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
                let fetchRequest = NSFetchRequest(entityName: entityName)
                let identificationPredicate = NSPredicate(format: "%K = %@", identificationAttributeName, identificationValue)
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
                        logger.warning("Found multiple existing objects with identification predicate \(identificationPredicate), choosing any: \(objects)")
                    }
                    let object = objects.first!
                    logger.verbose("Found existing object for representation: \(object)")
                    
                    fulfill(object)
                } else {
                    
                    // create object
                    // TODO: option to disable stubbing
                    logger.debug("Could not find object with identification predicate \(identificationPredicate), creating one.")
                    let object = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: context)
                    object.setValue(identificationValue, forKey: identificationAttributeName)
                    
                    fulfill(object)
                }
                
            }
            
        }
        
    }

}


enum FillError: ErrorType, CustomStringConvertible {
    case InvalidObjectType(ofEntityNamed: String)
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
    case NonIdentifyableType(named: String)
    case NonFillableType(named: String)
    case NonPersistableType(named: String)
    case ContextUnavailable
    
    var description: String {
        switch self {
        case .InvalidObjectType(ofEntityNamed: let entityName): return "Object of entity \(entityName) does not match the given \(Persistable.self) type."
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
        case .NonIdentifyableType(named: let name): return "\(name) does not conform to \(Identifyable.self)."
        case .NonFillableType(named: let name): return "\(name) does not conform to \(Fillable.self)."
        case .NonPersistableType(named: let name): return "\(name) does not conform to \(Persistable.self)."
        case .ContextUnavailable: return "Context unavailable, was the object deleted from its context?"
        }
    }
}

extension Fillable where Self: NSManagedObject {
    
    func setValue(value: JSON, forProperty property: PropertyMapping) -> Promise<Void> {
        let logger = Evergreen.getLogger("Persist.Fill")
        let object = self as NSManagedObject // workaround for "ambiguous use of setValue:forKey" compiler error
        
        if let attribute = entity.attributesByName[property.name] {
            
            return Promise { fulfill, reject in
                // transform to attribute type
                let newValue: NSObject?
                do {
                // TODO: use custom transformers
                    newValue = try value.transformedTo(attribute.attributeType)
                } catch {
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

            // retrieve destination objects
            return filledObjects(ofEntity: destinationEntityType.self, withRepresentation: value, context: context).then { destinationObjects in
                Promise { fulfill, reject in
                    context.performBlock {
                    
                        // assign to relationship
                        // TODO: remove as! NSObject force casts
                        let object = self as NSManagedObject // workaround for "ambiguous use of setValue:forKey" compiler error
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
            return Promise(error: FillError.PropertyNotFound(named: property.name))
        }
    
    }

}

extension JSON {
    
    enum TransformationError: ErrorType {
        case NotImplemented
    }
    
    private func transformedTo(attributeType: NSAttributeType) throws -> NSObject? {
        switch attributeType {
        case .DateAttributeType:
            switch self {
            case .String(let stringValue):
                let transformer = ISO8601DateTransform() // TODO: fallback to others
                return try transformer.transform(stringValue)
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .BooleanAttributeType:
            switch self {
            case .Bool(let boolValue): return boolValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .StringAttributeType:
            switch self {
            case .String(let stringValue): return stringValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .Integer16AttributeType, .Integer32AttributeType, .Integer64AttributeType:
            switch self {
            case .Int(let intValue): return intValue
            case .Null: return nil
            default:
                throw TransformationError.NotImplemented
            }
        case .FloatAttributeType, .DoubleAttributeType:
            switch self {
            case .Int(let intValue): return intValue
            case .Double(let doubleValue): return doubleValue
            default:
                throw TransformationError.NotImplemented
            }
        case .TransformableAttributeType:
            throw TransformationError.NotImplemented
        default:
            throw TransformationError.NotImplemented
        }
    }
    
//    private var objectValue: NSObject {
//        switch self {
//        case .Bool(let boolValue): return boolValue
//        case .Int(let intValue): return intValue
//        case .Double(let doubleValue): return doubleValue
//        case .String(let stringValue): return stringValue
//        case .Null: return NSNull()
//        case .Array(let arrayValue): return NSArray(array: arrayValue.map({ $0.objectValue }))
//        case .Dictionary(let dictionaryValue): return NSDictionary(dictionary: dictionaryValue.reduce([:]) { objectDictionary, row in
//                var objectDictionary = objectDictionary
//                objectDictionary[row.0] = row.1.objectValue
//                return objectDictionary
//            })
//        }
//    }
}

protocol Transformer {
    
    associatedtype FromType
    associatedtype ToType
    
    func transform(value: FromType) throws -> ToType
    
}

class URLTransformer: Transformer {
    
    typealias FromType = String
    typealias ToType = NSURL?
    
    enum URLTransformationError: ErrorType {
        case InvalidFormat(String)
    }
    
    func transform(value: String) throws -> NSURL? {
        guard !value.isEmpty else {
            return nil
        }
        guard let url = NSURL(string: value) else {
            throw URLTransformationError.InvalidFormat(value)
        }
        return url
    }
    
}

class FormattedDateTransformer: Transformer {
    
    typealias FromType = String
    typealias ToType = NSDate?
    
    let dateFormatter: NSDateFormatter
    
    init(dateFormatter: NSDateFormatter) {
        self.dateFormatter = dateFormatter
    }
    
    enum FormattedDateTransformationError: ErrorType {
        case InvalidFormat(String)
    }
    
    func transform(value: String) throws -> NSDate? {
        guard !value.isEmpty else {
            return nil
        }
        guard let result = dateFormatter.dateFromString(value) else {
            throw FormattedDateTransformationError.InvalidFormat(value)
        }
        return result
    }
    
}

class ISO8601DateTransform: FormattedDateTransformer {
    
    init() {
        let dateFormatter = NSDateFormatter()
        dateFormatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        super.init(dateFormatter: dateFormatter)
    }
    
}