// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pianola",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Pianola", targets: ["Pianola"]),
        .executable(name: "pianola-cli", targets: ["PianolaCLI"]),
    ],
    dependencies: [
        // Automatic updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // The engine: key layout, sheet parser, timing plan and real-time player.
        // Pure Foundation, so it can be tested without the app.
        .target(name: "PianolaCore"),
        .executableTarget(
            name: "Pianola",
            dependencies: ["PianolaCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is copied into Pianola.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        // Small command-line tool that prints what the engine makes of a sheet.
        .executableTarget(name: "PianolaCLI", dependencies: ["PianolaCore"]),
        .testTarget(name: "PianolaCoreTests", dependencies: ["PianolaCore"]),
    ]
)
