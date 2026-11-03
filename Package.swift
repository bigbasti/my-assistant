// swift-tools-version:6.2
import PackageDescription

// Command Line Tools ship Testing.framework outside the default search path.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLib = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "MyAssistant",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MyAssistantCore"),
        .executableTarget(name: "MyAssistant", dependencies: ["MyAssistantCore"]),
        .executableTarget(
            name: "MyAssistantTests",
            dependencies: ["MyAssistantCore"],
            path: "Tests/MyAssistantTests",
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltLib])]
        ),
    ]
)
