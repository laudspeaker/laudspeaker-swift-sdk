//
//  LaudspeakerConfig.swift
//  Laudspeaker
//
//
import Foundation

@objc(LaudspeakerConfig) public class LaudspeakerConfig: NSObject {
    @objc(LaudspeakerDataMode) public enum LaudspeakerDataMode: Int {
        case wifi
        case cellular
        case any
    }
    
    let retryDelay = 5.0
    let maxRetryDelay = 30.0
    // 30 minutes in seconds
    private let sessionChangeThreshold: TimeInterval = 60 * 30

    @objc public var host: URL
    @objc public var apiKey: String
    @objc public var flushAt: Int = 1
    //@objc public var flushAt: Int = 1
    @objc public var maxQueueSize: Int = 1000
    @objc public var maxBatchSize: Int = 50
    @objc public var flushIntervalSeconds: TimeInterval = 30
    @objc public var dataMode: LaudspeakerDataMode = .any
    @objc public var sendFeatureFlagEvent: Bool = true
    @objc public var preloadFeatureFlags: Bool = true
    @objc public var captureApplicationLifecycleEvents: Bool = true
    @objc public var captureScreenViews: Bool = true
    @objc public var debug: Bool = false
    @objc public var optOut: Bool = false
    public static let defaultHost: String = "https://app.laudspeaker.com"

    // only internal
    var disableReachabilityForTesting: Bool = false
    var disableQueueTimerForTesting: Bool = false

    @objc(apiKey:)
    public init(
        apiKey: String
    ) {
        self.apiKey = apiKey
        host = URL(string: LaudspeakerConfig.defaultHost)!
    }

    @objc(apiKey:host:)
    public init(
        apiKey: String,
        host: String = defaultHost
    ) {
        self.apiKey = apiKey
        self.host = URL(string: host) ?? URL(string: LaudspeakerConfig.defaultHost)!
    }
}
