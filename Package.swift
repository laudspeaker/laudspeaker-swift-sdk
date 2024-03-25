// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "laudspeaker-swift-sdk",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LaudspeakerCore",
            targets: ["LaudspeakerCore"]),
        .library(
            name: "LaudspeakerNotificationService",
            targets: ["LaudspeakerNotificationService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", .upToNextMajor(from: "8.22.2")),
        //.package(name: "SocketIO",url: "https://github.com/socketio/socket.io-client-swift", .upToNextMinor(from: "16.1.0")),
        .package(
            name: "Firebase",
          url: "https://github.com/firebase/firebase-ios-sdk.git",
          .upToNextMajor(from: "10.4.0")
            
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LaudspeakerCore",
            dependencies: [
                //.product(name: "SocketIO", package: "SocketIO" ),
                .product(name: "FirebaseMessaging", package: "Firebase" ),
                .product(name: "Sentry", package: "sentry-cocoa")]
        ),
        .target(
            name: "LaudspeakerNotificationService",
            dependencies: ["LaudspeakerCore"]
        ),
    ]
)
