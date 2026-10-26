// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pianola",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Pianola", targets: ["Pianola"]),
        .executable(name: "pianola-cli", targets: ["PianolaCLI"]),
    ],
    targets: [
        // The engine: key layout, sheet parser, timing plan and real-time player.
        // Pure Foundation, so it can be tested without the app.
        .target(name: "PianolaCore"),
        .executableTarget(name: "Pianola", dependencies: ["PianolaCore"]),
        // Small command-line tool that prints what the engine makes of a sheet.
        .executableTarget(name: "PianolaCLI", dependencies: ["PianolaCore"]),
        .testTarget(name: "PianolaCoreTests", dependencies: ["PianolaCore"]),
    ]
)
