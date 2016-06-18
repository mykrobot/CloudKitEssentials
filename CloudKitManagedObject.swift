//
//  CloudKitManagedObject.swift
//  CloudkitManager
//
//  Created by Michael Mecham on 6/17/16.
//  Copyright © 2016 MichaelMecham. All rights reserved.
//

import Foundation
import CoreData
import CloudKit

@objc protocol CloudKitManagedObject {
    var timestamp: NSDate { get set }
    var recordIDData: NSData? { get set } // Set with the Syncable Object Class
    var recordName: String { get set }
    var recordType: String { get }
    var cloudKitRecord: CKRecord? { get } // essentially the cloudKit version of 'dictionaryCopy'
    
    init?(record: CKRecord, context: NSManagedObjectContext) // Make all subclasses have this as a convenience required init
}

extension CloudKitManagedObject {
    var isSynced: Bool {
        return recordIDData != nil
    }
    
    var cloudKitRecordID: CKRecordID? {
        guard let recordIDData = recordIDData,
            let recordID = NSKeyedUnarchiver.unarchiveObjectWithData(recordIDData) as? CKRecordID else {
                return nil
        }
        return recordID
    }
    
    var cloudKitReference: CKReference? { // Essentially the same as a CoreData relationship
        guard let recordID = cloudKitRecordID else {
            return nil
        }
        return CKReference(recordID: recordID, action: .None)
    }
    
    func update(record: CKRecord) {
        self.recordIDData = NSKeyedArchiver.archivedDataWithRootObject(record.recordID)
        do {
            try Stack.sharedStack.managedObjectContext.save()
        } catch {
            print("Unable to save Managed Object Context: \(error)")
        }
    }
    
    func nameForManagedObject() -> String {
        return NSUUID().UUIDString
    }
}