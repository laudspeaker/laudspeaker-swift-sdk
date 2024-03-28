//
//  LaudspeakerEvent.swift
//  Laudspeaker
//

import Foundation

public class LaudspeakerEvent {
    public var event: String
    public var distinctId: String
    public var properties: [String: Any]
    public var timestamp: Date
    public var uuid: UUID
    public var fcmToken: String

    enum Key: String {
        case event
        case distinctId
        case properties
        case timestamp
        case uuid
        case fcmToken
    }

    init(event: String, distinctId: String, properties: [String: Any]? = nil, timestamp: Date = Date(), fcmToken: String, uuid: UUID = .init()) {
        self.event = event
        self.distinctId = distinctId
        self.properties = properties ?? [:]
        self.timestamp = timestamp
        self.uuid = uuid
        self.fcmToken = fcmToken
    }
    
    /*
    static func fromJSON(_ data: Data) -> LaudspeakerEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }

        return fromJSON(json)
    }
    */
    
    static func fromJSON(_ data: Data) -> LaudspeakerEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }

        return fromPayloadJSON(payload, withAdditionalInfo: json)
    }

    
    static func fromPayloadJSON(_ payload: [String: Any], withAdditionalInfo info: [String: Any]) -> LaudspeakerEvent? {
        guard let event = info["event"] as? String,
              let distinctId = info["correlationValue"] as? String,
              let timestampString = info["timestamp"] as? String,
              let timestamp = toISO8601Date(timestampString),
              let uuidString = info["uuid"] as? String,
              let fcmToken = info["fcmToken"] as? String,
              let uuid = UUID(uuidString: uuidString) else {
            return nil
        }

        return LaudspeakerEvent(
            event: event,
            distinctId: distinctId,
            properties: payload, // Assuming properties are contained within "payload"
            timestamp: timestamp,
            fcmToken: fcmToken,
            uuid: uuid
        )
    }

    static func fromJSON(_ json: [String: Any]) -> LaudspeakerEvent? {
        guard let event = json["event"] as? String else { return nil }

        let timestamp = json["timestamp"] as? String ?? toISO8601String(Date())

        let timestampDate = toISO8601Date(timestamp) ?? Date()

        var properties = (json["properties"] as? [String: Any]) ?? [:]

        // back compatibility with v2
        let setProps = json["$set"] as? [String: Any]
        if setProps != nil {
            properties["$set"] = setProps
        }
        
        guard let distinctId = (json["distinct_id"] as? String) ?? (properties["distinct_id"] as? String) else { return nil }
        
        let fcmToken = json["fcmToken"] as? String ?? ""
        
        let uuid = ((json["uuid"] as? String) ?? (json["message_id"] as? String)) ?? UUID().uuidString
        let uuidObj = UUID(uuidString: uuid) ?? UUID()
        
        return LaudspeakerEvent(
            event: event,
            distinctId: distinctId,
            properties: properties,
            timestamp: timestampDate,
            fcmToken: fcmToken,
            uuid: uuidObj
        )
    }

    func toJSON() -> [String: Any] {
        [
            "correlationKey": "_id",
            "correlationValue": distinctId,
            "source": "mobile",
            "event": event,
            "payload": properties,
            "timestamp": toISO8601String(timestamp),
            "fcmToken": fcmToken,
            "uuid": uuid.uuidString,
        ]
    }
}
