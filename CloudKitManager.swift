//
//  CloudKitManager.swift
//  CloudkitManager
//
//  Created by Michael Mecham on 6/15/16.
//  Copyright © 2016 MichaelMecham. All rights reserved.
//

import UIKit
import CloudKit

private let CreatorUserRecordIDKey = "creatorUserRecordID"
private let LastModifiedUserRecordIDKey = "creatorUserRecordID"
private let CreationDateKey = "creationDate"
private let ModificationDateKey = "modificationDate"

class CloudKitManager {
    
    let publicDatabase = CKContainer.defaultContainer().publicCloudDatabase
    let privateDatabase = CKContainer.defaultContainer().privateCloudDatabase
    
    init() {
        checkCloudKitAvailability()
        requestDiscoverabilityPermissions()
    }
    
    // MARK: - User Info Discovery
    
    func fetchedLoggedInUserRecord(completion: ((record: CKRecord?, error: NSError?) -> Void)?) {
        CKContainer.defaultContainer().fetchUserRecordIDWithCompletionHandler { (recordID, error) in
            if let error = error,
                completion = completion {
                completion(record: nil, error: error)
            }
            
            if let recordID = recordID,
                completion = completion {
                self.fetchRecordWithID(recordID, completion: { (record, error) in
                    completion(record: record, error: error)
                })
            }
        }
    }
    
    func fetchUsernameFromRecordID(recordID: CKRecordID, completion: ((firstName: String?, lastName: String?) -> Void)?) {
        let operation = CKDiscoverUserInfosOperation(emailAddresses: nil, userRecordIDs: [recordID])
        operation.discoverUserInfosCompletionBlock = { (emailsToUserInfos, userRecordsIDsToUserInfos, operationError) -> Void in
            if let userRecordsIDsToUserInfos = userRecordsIDsToUserInfos,
                userInfo = userRecordsIDsToUserInfos[recordID],
                completion = completion {
                completion(firstName: userInfo.displayContact?.givenName, lastName: userInfo.displayContact?.familyName)
            } else if let completion = completion {
                completion(firstName: nil, lastName: nil)
            }
        }
        CKContainer.defaultContainer().addOperation(operation)
    }
    
    func fetchAllDicsoverableUsers(completion: ((userInfoRecords: [CKDiscoveredUserInfo]?) -> Void)?) {
        let operation = CKDiscoverAllContactsOperation()
        operation.discoverAllContactsCompletionBlock = { (discoveredUserInfos, error) -> Void in
            if let completion = completion {
                completion(userInfoRecords: discoveredUserInfos)
            }
        }
        CKContainer.defaultContainer().addOperation(operation)
    }
    
    // MARK: - Fetch Records
    
    func fetchRecordWithID(recordID: CKRecordID, completion: ((record: CKRecord?, error: NSError?) -> Void)?) {
        publicDatabase.fetchRecordWithID(recordID) { (record, error) in
            if let completion = completion {
                completion(record: record, error: error)
            }
        }
    }
    
    func fetchRecordsWithType(type: String, predicate: NSPredicate = NSPredicate(value: true), recordFetchedBlock: ((record: CKRecord) -> Void)?, completion: ((records: [CKRecord]?, error: NSError?) -> Void)?) {
        var fetchedRecords: [CKRecord] = []
        let query = CKQuery(recordType: type, predicate: predicate)
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.recordFetchedBlock = { (fetchedRecord) -> Void in
            fetchedRecords.append(fetchedRecord)
            if let recordFetchedBlock = recordFetchedBlock {
                recordFetchedBlock(record: fetchedRecord)
            }
        }
        queryOperation.queryCompletionBlock = { (queryCurser, error) -> Void in
            if let queryCurser = queryCurser {
                let continuedQueryOperation = CKQueryOperation(cursor: queryCurser)
                continuedQueryOperation.recordFetchedBlock = queryOperation.recordFetchedBlock
                continuedQueryOperation.queryCompletionBlock = queryOperation.queryCompletionBlock
                self.publicDatabase.addOperation(continuedQueryOperation)
            } else {
                if let completion = completion {
                    completion(records: fetchedRecords, error: error)
                }
            }
        }
        self.publicDatabase.addOperation(queryOperation)
    }

