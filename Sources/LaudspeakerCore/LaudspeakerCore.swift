// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import UserNotifications
import Foundation
import FirebaseMessaging
import UserNotifications
import CryptoKit
import CommonCrypto
//import Starscream
//import SocketIO
import Sentry

let retryDelay = 5.0
let maxRetryDelay = 30.0
// 30 minutes in seconds
private let sessionChangeThreshold: TimeInterval = 60 * 30

public typealias PropertyDict = [String: Any]

// for future tracker update
func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    inputData.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(inputData.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}


public protocol LaudspeakerStorage {
    func getItem(forKey key: String) -> String?
    func setItem(_ item: String, forKey key: String)
}

public class UserDefaultsStorage: LaudspeakerStorage {
    public func getItem(forKey key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }
    
    public func setItem(_ item: String, forKey key: String) {
        UserDefaults.standard.set(item, forKey: key)
    }
}

public class LaudspeakerCore {
    
    public var config: LaudspeakerConfig
    private var queue: LaudspeakerQueue?
    private var api: LaudspeakerApi?
    private var newStorage: LaudspeakerNewStorage?
    private var reachability: Reachability?
    
    
    private var sessionManager: LaudspeakerSessionManager?
    private var sessionId: String?
    private var capturedAppInstalled = false
    private var appFromBackground = false
    private var sessionLastTimestamp: TimeInterval?
    private var isInBackground = false
    var now: () -> Date = { Date() }
    
    private let sessionLock = NSLock()
    private let personPropsLock = NSLock()
    
    private var storage: LaudspeakerStorage
    private let defaultURLString = "https://laudspeaker.com"
    ///private let manager: SocketManager
    //private var socket: SocketIOClient?
    private var apiKey: String?
    private var isPushAutomated: Bool = false
    public var isConnected: Bool = false
    private var endpointUrl: String?
    private var context: LaudspeakerContext?
    
    var authParams: [String: Any] = [
        "apiKey": "",
        "customerId":  "",
        "development": false
    ]
    
    private let initialReconnectDelay: Double = 1 // Initial delay in seconds
    private let maxReconnectDelay: Double = 90 // Maximum delay in seconds
    private let reconnectMultiplier: Double = 2 // Multiplier for each attempt
    private let maxReconnectAttempts: Int = 5 // Maximum number of reconnection attempts


    
    private var reconnectAttempt: Int = 0
    private var messageQueue: [[String: Any]] = [] {
        didSet {
            if messageQueue.count > 20 {
                        messageQueue.removeFirst(messageQueue.count - 20)
            }
            saveMessageQueueToDisk()
        }
    }
    
    public func getCustomerId() -> String {
        return self.storage.getItem(forKey: "customerId") ?? "getCustomerId not finding"
    }
    
    private static func trimmedURL(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // Remove path, query, and fragment components to only leave the scheme, host, and port (if any)
        components.path = "/"
        components.query = nil
        components.fragment = nil

        return components.string
    }
    
    private func getRegisteredProperties() -> [String: Any] {
        guard let props = newStorage?.getDictionary(forKey: .registerProperties) as? [String: Any] else {
            return [:]
        }
        return props
    }

    // register is a reserved word in ObjC
    @objc(registerProperties:)
    public func register(_ properties: [String: Any]) {
        /*
        if !isEnabled() {
            return
        }
        */

        let sanitizedProps = sanitizeDicionary(properties)
        if sanitizedProps == nil {
            return
        }

        personPropsLock.withLock {
            let props = getRegisteredProperties()
            let mergedProps = props.merging(sanitizedProps!) { _, new in new }
            newStorage?.setDictionary(forKey: .registerProperties, contents: mergedProps)
        }
    }

    @objc(unregisterProperties:)
    public func unregister(_ key: String) {
        personPropsLock.withLock {
            var props = getRegisteredProperties()
            props.removeValue(forKey: key)
            newStorage?.setDictionary(forKey: .registerProperties, contents: props)
        }
    }
    
