import CloudKit

/**
 Lays the foundation for fetching records from iCloud, as well as uploading to and deleting records from the cloud. The cloud kit handler
 fetches based on intervals set by the user. It will for example fetch records in an interval of 10. In a case where there is a total of
 25 records, it'll fetch record 1-10, then 11-20, thereafter 21-25. It uses the CKQueryCursor to know which records it'll fetch during
 the next batch.
 */
@available(iOS 10.0, *)
public protocol CloudKitHandler: AnyObject, PropertyStoring {

    /**
     The database the handler fetches from, uploads to and deletes records from.
     */
    var database: CKDatabase { get }
    
    /**
     The query the handler will fetch by. See [NSPredicate](https://developer.apple.com/documentation/foundation/nspredicate)
     and [NSSortDescriptor](https://developer.apple.com/documentation/foundation/nssortdescriptor) for more information on how the
     query can be set up.
     */
    var query: CKQuery? { get }
    
    /**
     The amount of records fetched per batch.
     */
    var interval: Int { get }
    
    /**
     The cursor which keeps control over which records that are to be fetched during the next batch. Is set to nil when all the records are fetched.
     */
    var cursor: CKQueryCursor? { get set }
    
    /**
     Indicates whether the library should deal with offline situations where it stores records locally temporarily, and uploads them when a connection
     is aquired.
    */
    var offlineSupport: Bool { get set }
    
    /**
     Fetches the records stored in iCloud based on the parameters given to the cloud kit fetcher.
     
     - parameters
     - completionHandler: encapsulates the records fetched and errors, if any.
     */
    func fetch(withCompletionHandler completionHandler: @escaping ([CKRecord]?, CKError?) -> Void)
    
    /**
     Uploads a CKRecord to the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to upload.
        - completionHandler: Is fired after an upload attempt.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to upload to iCloud or save locally.
     */
    func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?)
    
    /**
     Will set up to retry the upload after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the upload function again with the same arguments.
     
     - parameters:
        - error: The error causing the record upload to fail
        - record: The record which the handler will try to upload again
        - completionHandler: The completion handler given to the upload function
     */
    func retryUploadAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?)
    
    /**
     Deletes a CKRecord from the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to delete.
        - completionHandler: Is fired after a deletion attempt.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to delete from iCloud or delete from local storage.
     */
    func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?)
    
    /**
     Will set up to retry the deletion after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the delete function again with the same arguments.
     
     - parameters:
        - error: The error causing the record deletion to fail
        - record: The record which the handler will try to delete again
        - completionHandler: The completion handler given to the delete function
     */
    func retryDeletionAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?)
}

/**
 An enum which defines if the cloud kit fetcher has more to fetch or not. Is used to control the fetch operation in further detail.
 */
public enum FetchState {
    case more, none
}

public struct LocalStorageError: Error {
    public let description: String
}

private var fetchKey: UInt8 = 0

private let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
private let ArchiveURL = DocumentsDirectory.appendingPathComponent("records")

@available(iOS 10.0, *)
public extension CloudKitHandler {
    
    typealias T = FetchState
    
    /**
     Makes it possible to control in further detail how multiple fetch request based on different parameters are executed.
     An example would be to fetch search results, where the cursor is set to nil, this state is set to more and another query is given based on the search terms.
     */
    public var fetchState: FetchState {
        get { return getAssociatedObject(&fetchKey, defaultValue: .more)}
        set { return setAssociatedObject(&fetchKey, value: newValue)}
    }
    
    // MARK: Local records
    
    private func save(localRecord: CKRecord) -> Bool {
        var localRecords = loadLocalRecords()
        
        print("Attempting to save record locally... \(localRecord)")
        localRecords.append(localRecord)
        
        let completedSave = NSKeyedArchiver.archiveRootObject(localRecords, toFile: ArchiveURL.path)
        print("Save completed sucessfully: \(completedSave)")
        
        return completedSave
    }
    
    private func delete(localRecord: CKRecord) -> Bool {
        var localRecords = loadLocalRecords()
        
        if let index = localRecords.index(where: { $0.recordID == localRecord.recordID }) {
            print("Attempting to delete local record... \(localRecord)")
            localRecords.remove(at: index)
            
            let completedDelete = NSKeyedArchiver.archiveRootObject(localRecords, toFile: ArchiveURL.path)
            print("Deletion completed sucessfully: \(completedDelete)")

            return completedDelete
        }
        
        return false
    }
    