    func fetchCurrentUserRecords(type: String, completion: ((records: [CKRecord]?, error: NSError?) -> Void)?) {
        fetchedLoggedInUserRecord { (record, error) in
            if let record = record {
                let predicate = NSPredicate(format: "%K == %@", argumentArray: ["creatorUserRecordID", record.recordID])
                self.fetchRecordsWithType(type, predicate: predicate, recordFetchedBlock: nil, completion: { (records, error) in
                    if let completion = completion {
                        completion(records: records, error: error)
                    }
                })
            }
        }
    }
    
    func fetchRecordsFromDateRange(type: String, fromDate: NSDate, toDate: NSDate, completion: ((records: [CKRecord]?, error: NSError?) -> Void)?) {
        let startDatePredicate = NSPredicate(format: "%K > %@", argumentArray: [CreationDateKey, fromDate])
        let endDatePredicate = NSPredicate(format: "%K < %@", argumentArray: [CreationDateKey, toDate])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [startDatePredicate, endDatePredicate])
        self.fetchRecordsWithType(type, predicate: predicate, recordFetchedBlock: nil) { (records, error) in
            if let completion = completion {
                completion(records: records, error: error)
            }
        }
    }
    
    // MARK: - Delete Methods
    
    func deleteRecordWithID(recordID: CKRecordID, completion: ((recordID: CKRecordID?, error: NSError?) -> Void)?) {
        publicDatabase.deleteRecordWithID(recordID) { (record, error) in
            if let completion = completion {
                completion(recordID: recordID, error: error)
            }
        }
    }
    
    func deleteRecordsWithID(recordsIDs: [CKRecordID], completion: ((records: [CKRecord]?, recordIDs: [CKRecordID]?, error: NSError?) -> Void)?) {
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordsIDs)
        operation.queuePriority = .High
        operation.savePolicy = .IfServerRecordUnchanged
        operation.qualityOfService = .UserInitiated
        operation.modifyRecordsCompletionBlock = { (records, recordIDs, error) -> Void in
            if let completion = completion {
                completion(records: records, recordIDs: recordsIDs, error: error)
            }
        }
        publicDatabase.addOperation(operation)
    }
    
    // MARK: - Save and Modify Methods
    
    func saveRecords(records: [CKRecord], perRecordCompletion: ((record: CKRecord?, error: NSError?) -> Void)?, completion: ((records: [CKRecord]?, error: NSError?) -> Void)?) {
        modifyRecords(records, perRecordCompletion: perRecordCompletion) { (records, error) in
            if let completion = completion {
                completion(records: records, error: error)
            }
        }
    }
    
    func saveRecord(record: CKRecord, completion: ((record: CKRecord?, error: NSError?) -> Void)?) {
        publicDatabase.saveRecord(record) { (record, error) in
            if let completion = completion {
                completion(record: record, error: error)
            }
        }
    }
    
    func modifyRecords(records: [CKRecord], perRecordCompletion: ((record: CKRecord?, error: NSError?) -> Void)?, completion: ((records: [CKRecord]?, error: NSError?) -> Void)?) {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.queuePriority = .High
        operation.savePolicy = .ChangedKeys
        operation.qualityOfService = .UserInteractive
        operation.perRecordCompletionBlock = { (record, error) -> Void in
            if let perRecordCompletion = perRecordCompletion {
                perRecordCompletion(record: record, error: error)
            }
        }
        operation.modifyRecordsCompletionBlock = { (records, recordIDs, error) -> Void in
            if let completion = completion {
                completion(records: records, error: error)
            }
        }
        publicDatabase.addOperation(operation)
    }
    
    // MARK: - Subscriptions
    
    func subscribe(type: String, predicate: NSPredicate, subscriptionID: String, contentAvailable: Bool, alertBody: String? = nil, desiredKeys: [String]? = nil, options: CKSubscriptionOptions, completion: ((subscription: CKSubscription?, error: NSError?) -> Void)?) {
        let subscription = CKSubscription(recordType: type, predicate: predicate, subscriptionID: subscriptionID, options: options)
        let notificationInfo = CKNotificationInfo()
        notificationInfo.alertBody = alertBody
        notificationInfo.shouldSendContentAvailable = contentAvailable
        notificationInfo.desiredKeys = desiredKeys
        subscription.notificationInfo = notificationInfo
        publicDatabase.saveSubscription(subscription) { (subscription, error) in
            if let completion = completion {
                completion(subscription: subscription, error: error)
            }
        }
    }
    
    func unsubscribe(subscriptionID: String, completion: ((subscriptionID: String?, error: NSError?) -> Void)?) {
        publicDatabase.deleteSubscriptionWithID(subscriptionID) { (subscriptionID, error) in
            if let completion = completion {
                completion(subscriptionID: subscriptionID, error: error)
            }
        }
    }
    
    func fetchSubscriptions(completion: ((subscriptions: [CKSubscription]?, error: NSError?) -> Void)?) {
        publicDatabase.fetchAllSubscriptionsWithCompletionHandler { (subscriptions, error) in
            if let completion = completion {
                completion(subscriptions: subscriptions, error: error)
            }
        }
    }
    
    func fetchSubscription(subscriptionID: String, completion: ((subscription: CKSubscription?, error: NSError?) -> Void)?) {
        publicDatabase.fetchSubscriptionWithID(subscriptionID) { (subscription, error) in
            if let completion = completion {
                completion(subscription: subscription, error: error)
            }
        }
    } // READ THE DOCS. Phasma asking for a specific trooper that she has been keeping her eyes on.
    
    // MARK: - CloudKit Permissions
    
    func checkCloudKitAvailability() {
        CKContainer.defaultContainer().accountStatusWithCompletionHandler { (accountStatus: CKAccountStatus, error: NSError?) in
            switch accountStatus {
            case .Available:
                print("CloudKit available.")
            default:
                self.handleCloudKitUnavailable(accountStatus, error: error)
            }
        }
    }
    
    func handleCloudKitUnavailable(accountStatus: CKAccountStatus, error: NSError?) {
        var errorText = "Sync is disabled \n"
        if let error = error {
            errorText += error.localizedDescription
        }
        
        switch accountStatus {
        case .Restricted:
            errorText += "iCloud is not available due to restrictions"
        case .NoAccount:
            errorText += "There is no iCloud account set up. \nYou can setup iCloud in the Settings app"
        default:
            break
        }
        displayCloudKitNotAvailableError(errorText)
    }
    
    func displayCloudKitNotAvailableError(errorText: String) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            let alertController = UIAlertController(title: "iCloud Eync Error", message: "\(errorText)", preferredStyle: .Alert)
            let dismissAction = UIAlertAction(title: "Ok", style: .Cancel, handler: nil)
            alertController.addAction(dismissAction)
            
            if let appDelegate = UIApplication.sharedApplication().delegate,
                appWindow = appDelegate.window!,
                rootViewController = appWindow.rootViewController {
                rootViewController.presentViewController(alertController, animated: true, completion: nil)
            }
        })
    }
    
    // MARK: - CloudKit Discoverability
    
    func requestDiscoverabilityPermissions() {
        CKContainer.defaultContainer().statusForApplicationPermission(.UserDiscoverability) { (permissionStatus, error) in
            if permissionStatus == .InitialState {
                CKContainer.defaultContainer().requestApplicationPermission(.UserDiscoverability, completionHandler: { (permissionStatus, error) in
                    self.handleCloudKitPermissionStatus(permissionStatus, error: error)
                })
            } else {
                self.handleCloudKitPermissionStatus(permissionStatus, error: error)
            }
        }
    }
    
    func handleCloudKitPermissionStatus(permissionStatus: CKApplicationPermissionStatus, error: NSError?) {
        if permissionStatus == .Granted {
            print("User Discoverability Permission Granted. User May Prceed With Full Access")
        } else {
            var errorText = "Sync is disabled \n"
            if let error = error {
                errorText += error.localizedDescription
            }
            switch permissionStatus {
            case .Denied:
                errorText += "You have been denied User Discoverability Permissions. You may be unable to use certain features"
            case .CouldNotComplete:
                errorText += "Unable to verify User Discovery Permissions. You may have a connectivity issue. Please try again."
            default:
                break
            }
            displayCloudKitPermissionsNotGrantedError(errorText)
        }
    }
    
    func displayCloudKitPermissionsNotGrantedError(errorText: String) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            let alertController = UIAlertController(title: "CloudKit Permissions Error", message: "\(errorText)", preferredStyle: .Alert)
            let dismissAction = UIAlertAction(title: "Ok", style: .Cancel, handler: nil)
            alertController.addAction(dismissAction)
            
            if let appDelegate = UIApplication.sharedApplication().delegate,
                appWindow = appDelegate.window!,
                rootViewController = appWindow.rootViewController {
                rootViewController.presentViewController(alertController, animated: true, completion: nil)
            }
        })
    }
}