    @objc public func getDistinctId() -> String {
        /*
        if !isEnabled() {
            return ""
        }
         */
        return sessionManager?.getDistinctId() ?? "getDistingId Laudspeaker Core not finding"
    }

    @objc public func getAnonymousId() -> String {
        /*
        if !isEnabled() {
            return ""
        }
        */
        if(sessionManager == nil){
            SentrySDK.capture(message: "sessionManger nil on getAnonymousId")
        }
        return sessionManager!.getAnonymousId() //?? ""
    }
    
    @objc public func getFcmToken() -> String {
        /*
        if !isEnabled() {
            return ""
        }
        */
        if(sessionManager == nil){
            SentrySDK.capture(message: "sessionManger nil on getAnonymousId")
        }
        return sessionManager!.getFcmToken() //?? ""
    }
    
    private func rotateSessionIdIfRequired() {
        guard sessionId != nil, let sessionLastTimestamp = sessionLastTimestamp else {
            rotateSession()
            return
        }

        if now().timeIntervalSince1970 - sessionLastTimestamp > sessionChangeThreshold {
            rotateSession()
        }
    }

    private func rotateSession() {
        let newSessionId = UUID().uuidString
        let newSessionLastTimestamp = now().timeIntervalSince1970

        sessionLock.withLock {
            sessionId = newSessionId
            sessionLastTimestamp = newSessionLastTimestamp
        }
    }
    
    // EVENT CAPTURE

    private func dynamicContext() -> [String: Any] {
        var properties = getRegisteredProperties()
        
        /*
        var groups: [String: String]?
        groupsLock.withLock {
            groups = getGroups()
        }
        if groups != nil, !groups!.isEmpty {
            properties["$groups"] = groups!
        }
        */

        var theSessionId: String?
        sessionLock.withLock {
            theSessionId = sessionId
        }
        if let theSessionId = theSessionId {
            properties["$session_id"] = theSessionId
        }
        
        /*
        guard let flags = featureFlags?.getFeatureFlags() as? [String: Any] else {
            return properties
        }
        */
        
        /*
        var keys: [String] = []
        for (key, value) in flags {
            properties["$feature/\(key)"] = value

            var active = true
            let boolValue = value as? Bool
            if boolValue != nil {
                active = boolValue!
            } else {
                active = true
            }

            if active {
                keys.append(key)
            }
        }
        */
        
        /*
        if !keys.isEmpty {
            properties["$active_feature_flags"] = keys
        }
        */

        return properties
    }
    
    private func buildProperties(properties: [String: Any]?,
                                 userProperties: [String: Any]? = nil,
                                 userPropertiesSetOnce: [String: Any]? = nil,
                                 groupProperties: [String: Any]? = nil) -> [String: Any]
    {
        var props: [String: Any] = [:]

        let staticCtx = context?.staticContext()
        let dynamicCtx = context?.dynamicContext()
        //let staticCtx = staticContext()
        //let localDynamicCtx = dynamicContext()
        
        /*
        if staticCtx != nil {
            props = props.merging(staticCtx ?? [:]) { current, _ in current }
        }
        if dynamicCtx != nil {
            props = props.merging(dynamicCtx ?? [:]) { current, _ in current }
        }
        */
        if let staticCtx = staticCtx {
                props = props.merging(staticCtx) { current, _ in current }
        }
            
        if let dynamicCtx = dynamicCtx {
                props = props.merging(dynamicCtx) { current, _ in current }
        }
        
        if userProperties != nil {
            props["$set"] = (userProperties ?? [:])
        }
        if userPropertiesSetOnce != nil {
            props["$set_once"] = (userPropertiesSetOnce ?? [:])
        }
        
        /*
        if groupProperties != nil {
            // $groups are also set via the dynamicContext
            let currentGroups = props["$groups"] as? [String: Any] ?? [:]
            let mergedGroups = currentGroups.merging(groupProperties ?? [:]) { current, _ in current }
            props["$groups"] = mergedGroups
        }
        */
        
        props = props.merging(properties ?? [:]) { current, _ in current }

        return props
    }

    @objc public func flush() {
        /*
        if !isEnabled() {
            return
        }
        */

        queue?.flush()
    }

