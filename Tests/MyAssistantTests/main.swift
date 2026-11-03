// Command Line Tools cannot run `swift test` for Swift Testing; run `swift run MyAssistantTests [--filter X]`.
import Foundation
import Testing

exit(await Testing.__swiftPMEntryPoint() as CInt)
