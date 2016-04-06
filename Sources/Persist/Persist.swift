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
import PromiseKit


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

// TODO: Transformers

// TODO: Orphan deletion

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
    case Underlying(ErrorType)
    public var description: String {
        switch self {
        case .Underlying(let error): return String(error)
        }
    }
}

//public typealias Completion = (Result<[NSManagedObject], PersistError>) -> Void
public typealias ChangesPromise = Promise<[NSManagedObject]>


// - Persist

public enum Persist { // Namespace for `changes` function family
    
    // TODO: include this? requires Result dependency
//    public static func changes(jsonData: NSData, to entityType: Persistable.Type, context: NSManagedObjectContext, scope: NSPredicate? = nil, completion: Completion?) {
//        self.changes(jsonData, to: entityType.self, context: context, scope: scope).then { changes -> Void in
//            completion?(.Success(changes))
//        }.error { error in
//            switch error {
//            case let error as PersistError:
//                completion?(.Failure(error))
//            default:
//                completion?(.Failure(.Underlying(error))) // TODO: simplify
//            }
//        }
//    }
    
    public static func changes(jsonData: NSData, to entityType: Persistable.Type, context: NSManagedObjectContext, scope: NSPredicate? = nil) -> ChangesPromise {
        return Promise().thenInBackground {
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
            }
        }.then { json in
            // pass forward
            return self.changes(json, to: entityType.self, context: context, scope: scope)
        }
    }
    
    public static func changes(json: JSON, to entityType: Persistable.Type, context: NSManagedObjectContext, scope: NSPredicate? = nil) -> ChangesPromise {
        let contextLogger = Evergreen.getLogger("Persist.Context")
        let traceLogger = Evergreen.getLogger("Persist.Trace")
        traceLogger.debug("Persisting changes of entity \(entityType.self)...")
        
        // delete orphans
        let changes = deleteOrphans(ofEntity: entityType.self, onlyKeeping: json, context: context, scope: scope).then {
        
            // retrieve objects
            return filledObjects(ofEntity: entityType.self, withRepresentation: json, context: context)
            
        }.then { objects -> ChangesPromise in
            
            // save
            return Promise { fulfill, reject in
                context.performBlock {
                    do {
                        try context.save()
                        contextLogger.debug("Saved context.")
                        fulfill(objects)
                    } catch {
                        contextLogger.error("Failed saving context.", error: error)
                        reject(error)
                    }
                }
            }
            
        }
        
        // enqueue
        return enqueueChanges(changes)
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


// MARK: - Queue

var pending: ChangesPromise?

private func enqueueChanges(changes: ChangesPromise) -> ChangesPromise {
    let logger = Evergreen.getLogger("Persist.Queue")
    guard let pendingChanges = pending where pendingChanges.pending else {
        logger.debug("No changes in queue, executing now.")
        pending = changes
        return changes
    }
    logger.debug("Enqueueing changes...")
    let changes = pendingChanges.then { _ -> ChangesPromise in
        logger.debug("Queue advanced, executing next changes.")
        return changes
    }.recover { _ -> ChangesPromise in
        logger.debug("Queue advanced, executing next changes.")
        return changes
    }
    pending = changes
    return changes
}
