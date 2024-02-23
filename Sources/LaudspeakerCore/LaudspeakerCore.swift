// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import UserNotifications
import Foundation
import FirebaseMessaging
import UserNotifications
import CryptoKit
import CommonCrypto
import Starscream
import SocketIO

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
    private var storage: LaudspeakerStorage
    private let defaultURLString = "https://laudspeaker.com"
    private let manager: SocketManager
    private var socket: SocketIOClient?
    private var apiKey: String?
    private var isPushAutomated: Bool = false
    public var isConnected: Bool = false
    private var endpointUrl: String?
    
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
        return self.storage.getItem(forKey: "customerId") ?? ""
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
    
    public init(storage: LaudspeakerStorage? = nil, url: String? = nil, apiKey: String? = nil, isPushAutomated: Bool? = nil) {
        self.storage = storage ?? UserDefaultsStorage()
        self.apiKey = apiKey
        self.isPushAutomated = isPushAutomated ?? false
        
        var urlString = url ?? defaultURLString
        self.endpointUrl = urlString
        urlString = LaudspeakerCore.trimmedURL(from: urlString) ?? urlString
        guard let urlObject = URL(string: urlString) else {
            fatalError("Invalid URL")
        }
        // Use SocketManager to manage the connection
        self.manager = SocketManager(socketURL: urlObject, config: [
            .log(true),
            .compress,
            .reconnects(false)
        ])
        
        // Initialize the socket using the manager
        socket = manager.defaultSocket
        
        addHandlers()
        loadMessageQueueFromDisk() // Load the message queue from disk
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
    
    private func addHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("LaudspeakerCore connected")
            self?.isConnected = true
            self?.reconnectAttempt = 0
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("LaudspeakerCore disconnected")
            self?.isConnected = false
            
            self?.reconnectWithUpdatedParams()

        }
        
        socket?.on(clientEvent: .error) { [weak self] data, ack in
            print("LaudspeakerCore ERROR",data)
            self?.isConnected = false
            
            self?.reconnectWithUpdatedParams()

        }
        
        socket?.on("customerId") { [weak self] data, ack in
            print("LaudspeakerCore Got customerId")
            
            if let customerId = data[0] as? String {
                print(customerId)
                
                self?.storage.setItem(customerId, forKey: "customerId")
                
                // Tried to see if there was a way to update the auth string via query
                // Doesn't look like there is
                //self?.socket?.manager?.socketURL.query(false).
                
                self?.authParams = [
                    "apiKey": self?.apiKey ?? "",
                    "customerId": customerId,
                    "development": false
                ]
                
                //self?.socket?.manager.
                
                if ((self?.isPushAutomated) == true) {
                    self?.sendFCMToken()
                }
            }
        }
        
        socket?.on("log") {data, ack in
            print("LaudspeakerCore LOG")
            print(data)
        }
        
        print("added all handlers")
    }
    
    public func identify(distinctId: String, optionalProperties: PropertyDict? = nil) {
        // Ensure the socket is connected before attempting to write
        /*
        guard isConnected else {
            print("Impossible to identify: no connection to API. Try to init connection first")
            return
        }
        */
        
        var messageDict: PropertyDict = ["__PrimaryKey": distinctId]
        if let optionalProps = optionalProperties {
            messageDict["optionalProperties"] = optionalProps
        }
        
        //socket?.emit("identify", messageDict)
        emitMessage(channel: "identify", payload: messageDict)
    }
    
    public func set(properties: PropertyDict) {
        // Ensure the socket is connected before attempting to write
        /*
        guard isConnected else {
            print("Impossible to identify: no connection to API. Try to init connection first")
            return
        }
        */
         
        var messageDict: PropertyDict = [:]
        messageDict["optionalProperties"] = properties
        socket?.emit("set", messageDict)
        emitMessage(channel: "set", payload: messageDict)
        
    }
    
    public func sendFCMToken(fcmToken: String? = nil) {
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
    
    public func fire(event: String, payload: [String: Any]? = nil) {
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
    
    public func fireS(event: String, payload: [String: Any]? = nil) {
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
        
        self.socket?.on(clientEvent: .connect) { [weak self] data, ack in
                print("LaudspeakerCore connected")
                self?.isConnected = true
                self?.reconnectAttempt = 0 // Reset the reconnect attempt counter
                self?.resendQueuedMessages()
                self?.onConnect?()  // Call the completion handler if set
        }
    }
    
    public func disconnect() {
        print("disconnected")
        socket?.disconnect()
    }
    
    func reconnectWithUpdatedParams() {
        print("about to try and reconnect")
        if reconnectAttempt >= maxReconnectAttempts {
                print("Maximum reconnection attempts reached. Aborting.")
                print(self.isConnected)
                print("^")
                return
            }
        // Calculate the delay for the current attempt
        let delay = min(maxReconnectDelay, initialReconnectDelay * pow(reconnectMultiplier, Double(reconnectAttempt)))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { 
            [weak self] in
            guard let self = self else 
            {
                print("why")
                return
            }
            
            // Ensure the socket is disconnected before attempting to reconnect
            //if self.socket?.status != .connected {
                print("Attempting to reconnect with delay: \(delay) seconds")
                self.socket?.disconnect()
                self.authParams["customerId"] = self.storage.getItem(forKey: "customerId") ?? ""
                self.socket?.connect(withPayload: self.authParams)
                
                // Increase the attempt counter
                self.reconnectAttempt += 1
            //}
        }
    }

    /*
    func reconnectWithUpdatedParams() {
        // Update authParams with the latest customerId
        authParams["customerId"] = self.storage.getItem(forKey: "customerId") ?? ""
        
        // Now attempt to reconnect with updated parameters
        socket?.disconnect() // Ensure socket is disconnected
        socket?.connect(withPayload: authParams)
    }
    */
    
    public func queueMessage(event: String, payload: [String: Any]) {
        let messageDict: [String: Any] = ["event": event, "payload": payload]
        messageQueue.append(messageDict)
        saveMessageQueueToDisk()
    }
    
    private func resendQueuedMessages() {
        
        for message in messageQueue {
            guard let event = message["event"] as? String,
                  let payload = message["payload"] as? [String: Any] else {
                continue
            }
            
            // Emit each message
            emitMessage(channel: event, payload: payload)
        }
        
        // Clear the queue after sending all messages
        messageQueue.removeAll()
        saveMessageQueueToDisk()
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
    
}
