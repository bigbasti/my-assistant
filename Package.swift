// swift-tools-version:6.2
import Foundation
import PackageDescription

// The test runner is an executable target, so SwiftPM doesn't add Testing.framework's search
// paths for it. Find them in the Command Line Tools (local) or in Xcode (e.g. GitHub runners).
func testingPaths() -> (frameworks: String, lib: String) {
    let fm = FileManager.default
    // Order matters: the explicitly selected toolchain first (CI sets DEVELOPER_DIR), then the
    // Command Line Tools, then any Xcode. Mixing toolchains breaks the Testing macros.
    var bases: [String] = []
    if let dir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
        bases += ["\(dir)/Platforms/MacOSX.platform/Developer", "\(dir)/Library/Developer"]
    }
    bases.append("/Library/Developer/CommandLineTools/Library/Developer")
    let xcodes = ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? [])
        .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }.sorted().reversed()
    bases += xcodes.map { "/Applications/\($0)/Contents/Developer/Platforms/MacOSX.platform/Developer" }
    for base in bases {
        // CLT keeps it in <base>/Frameworks, Xcode in <base>/Library/Frameworks.
        for frameworks in ["\(base)/Frameworks", "\(base)/Library/Frameworks"]
        where fm.fileExists(atPath: "\(frameworks)/Testing.framework") {
            return (frameworks, "\(base)/usr/lib")
        }
    }
    return ("/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
            "/Library/Developer/CommandLineTools/Library/Developer/usr/lib")
}
let testing = testingPaths()
let cltFrameworks = testing.frameworks
let cltLib = testing.lib

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
