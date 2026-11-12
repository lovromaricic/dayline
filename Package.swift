// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dayline",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dayline", targets: ["Dayline"]),
        .executable(name: "dayline-report", targets: ["dayline-report"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Pure models and segment logic. No AppKit, no I/O.
        .target(name: "Domain"),
        // macOS signals: frontmost app, AX titles, Chrome URL, idle, sleep/lock, calls.
        .target(name: "Capture", dependencies: ["Domain"]),
        // Category resolution (spec section 4).
        .target(name: "Categorize", dependencies: ["Domain"]),
        // SQLite via GRDB.
        .target(name: "Store", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),
        // SwiftUI views and the menu bar icon. Value types in, no capture or storage.
        .target(name: "UI", dependencies: ["Domain"]),
        // The menu bar app: wires capture, store, categorizer and UI together.
        .executableTarget(name: "Dayline", dependencies: ["Domain", "Capture", "Categorize", "Store", "UI"]),
        // Renders the popover in every state to PNG, for design review.
        .executableTarget(name: "ui-snapshots", dependencies: ["Domain", "UI", "Store", "Categorize"]),
        // Prints a day's segments from the database.
        .executableTarget(name: "dayline-report", dependencies: ["Domain", "Store"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "StoreTests", dependencies: ["Store", "Domain"]),
        .testTarget(name: "CategorizeTests", dependencies: ["Categorize", "Domain"]),
        .testTarget(name: "DaylineTests", dependencies: ["Dayline", "Categorize", "Domain", "UI"]),
    ],
    swiftLanguageModes: [.v5]
)
