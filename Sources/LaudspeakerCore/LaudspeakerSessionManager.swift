//
//
//  Created by Abheek Basu on 3/9/24.
//

import Foundation
import Sentry

class LaudspeakerSessionManager {
    private let storage: LaudspeakerNewStorage!

    private let anonLock = NSLock()
    private let distinctLock = NSLock()
    init(_ config: LaudspeakerConfig) {
        storage = LaudspeakerNewStorage(config)
    }

    public func getAnonymousId() -> String {
        var anonymousId: String?
        anonLock.withLock {
            anonymousId = storage.getString(forKey: .anonymousId)

            if anonymousId == nil || anonymousId == "" {
                SentrySDK.capture(message: "anonymousId nil or empty in getAnonymousI")
                anonymousId = UUID().uuidString
                SentrySDK.capture(message: anonymousId ?? "tried to set a new uuid")
                
                setAnonId(anonymousId ?? "anon sessionManger not setting")
            }
        }

        return anonymousId ?? "getAnonymouseId not finding SessionManager"
    }

    public func setAnonymousId(_ id: String) {
        //SentrySDK.capture(message: "setting anonymouse id, setAnonymousId")
        //SentrySDK.capture(message: id)
        anonLock.withLock {
            setAnonId(id)
        }
    }

    private func setAnonId(_ id: String) {
        //SentrySDK.capture(message: "setting anonID, setAnonId")
        storage.setString(forKey: .anonymousId, contents: id)
    }

    public func getDistinctId() -> String {
        var distinctId: String?
        distinctLock.withLock {
            distinctId = storage.getString(forKey: .distinctId) ?? getAnonymousId()
        }
        if(distinctId == nil){
            SentrySDK.capture(message: "distinctId nil or empty in getDistinctId")
        }
        return distinctId ?? "getDistincId not finding Manger"
    }

    public func setDistinctId(_ id: String) {
        distinctLock.withLock {
            storage.setString(forKey: .distinctId, contents: id)
        }
    }
    
    public func getFcmToken() -> String {
        var fcmToken: String?
        distinctLock.withLock {
            fcmToken = storage.getString(forKey: .fcmToken) ?? ""
        }
        if(fcmToken == nil){
            SentrySDK.capture(message: "fcmToken nil or empty in getfcmToken")
        }
        return fcmToken ?? "get fcmToken not finding Manger"
    }
    
    public func setFcmToken(_ fcmToken: String) {
        distinctLock.withLock {
            storage.setString(forKey: .fcmToken, contents: fcmToken)
        }
    }

    public func reset() {
        distinctLock.withLock {
            storage.remove(key: .distinctId)
        }
        anonLock.withLock {
            storage.remove(key: .anonymousId)
        }
    }
}
