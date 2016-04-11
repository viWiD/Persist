//
//  JSONInterpreter.swift
//  Pods
//
//  Created by Nils Fischer on 06.04.16.
//
//

import Foundation
import Freddy
import Evergreen


typealias PropertyValues = [String: JSON]


internal extension JSON {
    
    func map<T>(identificationValueTransform identificationValueTransform: (identificationValue: JSON) throws -> T, propertyValuesTransform: (propertyValues: PropertyValues) throws -> T) throws -> [T] {
        let logger = Evergreen.getLogger("Persist.JSONInterpretation")
        
        switch self {
            
        case .Array(let objectRepresentations):
            
            // interpret as array of object representations
            
            logger.verbose("Found array of object representations, processing each entry: \(objectRepresentations)")
            
            // retrieve objects
            return objectRepresentations.enumerate().flatMap { (index, objectsRepresentation) -> [T] in
                logger.verbose("Processing entry \(index + 1) of \(objectRepresentations.count)...")
                do {
                    return try objectsRepresentation.map(identificationValueTransform: identificationValueTransform, propertyValuesTransform: propertyValuesTransform)
                } catch {
                    logger.error("Failed processing object representation \(objectsRepresentation).", error: error)
                    return []
                }
            }
            
        case .Dictionary(let propertyValues):
            
            // interpret as object representation
            
            logger.verbose("Found object property values: \(propertyValues)")
            
            // retrieve object
            return [ try propertyValuesTransform(propertyValues: propertyValues) ]
            
        case .Bool, .Double, .Int, .String:
            
            // interpret as identification key
            
            logger.verbose("Found object identification value: \(self)")
            
            return [ try identificationValueTransform(identificationValue: self) ]
            
        case .Null:
            
            // interpret as empty list of object representations
            
            logger.verbose("Found \(self) for object representation, ignoring.")
            
            return []
            
        }
        
    }
    
}
