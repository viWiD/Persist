//
//  JSONInterpreter.swift
//  Pods
//
//  Created by Nils Fischer on 06.04.16.
//
//

import Foundation
import Freddy
import PromiseKit
import Evergreen


typealias PropertyValues = [String: JSON]


internal extension JSON {
    
    func map<T>(identificationValueTransform identificationValueTransform: (identificationValue: JSON) -> Promise<T>, propertyValuesTransform: (propertyValues: PropertyValues) -> Promise<T>) -> Promise<[T]> {
        let logger = Evergreen.getLogger("Persist.JSONInterpretation")
        
        switch self {
            
        case .Array(let objectRepresentations):
            
            // interpret as array of object representations
            
            logger.verbose("Found array of object representations, processing each entry: \(objectRepresentations)")
            
            // retrieve objects
            return when(objectRepresentations.enumerate().map { (index, objectsRepresentation) -> Promise<[T]> in
                logger.verbose("Processing entry \(index + 1) of \(objectRepresentations.count)...")
                return objectsRepresentation.map(identificationValueTransform: identificationValueTransform, propertyValuesTransform: propertyValuesTransform).recover { error -> [T] in
                    logger.error("Failed processing object representation \(objectsRepresentation).", error: error)
                    return []
                }
            }).then { objects in
                return objects.flatMap({ $0 })
            }
            
        case .Dictionary(let propertyValues):
            
            // interpret as object representation
            
            logger.verbose("Found object property values: \(propertyValues)")
            
            // retrieve object
            return propertyValuesTransform(propertyValues: propertyValues).then { object in
                return [ object ]
            }
            
        case .Bool, .Double, .Int, .String:
            
            // interpret as identification key
            
            logger.verbose("Found object identification value: \(self)")
            
            return identificationValueTransform(identificationValue: self).then { object in
                return [ object ]
            }
            
        case .Null:
            
            // interpret as empty list of object representations
            
            logger.verbose("Found \(self) for object representation, ignoring.")
            
            return Promise([])
            
        }
        
    }
    
}
