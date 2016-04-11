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
import Freddy
import Result


// TODO: move background execution here using a `ContextProvider` protocol with `newBackgroundContext()` and `mainContext`?
// This would relieve the user from merging the background changes into the main context BUT it would require the core data stack to be structured in a certain way: both mainContext and a backgroundContext must be direct descendents of the persistent store coordinator (or must they?)

//public protocol ContextProvider {
//    
//    var mainContext: NSManagedObjectContext { get }
//    
//    func newBackgroundContext() -> NSManagedObjectContext
//    
//}

// TODO: separate from Core Data using a `PersistenceProvider` protocol that NSManagedObjectContext conforms to

// TODO: make sure to execute everything in background


// MARK: - EntityRepresentable

public protocol EntityRepresentable {
    
    static var entityName: String { get }
    
}


// MARK: - Persistable

public protocol Persistable: Identifyable, Fillable {}

extension Persistable {
    
    internal static var identificationProperty: PropertyMapping? {
        return persistablePropertiesByName[identificationAttributeName]
    }
    
}


public enum PersistError: ErrorType, CustomStringConvertible {
    case InvalidJSONData(underlying: ErrorType), OrphanDeletionFailed(underlying: ErrorType), FillingObjectsFailed(underlying: ErrorType), SaveContextFailed(underlying: ErrorType)
    public var description: String {
        switch self {
        case .InvalidJSONData(underlying: let underlyingError): return "Invalid JSON data: \(underlyingError)"
        case .OrphanDeletionFailed(underlying: let underlyingError): return "Orphan deletion failed: \(underlyingError)"
        case .FillingObjectsFailed(underlying: let underlyingError): return "Filling objects failed: \(underlyingError)"
        case .SaveContextFailed(underlying: let underlyingError): return "Save context failed: \(underlyingError)"
        }
    }
}

public typealias Completion = (Result<[NSManagedObject], PersistError>) -> Void


// - Persist

public enum Persist { // Namespace for `changes` function family
    
    public static func changes(jsonData: NSData, to entityType: Persistable.Type, context: NSManagedObjectContext, scope: NSPredicate? = nil, completion: Completion?) {
        // dispatch on background
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {

            let logger = Evergreen.getLogger("Persist.Parse")
            let traceLogger = Evergreen.getLogger("Persist.Trace")
            traceLogger.tic(andLog: "Parsing \(entityType) JSON data...", forLevel: .Debug, timerKey: "parse_json_\(entityType.entityName)")
            
            // parse json
            let json: JSON
            do {
                json = try JSON(data: jsonData)
            } catch {
                logger.error("Failed to parse JSON from data.", error: error)
                dispatch_sync(dispatch_get_main_queue()) {
                    completion?(.Failure(.InvalidJSONData(underlying: error)))
                }
                return
            }
            traceLogger.toc(andLog: "Parsed \(entityType) JSON data.", forLevel: .Debug, timerKey: "parse_json_\(entityType.entityName)")
            logger.verbose(json)
            
            // pass forward
            self.changes(json, to: entityType.self, context: context, scope: scope, completion: completion)
        }
    }
    
    public static func changes(json: JSON, to entityType: Persistable.Type, context: NSManagedObjectContext, scope: NSPredicate? = nil, completion: Completion?) {
        // dispatch on context's queue
        context.performBlock {
            let contextLogger = Evergreen.getLogger("Persist.Context")
            let traceLogger = Evergreen.getLogger("Persist.Trace")
            traceLogger.debug("Persisting changes of entity \(entityType.self)...")

            // delete orphans
            do {
                
                try deleteOrphans(ofEntity: entityType.self, onlyKeeping: json, context: context, scope: scope)
        
            } catch {
                dispatch_sync(dispatch_get_main_queue()) {
                    completion?(.Failure(.OrphanDeletionFailed(underlying: error)))
                }
                return
            }
            
            // retrieve filled objects
            let objects: [NSManagedObject]
            do {

                objects = try filledObjects(ofEntity: entityType.self, withRepresentation: json, context: context)

            } catch {
                dispatch_sync(dispatch_get_main_queue()) {
                    completion?(.Failure(.FillingObjectsFailed(underlying: error)))
                }
                return
            }
            
            // save
            do {
                
                if context.hasChanges {
                    try context.save()
                    contextLogger.debug("Saved context with changes to \(entityType).")
                } else {
                    contextLogger.debug("Nothing changed for \(entityType), no need to save context.")
                }
                
            } catch {
                contextLogger.error("Failed saving context with changes to \(entityType).", error: error)
                dispatch_sync(dispatch_get_main_queue()) {
                    completion?(.Failure(.SaveContextFailed(underlying: error)))
                }
                return
            }
            
            completion?(.Success(objects))
        }
        
    }
//    public static func changes(json: JSON, contextProvider: ContextProvider, scope: NSPredicate? = nil) -> ChangesPromise {
//        let logger = Evergreen.getLogger("Persist.Trace")
//        logger.debug("Persisting changes of entity \(EntityType.self)...")
//        
//        let context = contextProvider.newBackgroundContext()
//        
//        let contextMerger = ContextMerger(observing: context, toMergeInto: contextProvider.mainContext, deduplicatingEntity: EntityType.self)
//        
//        return filledObjects(ofEntity: EntityType.self, withRepresentation: json, context: context).then { objects in
//            Promise { fulfill, reject in
//                context.performBlock {
//                    
//                    // mainly to keep the context merger from deiniting
//                    contextMerger.beginObserving()
//                 
//                    // save context
//                    do {
//                        try context.save()
//                        logger.debug("Saved changes to \(EntityType.self) in context.")
//                        fulfill(objects)
//                    } catch {
//                        logger.error("Failed saving context.", error: error)
//                        reject(error)
//                    }
//                    
//                }
//            }
//        }
//        
//    }
    
}