    @objc public func reset() {
        /*
        if !isEnabled() {
            return
        }
        */

        // storage also removes all feature flags
        newStorage?.reset()
        queue?.clear()
        //flagCallReported.removeAll()
        resetSession()
    }

    private func resetSession() {
        sessionLock.withLock {
            sessionId = nil
            sessionLastTimestamp = nil
        }
    }
    
    public init(storage: LaudspeakerStorage? = nil, url: String? = nil, apiKey: String? = nil, sentryDSN: String? = nil, isPushAutomated: Bool? = nil) {
        self.storage = storage ?? UserDefaultsStorage()
        self.apiKey = apiKey
        self.isPushAutomated = isPushAutomated ?? false
        var urlString = url ?? defaultURLString
        self.endpointUrl = urlString
        
        
        self.config = LaudspeakerConfig(apiKey: apiKey ?? "missing_api", host: urlString)
        
        //self.config.apiKey = apiKey ?? "missing_api"
        
        if let url = URL(string: urlString) {
                self.config.host = url
            } else {
                print("Invalid URL string: \(urlString)")
                // Handle the error as appropriate for your application
                // For example, you might set a default URL or throw an error
            }
        //self.api?.config.host = urlString
        
        //self.config.host = apiKey ?? "missing_api"
        print("values of config are")
        print(self.config.apiKey)
        print(self.config.host)
        sessionManager = LaudspeakerSessionManager(self.config)
        if(sessionManager == nil){
            SentrySDK.capture(message: "sessionManger nil on init")
        }
        let theStorage = LaudspeakerNewStorage(self.config)
        newStorage = theStorage;
        let theApi = LaudspeakerApi(self.config)
        api = theApi;
        do {
            reachability = try Reachability()
        } catch {
            // ignored
        }
        
        
        PackageInitializer.setup(withDSN: sentryDSN)

        
        print("init queue")
        queue = LaudspeakerQueue(self.config, theStorage, theApi, reachability)
        
        queue?.start(disableReachabilityForTesting: config.disableReachabilityForTesting,
                     disableQueueTimerForTesting: config.disableQueueTimerForTesting)
        
        urlString = LaudspeakerCore.trimmedURL(from: urlString) ?? urlString
        guard let urlObject = URL(string: urlString) else {
            fatalError("Invalid URL")
        }
        // Use SocketManager to manage the connection
        /*
        self.manager = SocketManager(socketURL: urlObject, config: [
            .log(true),
            .compress,
            .reconnects(false)
        ])
        */
        // Initialize the socket using the manager
        //socket = manager.defaultSocket
        
        //addHandlers()
        //loadMessageQueueFromDisk() // Load the message queue from disk
    }
    
    @objc public func close() {

        //setupLock.withLock {
            //Laudspeaker.apiKeys.remove(config.apiKey)
            queue?.stop()
            queue = nil
            sessionManager = nil
            config = LaudspeakerConfig(apiKey: "")
            api = nil
            newStorage = nil
            self.reachability?.stopNotifier()
            reachability = nil
            resetSession()
            capturedAppInstalled = false
            appFromBackground = false
            isInBackground = false
                        
        //}
    }
    
    private func saveMessageQueueToDisk() {
         guard let data = try? JSONSerialization.data(withJSONObject: messageQueue, options: []) else { return }
         let fileURL = getDocumentsDirectory().appendingPathComponent("socketMessageQueue.json")
         try? data.write(to: fileURL)
     }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    /*

    public func sendFCMTokenOld(fcmToken: String? = nil) {
        /*
        guard isConnected else {
            print("Impossible to send token: no connection to API. Try to init connection first")
            return
        }
        */
        
        let tokenToSend: String
        
