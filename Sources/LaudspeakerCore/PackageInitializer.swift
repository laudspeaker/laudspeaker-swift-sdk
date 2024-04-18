//
//  PackageInitializer.swift
//
//
//  Created by Abheek Basu on 3/21/24.
//

import Foundation

import Sentry

public class PackageInitializer {
    static let shared = PackageInitializer()
    
    private init(dsn: String? = nil) {
        SentrySDK.start { options in
            options.dsn = dsn ?? "https://15c7f142467b67973258e7cfaf814500@o4506038702964736.ingest.sentry.io/4506040630640640"
            options.debug = true // Consider turning off in production
            // Any additional Sentry configuration
            // Automatically record crashes and other issues
            options.enableAutoSessionTracking = true // Tracks app sessions
            options.sessionTrackingIntervalMillis = 30000 // Adjust session tracking interval (default is 30 seconds)
            
            // Attach stack trace for messages, not just for exceptions
            options.attachStacktrace = true
            
            // Set the environment to distinguish between staging, production, etc.
            options.environment = "production" // Or use "staging", "development", depending on your setup
            
            // More configurations can be set as needed
        }
    }
    
    public static func setup(withDSN dsn: String? = nil) {
            _ = PackageInitializer(dsn: dsn)
        }
}
