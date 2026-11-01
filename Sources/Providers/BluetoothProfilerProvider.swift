import Foundation

/// 通过 system_profiler 读取蓝牙外设电量。
/// 覆盖 AirPods 这类会返回"左 / 右 / 充电盒"三路电量的设备，
/// 以及部分在 HID 层不暴露属性的蓝牙外设。
final class BluetoothProfilerProvider {

    var onUpdate: (([PeripheralDevice]) -> Void)?

    private let queue = DispatchQueue(label: "peripheral-battery.profiler", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var running = false

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.run()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 8, repeating: 8)
            timer.setEventHandler { [weak self] in self?.run() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    func pollNow() {
        queue.async { [weak self] in self?.run() }
    }

    private func run() {
        guard !running else { return }
        running = true
        defer { running = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let devices = Self.parse(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(devices)
        }
    }

    // MARK: - 解析

    static func parse(data: Data) -> [PeripheralDevice]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        var devices: [PeripheralDevice] = []
        for controller in controllers {
            let groups: [(String, Bool)] = [("device_connected", true), ("device_not_connected", false)]
            for (key, connected) in groups {
                guard let list = controller[key] as? [[String: Any]] else { continue }
                for entry in list {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        if let device = makeDevice(name: name, info: info, connected: connected) {
                            devices.append(device)
                        }
                    }
                }
            }
        }
        return devices
    }

    private static func makeDevice(name: String, info: [String: Any], connected: Bool) -> PeripheralDevice? {
        let minorType = (info["device_minorType"] as? String) ?? ""
        let kind = kind(from: minorType, name: name)

        var components: [BatteryComponent] = []
        if let left = percent(info["device_batteryLevelLeft"]) { components.append(BatteryComponent(label: "左耳", level: left)) }
        if let right = percent(info["device_batteryLevelRight"]) { components.append(BatteryComponent(label: "右耳", level: right)) }
        if let caseLevel = percent(info["device_batteryLevelCase"]) { components.append(BatteryComponent(label: "充电盒", level: caseLevel)) }

        var main = percent(info["device_batteryLevel"])
            ?? percent(info["device_batteryLevelMain"])
            ?? percent(info["device_batteryLevelCombined"])
            ?? percent(info["device_batteryPercent"])
        if main == nil, !components.isEmpty {
            main = components.map(\.level).min()
        }

        // 过滤掉手机 / 平板等非外设
        if minorType.isEmpty && components.isEmpty && main == nil { return nil }
        if kind == .other && minorType.isEmpty && main == nil && components.isEmpty { return nil }
        if isPhoneLike(minorType: minorType, name: name) { return nil }
        // 已经离线且没有电量数据的设备不进入列表，避免满屏 "--"
        if !connected && main == nil && components.isEmpty { return nil }

        var state: ChargingState = .unknown
        if let rawText = info["device_batteryLevel"] as? String {
            let text = rawText.lowercased()
            if text.contains("charging") { state = .charging }
            else if text.contains("discharging") { state = .discharging }
            else if text.contains("charged") { state = .full }
        }
        if let level = main, level >= 100 { state = .full }

        let address = info["device_address"] as? String
        return PeripheralDevice(
            id: DeviceNameKey.id(for: .bluetooth, address: address, name: name),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            level: main,
            state: state,
            source: .bluetooth,
            address: address,
            rssi: nil,
            components: components,
            lastUpdate: Date(),
            isConnected: connected
        )
    }

    private static func isPhoneLike(minorType: String, name: String) -> Bool {
        let t = minorType.lowercased()
        if t.contains("phone") || t.contains("pad") || t.contains("computer") || t.contains("watch") { return true }
        let n = name.lowercased()
        if n.contains("iphone") || n.contains("ipad") || n.contains("macbook") || n.contains("watch") { return true }
        return false
    }

    private static func kind(from minorType: String, name: String) -> DeviceKind {
        switch minorType.lowercased() {
        case "mouse": return .mouse
        case "keyboard", "keypad": return .keyboard
        case "trackpad": return .trackpad
        case "gamepad", "joystick": return .gamepad
        case "headset", "headphones", "speaker": return .headset
        default: return DeviceKindInference.infer(name)
        }
    }

    private static func percent(_ value: Any?) -> Int? {
        if let number = value as? Int { return (0...100).contains(number) ? number : nil }
        if let number = value as? NSNumber { return (0...100).contains(number.intValue) ? number.intValue : nil }
        if let text = value as? String {
            let digits = text.prefix { $0.isNumber }
            if let number = Int(digits), (0...100).contains(number) { return number }
        }
        return nil
    }
}
