//
//  LaudspeakerConsumerPayload.swift
//  Laudspeaker
//
//

import Foundation

struct LaudspeakerConsumerPayload {
    let events: [LaudspeakerEvent]
    let completion: (Bool) -> Void
}
