import AppKit
import Foundation

/// 让 App 在系统层面「常驻后台」：
/// - 运行时禁止自动终止 / 突然终止 / App Nap（由 AppDelegate 调用 beginActivity）
/// - 登录项：写一个 LaunchAgent，登录时自动回到菜单栏
final class BackgroundKeeper {

    static let shared = BackgroundKeeper()

    private let label = "com.local.peripheralbattery"
    private let fm = FileManager.default

    private var plistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 只有装到 /Applications 里才注册登录项，避免开发目录的临时路径写进系统
    var canRegisterLoginItem: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    var isLoginItemRegistered: Bool {
        guard let uid = currentUID else { return false }
        let result = run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"])
        return result.status == 0
    }

    // MARK: - 运行时保活

    /// 返回的 token 需要一直持有，释放后保活就失效
    func beginBackgroundActivity() -> NSObjectProtocol? {
        ProcessInfo.processInfo.disableAutomaticTermination("实时监控外设电量")
        ProcessInfo.processInfo.disableSuddenTermination()
        return ProcessInfo.processInfo.beginActivity(
            options: [.background, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "实时读取外设电量"
        )
    }

    // MARK: - 登录项

    @discardableResult
    func applyLoginItem(enabled: Bool) -> Bool {
        enabled ? installLoginItem() : removeLoginItem()
    }

    @discardableResult
    func installLoginItem() -> Bool {
        guard canRegisterLoginItem else { return false }
        guard let uid = currentUID else { return false }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua"
        ]

        do {
            try fm.createDirectory(at: plistURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return false
        }

        // 先卸载旧的定义，再重新加载
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        let result = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
        return result.status == 0
    }

    @discardableResult
    func removeLoginItem() -> Bool {
        guard let uid = currentUID else { return false }
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
        try? fm.removeItem(at: plistURL)
        return true
    }

    // MARK: - 工具

    private var currentUID: uid_t? {
        let uid = getuid()
        return uid == 0 ? nil : uid
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
