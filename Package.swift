// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "itunes-reclaim",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ReclaimCore"),
        .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
        .executableTarget(
            name: "reclaim-probe",
            dependencies: ["ReclaimCore"],
            exclude: ["Info.plist"],
            linkerSettings: [.linkedFramework("iTunesLibrary")]
        ),
    ]
)
