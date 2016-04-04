//
//  ContextMerger.swift
//  Pods
//
//  Created by Nils Fischer on 01.04.16.
//
//

import Foundation
import CoreData
import Evergreen


// Currently unused

class ContextMerger: NSObject {
    
    let logger = Evergreen.getLogger("Persist.ContextMerger")
    
    weak var context: NSManagedObjectContext?
    weak var mainContext: NSManagedObjectContext?
    
    let entityType: Identifyable.Type
    
    init(observing context: NSManagedObjectContext, toMergeInto mainContext: NSManagedObjectContext, deduplicatingEntity entityType: Identifyable.Type) {
        self.context = context
        self.mainContext = mainContext
        self.entityType = entityType
        super.init()
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func contextDidSave(notification: NSNotification) {
        guard let mainContext = self.mainContext else {
            logger.warning("Main context was released before changes could be merged into it.")
            return
        }
        mainContext.performBlock {
            
            // merge changes into main context
            self.logger.debug("Merging changes into main context...")
            mainContext.mergeChangesFromContextDidSaveNotification(notification)
                        
            // save
            if mainContext.hasChanges {
                do {
                    self.logger.debug("Saving main context with merged changes.")
                    try mainContext.save()
                } catch {
                    self.logger.error("Failed saving context.", error: error)
                }
            } else {
                self.logger.debug("No need to save main context.")
            }
        }
    }
    
    func beginObserving() {
        guard let context = self.context else {
            logger.warning("Observed context was released before observing began.")
            return
        }
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ContextMerger.contextDidSave(_:)), name: NSManagedObjectContextDidSaveNotification, object: context)
    }
    
}
