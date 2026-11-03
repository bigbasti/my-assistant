import ServiceManagement

public protocol LoginItem {
    var isEnabled: Bool { get }
    func set(_ on: Bool) throws
}

public enum LaunchAtLogin {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

public struct SystemLoginItem: LoginItem {
    public init() {}
    public var isEnabled: Bool { LaunchAtLogin.isEnabled }
    public func set(_ on: Bool) throws { try LaunchAtLogin.set(on) }
}
