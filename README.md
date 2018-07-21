# SwiftyCloudKit

[![Version](https://img.shields.io/cocoapods/v/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![License](https://img.shields.io/cocoapods/l/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![Platform](https://img.shields.io/cocoapods/p/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit)

SwiftyCloudKit is a thin layer above Cloud Kit which makes it easy to implement cloud support into iOS apps.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory. It is strongly recommended to run through the tutorial with the example project.

## Requirements

- Swift 4.2 (use pre 0.1.5 for Swift 4.0)
- iOS: 10.0+

## Installation

SwiftyCloudKit is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SwiftyCloudKit'
```

## Use

SwiftyCloudKit is structured into three submodules: CloudKitFetcher, CloudKitHandler and CloudKitSubscriber. *Note: The library supports offline capabilities. If `offlineSupport` is set to true, and there is a case where an internet connection is not present, the library will store records temporarily locally, and upload them later.*

### CloudKitFetcher

The CloudKitFetcher fetches records from iCloud. Remember to set up a record type at the [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard) first. The protocol requires you to implement four variables, which define how the fetch is executed (read more about these in the documentation or in the example project).

```swift

var database: CKDatabase
var query: CKQuery?
var interval: Int
var cursor: CKQueryOperation.Cursor?
var zoneID: CKRecordZone.ID
var desiredKeys: [String]?
```

Then simply call the fetch function in e.g. viewDidAppear to fetch the records:

```swift
fetch(withCompletionHandler: { (records, error) in
    // Do something with the fetched records.
})
```

### CloudKitHandler

CloudKitHandler allows you to upload and delete mulitple CloudKit records in a single operation. You can specify a priority for the operation and retrieve callbacks on the prorgress for the operation for each record. If an upload or deletion operation fails because of an iCloud error, the error included in the completion handler will be a CKError. If the operation fails because the library didn't detect an internet connection and failed to save or delete locally, it will return a LocalStorageError.

```swift
upload(records: [CKRecord], withPriority priority: QualityOfService, perRecordProgress: ((CKRecord, Double) -> Void)?, andCompletionHandler completionHandler: (([CKRecord]?, Error?) -> Void)?)

```
```swift
func delete(records: [CKRecord], withPriority priority: QualityOfService, perRecordProgress: ((CKRecord, Double) -> Void)?, andCompletionHandler completionHandler: (([CKRecord.ID]?, Error?) -> Void)?)
```

An example:
```swift
let record = CKRecord(recordType: MyRecordType)
record.set(string: "Hello World", key: MyStringKey)
upload(records: [record], withPriority: .userInitiated, perRecordProgress: nil) { (uploadedRecords, error) in
    // Do something with the uploaded record
})
delete(records: [record], withPriority: .userInitiated, perRecordProgress: nil) { (deletedRecordIDs, error) in
    // Do something when the record is deleted
})
```

#### Accessing and setting values of records

There exist helper functions for every type supported by CloudKit. So you can retrieve and set strings, references, data, assets, ints, doubles, locations, dates, lists of the these types, as well as images and videos using the helper functions. If you store a image in the record you'll retrieve an optional UIImage when asking for the image, for a video you'll receive an optional URL to a temporary local file which can be used in an AVPlayer. In that way you don't have to deal with conversion. *Note: As the videos are stored locally as cache, it's necessary to clear the cache from time to time. Call `deleteLocalVideos()` in e.g. `applicationWillTerminate(_ application: UIApplication)` in the AppDelegate to remove them. If you want to remove certain videos, use FileManager (the videos are stored in the documents folder with the filename template video_recordName_key.mov)*

To retrieve values, use `value(_ key: String)`. E.g.:
```swift
let myString = record.string(MyStringKey)
```

In order to set values, use `set(value: Value, key: String)`. E.g:
```swift
record.set(string: "Hello World", key: MyStringKey)
```


### CloudKitSubscriber

A subscription is useful when there are multiple units having read and write access to the same data. An example would be an app which allows multiple users to collaborate on a spreadsheet. The subscription fires a notification when new data is appended, when data is deleted and when data is modified. The example project includes a demo concerning this (be aware that the iOS simulator can't send these notifications, only receive, so test between two iOS devices).

The prerequisites for subscriptions are:
- Adding remote-notification to UIBackgroundModes in info.plist
- Register for remote notifications in the app delegate and post notifications around the app when a push notification is received, which is done the following way:

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.registerForRemoteNotifications()
        
        return true
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let ckqn = CKQueryNotification(fromRemoteNotificationDictionary: userInfo as! [String:NSObject])
        let notification = Notification(name: NSNotification.Name(rawValue: CloudKitNotifications.NotificationReceived),
                                        object: self,
                                        userInfo: [CloudKitNotifications.NotificationKey: ckqn])
        NotificationCenter.default.post(notification)
    }
```

The next step is to conform to the protocol:

```swift
var subscription: CKQuerySubscription

func handleSubscriptionNotification(ckqn: CKQueryNotification) {}
```

And the final step is to subscribe to and unsubscribe from updates. This is necessary as subscriptions are quite expensive:

```swift
// Call in e.g. viewDidAppear
subscribe(_ completionHandler: ((CKError?) -> Void)?)

// Call in e.g. viewDidDisappear
unsubscribe(_ completionHandler: ((CKError?) -> Void)?)
```

## User Data Management

The library includes helper functions to make it easy let users manage their data.

### Retrieving a copy of all data

```swift
retrieveRecords(containerRecordTypes: [CKContainer: [String]]) -> [CKContainer: [CKRecord]]
```

### Erasing

The following methods erases all private and public data created by the user in the given containers.

```swift
erasePrivateData(inContainers containers: [CKContainer], completionHandler: @escaping (Error?) -> Void)
```
```swift
eraseUserCreatedPublicData(containerRecordTypes: [CKContainer: [String]], completionHandler: @escaping (Error?) -> Void)
```

### Restriction

In order to restrict databases and lift restrictions, use the following methods:

```swift
restrict(container: CKContainer, apiToken: String, webToken: String, environment: Environment, completionHandler: @escaping (Error?) -> Void)
```
```swift
unrestrict(container: CKContainer, apiToken: String, webToken: String, environment: Environment, completionHandler: @escaping (Error?) -> Void)
```

Reusable API tokens (created in CloudKit Dashboard) and web tokens are required for the requests to qualify. Create web tokens using:

```swift
restrictTokens(forContainersWithAPITokens containerTokens: [CKContainer: String]) -> [CKContainer:String]
```


## Todo

- Add proper support for macOS, tvOS and watchOS

## Author

Simen Gangstad, simen.gangstad@me.com

## License

SwiftyCloudKit is available under the MIT license. See the LICENSE file for more info.
