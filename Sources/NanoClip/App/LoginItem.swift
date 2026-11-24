import Foundation
import ServiceManagement
import NanoClipCore

/// Login-item control through `SMAppService.mainApp` (macOS 13+): no helper bundle, no
/// LaunchAgents plist, and the preference is mirrored by the system.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var statusDescription: String {
        switch status {
        case .enabled: return "已启用"
        case .notRegistered: return "未注册"
        case .notFound: return "无法定位应用（请把 NanoClip 放到 /Applications）"
        case .requiresApproval: return "需要在系统设置中允许"
        @unknown default: return "未知状态"
        }
    }

    @discardableResult
    static func register() -> Bool {
        do {
            try SMAppService.mainApp.register()
            Log.info("login item registered")
            return true
        } catch {
            Log.error("login item register failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func unregister() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            Log.info("login item unregistered")
            return true
        } catch {
            Log.error("login item unregister failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Makes the system state match the user's intent. Returns the achieved state.
    @discardableResult
    static func apply(enabled: Bool) -> Bool {
        if enabled {
            if status != .enabled { return register() }
            return true
        } else {
            if status == .enabled { return unregister() }
            return true
        }
    }
}