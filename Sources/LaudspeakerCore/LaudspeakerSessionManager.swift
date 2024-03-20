//
//
//  Created by Abheek Basu on 3/9/24.
//

import Foundation

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
                anonymousId = UUID().uuidString
                setAnonId(anonymousId ?? "")
            }
        }

        return anonymousId ?? ""
    }

    public func setAnonymousId(_ id: String) {
        anonLock.withLock {
            setAnonId(id)
        }
    }

    private func setAnonId(_ id: String) {
        storage.setString(forKey: .anonymousId, contents: id)
    }

    public func getDistinctId() -> String {
        var distinctId: String?
        distinctLock.withLock {
            distinctId = storage.getString(forKey: .distinctId) ?? getAnonymousId()
        }
        return distinctId ?? ""
    }

    public func setDistinctId(_ id: String) {
        distinctLock.withLock {
            storage.setString(forKey: .distinctId, contents: id)
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
