// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DaylineSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DaylineSpike", path: "Sources/DaylineSpike")
    ]
)
