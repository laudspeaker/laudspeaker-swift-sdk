//
//  LaudspeakerQueue.swift
//
//

import Foundation

class LaudspeakerQueue {
    let retryDelay = 5.0
    let maxRetryDelay = 30.0
    // 30 minutes in seconds
    private let sessionChangeThreshold: TimeInterval = 60 * 30
    private let config: LaudspeakerConfig
    private let storage: LaudspeakerNewStorage
    private let api: LaudspeakerApi
    private var paused: Bool = false
    private var pausedLock = NSLock()
    private var pausedUntil: Date?
    private var retryCount: TimeInterval = 0
    #if !os(watchOS)
        private let reachability: Reachability?
    #endif

    private var isFlushing = false
    private let isFlushingLock = NSLock()
    private var timer: Timer?
    private let timerLock = NSLock()

    private let dispatchQueue = DispatchQueue(label: "com.laudspeaker.Queue", target: .global(qos: .utility))

    var depth: Int {
        fileQueue.depth
    }

    private let fileQueue: LaudspeakerFileBackedQueue

    #if !os(watchOS)
        init(_ config: LaudspeakerConfig, _ storage: LaudspeakerNewStorage, _ api: LaudspeakerApi, _ reachability: Reachability?) {
            self.config = config
            self.storage = storage
            self.api = api
            self.reachability = reachability
            fileQueue = LaudspeakerFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
        }
    #else
        init(_ config: LaudspeakerConfig, _ storage: LaudspeakerNewStorage, _ api: LaudspeakerApi) {
            self.config = config
            self.storage = storage
            self.api = api
            fileQueue = LaudspeakerFileBackedQueue(queue: storage.url(forKey: .queue), oldQueue: storage.url(forKey: .oldQeueue))
        }
    #endif

    private func eventHandler(_ payload: LaudspeakerConsumerPayload) {
        print("Sending batch of \(payload.events.count) events to Laudspeaker")

        api.batch(events: payload.events) { result in
            // -1 means its not anything related to the API but rather network or something else, so we try again
            let statusCode = result.statusCode ?? -1

            var shouldRetry = false
            if 300 ... 399 ~= statusCode || statusCode == -1 {
                shouldRetry = true
            }

            if shouldRetry {
                self.retryCount += 1
                let delay = min(self.retryCount * self.retryDelay, self.maxRetryDelay)
                self.pauseFor(seconds: delay)
                print("Pausing queue consumption for \(delay) seconds due to \(self.retryCount) API failure(s).")
            } else {
                self.retryCount = 0
            }

            payload.completion(!shouldRetry)
        }
        
        
        api.emitOne(event: payload.events){ result in
            // -1 means its not anything related to the API but rather network or something else, so we try again
            let statusCode = result.statusCode ?? -1

            var shouldRetry = false
            if 300 ... 399 ~= statusCode || statusCode == -1 {
                shouldRetry = true
            }

            if shouldRetry {
                self.retryCount += 1
                let delay = min(self.retryCount * self.retryDelay, self.maxRetryDelay)
                self.pauseFor(seconds: delay)
                print("Pausing queue consumption for \(delay) seconds due to \(self.retryCount) API failure(s).")
            } else {
                self.retryCount = 0
            }

            payload.completion(!shouldRetry)
        }
    }

    func start(disableReachabilityForTesting: Bool,
               disableQueueTimerForTesting: Bool)
    {
        if !disableReachabilityForTesting {
            // Setup the monitoring of network status for the queue
            #if !os(watchOS)
                reachability?.whenReachable = { reachability in
                    self.pausedLock.withLock {
                        if self.config.dataMode == .wifi, reachability.connection != .wifi {
                            print("Queue is paused because its not in WiFi mode")
                            self.paused = true
                        } else {
                            self.paused = false
                        }
                    }

                    // Always trigger a flush when we are on wifi
                    if reachability.connection == .wifi {
                        if !self.isFlushing {
                            self.flush()
                        }
                    }
                }

                reachability?.whenUnreachable = { _ in
                    self.pausedLock.withLock {
                        print("Queue is paused because network is unreachable")
                        self.paused = true
                    }
                }

                do {
                    try reachability?.startNotifier()
                } catch {
                    print("Error: Unable to monitor network reachability: \(error)")
                }
            #endif
        }

        if !disableQueueTimerForTesting {
            timerLock.withLock {
                timer = Timer.scheduledTimer(withTimeInterval: config.flushIntervalSeconds, repeats: true, block: { _ in
                    if !self.isFlushing {
                        self.flush()
                    }
                })
            }
        }
    }

    func clear() {
        fileQueue.clear()
    }

    func stop() {
        timerLock.withLock {
            timer?.invalidate()
            timer = nil
        }
    }

    func flush() {
        if !canFlush() {
            print("Already flushing")
            return
        }

        take(config.maxBatchSize) { payload in
            if !payload.events.isEmpty {
                self.eventHandler(payload)
            } else {
                // there's nothing to be sent
                payload.completion(true)
            }
        }
    }

    private func flushIfOverThreshold() {
        if fileQueue.depth >= config.flushAt {
            flush()
        }
    }

    func add(_ event: LaudspeakerEvent) {
        var data: Data?
        do {
            data = try JSONSerialization.data(withJSONObject: event.toJSON())
        } catch {
            print("Tried to queue unserialisable LaudspeakerEvent \(error)")
            return
        }

        fileQueue.add(data!)
        print("Queued event '\(event.event)'. Depth: \(fileQueue.depth)")
        flushIfOverThreshold()
    }

    private func take(_ count: Int, completion: @escaping (LaudspeakerConsumerPayload) -> Void) {
        dispatchQueue.async {
            self.isFlushingLock.withLock {
                if self.isFlushing {
                    return
                }
                self.isFlushing = true
            }

            let items = self.fileQueue.peek(count)

            var processing = [LaudspeakerEvent]()

            for item in items {
                // each element is a LaudspeakerEvent if fromJSON succeeds
                guard let event = LaudspeakerEvent.fromJSON(item) else {
                    continue
                }
                processing.append(event)
            }

            completion(LaudspeakerConsumerPayload(events: processing) { success in
                if success, items.count > 0 {
                    self.fileQueue.pop(items.count)
                    print("Completed!")
                }

                self.isFlushingLock.withLock {
                    self.isFlushing = false
                }
            })
        }
    }

    private func pauseFor(seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
    }

    private func canFlush() -> Bool {
        if isFlushing {
            return false
        }

        if paused {
            // We don't flush data if the queue is paused
            return false
        }

        if pausedUntil != nil, pausedUntil! > Date() {
            // We don't flush data if the queue is temporarily paused
            return false
        }

        return true
    }
}