        if let token = fcmToken {
            tokenToSend = token
            
            self.storage.setItem(tokenToSend, forKey: "fcmToken")
            
            let payload: [String: Any] = [
                "type": "iOS",
                "token": tokenToSend
            ]
            //self.socket?.emit("fcm_token", payload)
            self.emitMessage(channel: "fcm_token", payload: payload)
            
        } else {
            DispatchQueue.main.async {
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        print("Error requesting notifications permissions: \(error)")
                        return
                    }
                    guard granted else {
                        print("Permissions not granted")
                        return
                    }
                    
                    Messaging.messaging().token { [weak self] token, error in
                        if let error = error {
                            print("Error fetching FCM token: \(error)")
                            return
                        }
                        guard let token = token else {
                            print("Token is nil")
                            return
                        }
                        
                        print("FCM token found: \(token)")
                        self?.storage.setItem(token, forKey: "fcmToken")
                        
                        let payload: [String: Any] = [
                            "type": "iOS",
                            "token": token
                        ]
                        
                        //self?.socket?.emit("fcm_token", payload)
                        self?.emitMessage(channel: "fcm_token", payload: payload)
                    }
                }
            }
            return
        }
    }
    */
    
    public func fire( event: String,
                        payload: [String: Any]? = nil,
                        userProperties: [String: Any]? = nil,
                        userPropertiesSetOnce: [String: Any]? = nil,
                        groupProperties: [String: Any]? = nil)
    {
        
        //print("in fireH")
        //SentrySDK.capture(message: "in fire")

        guard let queue = queue else {
            return
        }

        // If events fire in the background after the threshold, they should no longer have a sessionId
        /*
        if isInBackground,
           sessionId != nil,
           let sessionLastTimestamp = sessionLastTimestamp,
           now().timeIntervalSince1970 - sessionLastTimestamp > sessionChangeThreshold
        {
            sessionLock.withLock {
                sessionId = nil
            }
        }
        */
        
        //print("this is firing url")
        
        print(api?.config.host);
        
        let eventToSend = LaudspeakerEvent(
            event: event,
            distinctId: getAnonymousId(),
            properties: buildProperties(properties: sanitizeDicionary(payload),
                                        userProperties: sanitizeDicionary(userProperties),
                                        userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce),
                                        groupProperties: sanitizeDicionary(groupProperties)),
            fcm:[ "iosDeviceToken" :getFcmToken()]
        )
        
        if(eventToSend.distinctId == nil){
            SentrySDK.capture(message: "fire distinctId getAnonymousId nil")
        }
        
        print("this is event")
        
        print(eventToSend)
        
        print("adding to queu")
        //SentrySDK.capture(message: "fire - adding to queue")
    

        queue.add(eventToSend)
    }
    
    
    @objc public func identify( distinctId: String) {
        identify(distinctId: distinctId, userProperties: nil, userPropertiesSetOnce: nil)
    }

    @objc(identifyWithDistinctId:userProperties:)
    public func identify( distinctId: String,
                         userProperties: [String: Any]? = nil)
    {
        identify( distinctId: distinctId, userProperties: userProperties, userPropertiesSetOnce: nil)
    }

    @objc(identifyWithDistinctId:userProperties:userPropertiesSetOnce:)
    public func identify( distinctId: String,
                         userProperties: [String: Any]? = nil,
                         userPropertiesSetOnce: [String: Any]? = nil)
    {
        /*
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }
        */
        
        guard let queue = queue, let sessionManager = sessionManager else {
            return
        }
        let oldDistinctId = getDistinctId()
        
        var properties: [String: Any] = [
            "distinct_id": distinctId,
            "$anon_distinct_id": getAnonymousId()
        ]
        
        properties.merge(userProperties ?? [:]) { (current, _) in current }

        queue.add(LaudspeakerEvent(
            event: "$identify",
            distinctId: getAnonymousId(),
            properties: buildProperties(properties: properties,  userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce)),
            fcm:[ "iosDeviceToken" :getFcmToken()]
            //fcmToken: getFcmToken()
        ))

        if distinctId != oldDistinctId {
            // We keep the AnonymousId to be used by decide calls and identify to link the previousId
            //sessionManager.setAnonymousId(oldDistinctId)
            sessionManager.setDistinctId(distinctId)

        }
    }
    
    //
    public func set( properties: [String: Any]? = nil,
                         userProperties: [String: Any]? = nil,
                         userPropertiesSetOnce: [String: Any]? = nil)
    {
        /*
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }
        */
        
        guard let queue = queue, let sessionManager = sessionManager else {
            return
        }
        //let oldDistinctId = getDistinctId()

        queue.add(LaudspeakerEvent(
            event: "$set",
            distinctId: getAnonymousId(),
            properties: buildProperties(properties: sanitizeDicionary(properties), userProperties: sanitizeDicionary(userProperties), userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce)),
            fcm:[ "iosDeviceToken" :getFcmToken()]
        ))
        
    }
    
    //
    
    public func sendFCMToken( fcmToken: String? = nil, userProperties: [String: Any]? = nil, userPropertiesSetOnce: [String: Any]? = nil, groupProperties: [String: Any]? = nil)
    {
        /*
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }
        */
        
        /*
        guard let queue = queue, let sessionManager = sessionManager else {
            return
        }
        //let oldDistinctId = getDistinctId()
        
        self.storage.setItem(fcmToken ?? "", forKey: "fcmToken")
        self.newStorage?.setString(forKey: .fcmToken, contents: fcmToken ?? "fcm_set_token_error")

        queue.add(LaudspeakerEvent(
            event: "$fcm",
            distinctId: getAnonymousId(),
            properties: buildProperties(properties: [
                "iosDeviceToken": fcmToken ?? "",
            ], userProperties: sanitizeDicionary(userProperties), userPropertiesSetOnce: sanitizeDicionary(userPropertiesSetOnce)),
            fcm:[ "iosDeviceToken" :getFcmToken()]
        ))
        */

        
    }
    
    /*
    public func fireS(event: String, payload: [String: Any]? = nil) {
        // Initialize payload string
        let customerId = self.getCustomerId()
        var payloadString = "{}"
        
        // If payload is provided, convert it to JSON string
        if let payload = payload, let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        }
        
        // Create JSON body with dynamic event name, correlationKey, correlationValue, and payload
        let parameters = """
        {
            "correlationKey": "_id",
            "correlationValue": "\(customerId)",
            "source": "mobile",
            "event": "\(event)",
            "payload": \(payloadString)
        }
        """
        
        let postData = parameters.data(using: .utf8)
        
        print("this is firing url")
        
        let fullURLString = (self.endpointUrl ?? "") + "events"

        print(fullURLString);
        
        var request = URLRequest(url: URL(string: (self.endpointUrl ?? "") + "events")!,timeoutInterval: Double.infinity)
        //var request = URLRequest(url: URL(string: "https://api.laudspeaker.com/events/")!,timeoutInterval: Double.infinity)
        request.addValue("Api-Key " + (self.apiKey ?? ""), forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpMethod = "POST"
        request.httpBody = postData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
          guard let data = data else {
            print(String(describing: error))
            return
          }
          //print("response is")
          //print(response)
          //print("response done")
          print(String(data: data, encoding: .utf8)!)
        }

        task.resume()

    }
    */
    
    /*
    public func fireOld(event: String, payload: [String: Any]? = nil) {
        // Initialize payload string
        let customerId = self.getCustomerId()
        var payloadString = "{}"
        
        // If payload is provided, convert it to JSON string
        if let payload = payload, let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        }
        
        var fullPayload: [String: Any] = [:]
        
        fullPayload["eventName"] = event;
        fullPayload["payload"] = payloadString;
        fullPayload["customerId"] = customerId;
        
        emitMessage(channel: "fire", payload: fullPayload)

        
        //socket?.emit("fire", fullPayload)
        
        // Create JSON body with dynamic event name, correlationKey, correlationValue, and payload
        
    }
    
    public var onConnect: (() -> Void)?
    
    public func connect() {
        print("Try to connect")
        
        authParams = [
            "apiKey": self.apiKey ?? "",
            "customerId": self.storage.getItem(forKey: "customerId") ?? "",
            "development": false
        ]
        /*
        let authParams: [String: Any] = [
            "apiKey": self.apiKey ?? "",
            "customerId": self.storage.getItem(forKey: "customerId") ?? "",
            "development": false
        ]
        */
        
        socket?.connect(withPayload: authParams)
        
        /*
        self.socket?.on(clientEvent: .connect) { [weak self] data, ack in
                print("LaudspeakerCore connected")
                self?.isConnected = true
                //self?.reconnectAttempt = 0 // Reset the reconnect attempt counter
                self?.resendQueuedMessages()
                print("sent resendQueue")
                self?.onConnect?()  // Call the completion handler if set
        }
        */
    }
    
    public func disconnect() {
        print("disconnected")
        socket?.disconnect()
    }
    
    func reconnectWithUpdatedParams() {
        print("about to try and reconnect")
        /*
        if reconnectAttempt >= maxReconnectAttempts {
                print("Maximum reconnection attempts reached. Aborting.")
                print(self.isConnected)
                print("^")
                return
            }
         */
        // Calculate the delay for the current attempt
        let delay = min(maxReconnectDelay, initialReconnectDelay * pow(reconnectMultiplier, Double(reconnectAttempt)))
        
        print("Attempting to reconnect with delay: \(delay) seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            [weak self] in
            guard let self = self else 
            {
                print("why")
                return
            }
            // Ensure the socket is disconnected before attempting to reconnect
            //if self.socket?.status != .connected {
            self.socket?.disconnect()
            self.authParams["customerId"] = self.storage.getItem(forKey: "customerId") ?? ""
            self.socket?.connect(withPayload: self.authParams)
            // Increase the attempt counter
            self.reconnectAttempt += 1
            //}
        }
    }
    
    public func queueMessage(event: String, payload: [String: Any]) {
        let messageDict: [String: Any] = ["event": event, "payload": payload]
        messageQueue.append(messageDict)
        saveMessageQueueToDisk()
    }
    
    private func resendQueuedMessages() {
        print("in resendQueudMessages")
        
        for message in messageQueue {
            guard let event = message["event"] as? String,
                  let payload = message["payload"] as? [String: Any] else {
                print("continue for some reason")
                continue
            }
            // Emit each message
            print("about to resend here is message");
            print(event)
            print(payload)
            print("about to resend");
            emitMessage(channel: event, payload: payload)
        }
        // Clear the queue after sending all messages
        messageQueue.removeAll()
        saveMessageQueueToDisk()
        reconnectAttempt = 0;
    }
    
    private func loadMessageQueueFromDisk() {
        let fileURL = getDocumentsDirectory().appendingPathComponent("socketMessageQueue.json")
        if let data = try? Data(contentsOf: fileURL),
           let queue = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            messageQueue = queue
        }
    }
    
    
    public func emitMessage(channel: String, payload: [String: Any]) {
        if isConnected {
            socket?.emit(channel, payload)
            
            } else {
                print("Socket is disconnected. Queuing message for \(channel)")
                queueMessage(event: channel, payload: payload)
                return
            }
    }
    */
    
    func throwError() throws {
        let error = NSError(domain: "com.example.error", code: 1001, userInfo: [NSLocalizedDescriptionKey: "This is a simulated error"])
        throw error
    }
    
    /*
    func crashWithStackOverflow() {
        crashWithStackOverflow()
    }
    */
     
    public func testSentryIntegration() {
        //let a = SentrySDK.capture(message: "Test error for Sentry integration")
        SentrySDK.capture(message: "Test error 2 for Sentry integration")
        print("adfasf")
        //print(a)
        print("adfasf")
        //let array = [1, 2, 3]
        //let element = array[5]
        //throwError()
        //crashWithStackOverflow()

        /*
        do {
                // Attempt to run a function that may throw an error
                try throwError()
            } catch let error as NSError {
                // Manually capture the error with Sentry upon catching it
                //SentrySDK.capture(error: error)
                //print("Error captured by Sentry: \(error.localizedDescription)")
            }
         */
        //fatalError("Sentry integration test crash")
        //SentrySDK.capture(message: "Test error 2 for Sentry integration")
    }
    
    func convertTimeToUTC(localTime: String, utcOffsetMinutes: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: utcOffsetMinutes * 60)
        
        guard let time = dateFormatter.date(from: localTime) else {
            return ""
        }
        
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        return dateFormatter.string(from: time)
    }
    
    func isWithinInterval(startTime: String, endTime: String, currentTime: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        guard let start = dateFormatter.date(from: startTime),
              let end = dateFormatter.date(from: endTime),
              let current = dateFormatter.date(from: currentTime) else {
            return false
        }
        
        if start <= end {
            return current >= start && current <= end
        } else { // Handles the over-midnight case
            return current >= start || current <= end
        }
    }
    
    struct QuietHours {
        var start: String
        var end: String
        var timeZone: Int // Assuming this is an offset in minutes from UTC
    }
    
    public func handleData(data: [String: Any]) -> Bool
    {
        guard let quietHoursData = data["quietHours"] as? [String: Any],
                  let start = quietHoursData["start"] as? String,
                  let end = quietHoursData["end"] as? String,
                  let timeZone = quietHoursData["timeZone"] as? Int else {
                print("Error: Quiet hours data is missing or incorrect")
            //decide this later
            return true;
            }

            let quietHours = QuietHours(start: start, end: end, timeZone: timeZone)

            let utcStartTime = convertTimeToUTC(localTime: quietHours.start, utcOffsetMinutes: quietHours.timeZone)
            let utcEndTime = convertTimeToUTC(localTime: quietHours.end, utcOffsetMinutes: quietHours.timeZone)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm"
            dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
            let utcNowString = dateFormatter.string(from: Date())

            let isQuietHour = isWithinInterval(startTime: utcStartTime, endTime: utcEndTime, currentTime: utcNowString)
            
            // Here you can take action based on whether it is quiet hours or not
            if isQuietHour {
                print("It's quiet hours.")
                return true;
            } else {
                print("It's not quiet hours.")
                return false;
            }
        /*
        if !isEnabled() {
            return
        }

        if isOptOutState() {
            return
        }
        */
        
        //let oldDistinctId = getDistinctId()
        //self.storage.setItem(fcmToken ?? "", forKey: "fcmToken")

        
    }
    
    public func logMessageEvent( event: String, userInfo: [AnyHashable : Any])
    {
        print("in logMessageEvent")
        //SentrySDK.capture(message: "in logMessageEvent")
        
        if let stepId = userInfo["stepID"], let customerId = userInfo["customerID"], let workspaceId = userInfo["workspaceID"], let templateId = userInfo["templateID"], let messageId = userInfo["messageID"] {
            print("this is the userInfo in didReceive")
            print(userInfo)
            print("userInfo stepID, customer, workspace, template exist")
            guard let queue = queue else {
                return
            }
            
            let properties = ["stepId": stepId, "customerId": customerId, "workspaceId": workspaceId, "templateId": templateId, "messageId": messageId];

            // If events fire in the background after the threshold, they should no longer have a sessionId
            /*
            if isInBackground,
               sessionId != nil,
               let sessionLastTimestamp = sessionLastTimestamp,
               now().timeIntervalSince1970 - sessionLastTimestamp > sessionChangeThreshold
            {
                sessionLock.withLock {
                    sessionId = nil
                }
            }
            */
            //print("this is firing url")
            print(api?.config.host);
            
            let eventToSend = LaudspeakerEvent(
                event: event,
                distinctId: getAnonymousId(),
                properties: buildProperties(properties: sanitizeDicionary(properties), userProperties: nil, userPropertiesSetOnce: nil
                ),
                fcm:[ "iosDeviceToken" :getFcmToken()],
                source: "message"
                )
            
            if(eventToSend.distinctId == nil){
                SentrySDK.capture(message: "fire distinctId getAnonymousId nil")
            }
                
            //print("this is event")
            print(eventToSend)
            //print("adding to queu")
            //SentrySDK.capture(message: "fire - adding to queue")
            queue.add(eventToSend)
            // Since all required fields exist, proceed to log the message event
            
        } else {
            print("Required userInfo fields are missing")
            print(userInfo)
            return;
        }
        
        

        
    }
}