    private func eraseLocalRecords() {
        if !loadLocalRecords().isEmpty {
            let completed = NSKeyedArchiver.archiveRootObject([], toFile: ArchiveURL.path)
            print("Attempting to erease local records...")
            print("Ereasing completed sucessfully: \(completed)")
        }
    }
    
    private func loadLocalRecords() -> [CKRecord] {
        guard let records = NSKeyedUnarchiver.unarchiveObject(withFile: ArchiveURL.path) as? [CKRecord] else {
            return []
        }

        return records
    }
    
    // MARK: Fetching
    
    public func fetch(withCompletionHandler completionHandler: @escaping ([CKRecord]?, CKError?) -> Void) {
        var operation: CKQueryOperation!
        var array = [CKRecord]()
        
        if cursor == nil {
            guard let query = query else {
                completionHandler(nil, CKError(_nsError: NSError(domain: "ck fetch", code: CKError.serviceUnavailable.rawValue, userInfo: nil)))
                return
            }
            
            operation = CKQueryOperation(query: query)
        }
        else {
            operation = CKQueryOperation(cursor: cursor!)
        }
        
        operation.resultsLimit = interval
        operation.qualityOfService = .userInitiated
        operation.recordFetchedBlock = { [unowned self] in
            if self.fetchState == .more {
                array.append($0)
            }
        }
        
        operation.queryCompletionBlock = { [unowned self] (cursor, error) in
            if cursor != nil {
                self.cursor = cursor
            }
            else {
                self.fetchState = .none
            }
            
            var localRecords = self.loadLocalRecords()
            print("Fetched \(localRecords.count) local records")
            // Local records
            if self.offlineSupport, !localRecords.isEmpty  {
                // We erase the local storage after storing the records in memory so that we don't duplicate the array every time.
                self.eraseLocalRecords()

                let completion: ((CKRecord?, Error?) -> Void) = { (record, error) in
                    // Move uploaded record over to the record and remove it from the local records if the upload is successful.
                    if let record = record {
                        print("Local record uploaded successfully, deleting from local storage")
                        array.append(record)
                        localRecords.remove(at: localRecords.index(of: record)!)
                        _ = self.delete(localRecord: record)
                    }
                }
                
                localRecords.forEach({ (record) in
                    print("Attempting to upload local record")
                    self.upload(record: record, withCompletionHandler: { (uploadedRecord, error) in
                        guard error == nil else {
                            self.retryUploadAfter(error: error as? CKError, withRecord: record, andCompletionHandler: nil)
                            return
                        }
               
                        completion(uploadedRecord, error)
                    })
                })
                
                array.append(contentsOf: localRecords)
                // This will try to sort by the given sort descriptors of the query, but if the record was created offline it will not include
                // creation date and other parameters of the CKRecord as they seem to be assigned upon successfull upload.
                // A workaround is to add own parameters for e.g. date and sort by them, as creationDate is read only.
                if let sortDescriptors = self.query?.sortDescriptors {
                    array = array.sorted(sortDescriptors: sortDescriptors)
                }
            }
            
            completionHandler(array, error as? CKError)
        }
        
        database.add(operation)
    }
    
    // MARK: Uploading and deletion
    
    public func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?) {
        database.save(record) { (savedRecord, error) in
            
            if self.offlineSupport, error != nil  {
                print("Upload failed, saving locally...")
                if !self.save(localRecord: record) {
                    completionHandler?(nil, error)
                    return
                }
            }

            completionHandler?(savedRecord != nil ? savedRecord : record, error)
        }
    }


    public func retryUploadAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.upload(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }

    public func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?) {
        let localRecords = loadLocalRecords()
        
        // If the record to be deleted exist in the local records
        if offlineSupport, let index = localRecords.index(where: { $0.recordID == record.recordID }), !delete(localRecord: localRecords[index]) {
            completionHandler?(nil, LocalStorageError(description: "Could not delete local record..."))
        }
        else {
            database.delete(withRecordID: record.recordID) { (deletedRecordID, error) in
                completionHandler?(deletedRecordID, error)
            }
        }
    }

    public func retryDeletionAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
}
