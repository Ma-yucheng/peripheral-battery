import Foundation
import Combine

/// 汇总四路数据源，按设备名称合并成统一的设备列表。
final class BatteryStore: ObservableObject {

    @Published private(set) var devices: [PeripheralDevice] = []
    @Published private(set) var lastRefresh: Date = Date()
    @Published private(set) var bleStatus = BLEBatteryProvider.Status()
    @Published private(set) var sourceSummary: String = ""

    private let ble = BLEBatteryProvider()
    private let hid = HIDBatteryProvider()
    private let profiler = BluetoothProfilerProvider()
    private let gamepad = GamepadProvider()
    private let demo = DemoProvider()

    private var rawBLE: [PeripheralDevice] = []
    private var rawHID: [PeripheralDevice] = []
    private var rawProfiler: [PeripheralDevice] = []
    private var rawGamepad: [PeripheralDevice] = []
    private var rawDemo: [PeripheralDevice] = []

    /// 每个设备的最近电量序列，用于卡片模式的走势线
    private var history: [String: [Int]] = [:]

    private var started = false

    func start() {
        guard !started else { return }
        started = true

        ble.onUpdate = { [weak self] list in
            self?.rawBLE = list
            self?.rebuild()
        }
        ble.onStatus = { [weak self] status in
            self?.bleStatus = status
        }
        hid.onUpdate = { [weak self] list in
            self?.rawHID = list
            self?.rebuild()
        }
        profiler.onUpdate = { [weak self] list in
            self?.rawProfiler = list
            self?.rebuild()
        }
        gamepad.onUpdate = { [weak self] list in
            self?.rawGamepad = list
            self?.rebuild()
        }
        demo.onUpdate = { [weak self] list in
            guard let self else { return }
            self.rawDemo = list
            if AppSettings.shared.demoMode { self.rebuild() }
        }

        ble.start()
        hid.start()
        profiler.start()
        gamepad.start()
        demo.start()
    }

    func stop() {
        ble.stop()
        hid.stop()
        profiler.stop()
        gamepad.stop()
        demo.stop()
        started = false
    }

    /// 手动重新扫描
    func rescan() {
        ble.pollNow()
        hid.pollNow()
        profiler.pollNow()
        gamepad.pollNow()
    }

    func discoverGamepads() {
        gamepad.startDiscovery()
    }

    func history(for deviceID: String) -> [Int] {
        history[deviceID] ?? []
    }

    // MARK: - 合并

    private struct Merged {
        var device: PeripheralDevice
        var sources: Set<BatterySource>
    }

    private func rebuild() {
        let useDemo = AppSettings.shared.demoMode

        var map: [String: Merged] = [:]

        let streams: [(source: BatterySource, list: [PeripheralDevice])] = useDemo
            ? [(.demo, rawDemo)]
            : [(.ble, rawBLE), (.hid, rawHID), (.gamepad, rawGamepad), (.bluetooth, rawProfiler)]

        for (_, list) in streams {
            for device in list {
                let key = DeviceNameKey.normalize(device.name)
                guard !key.isEmpty else { continue }

                if var existing = map[key] {
                    existing.sources.insert(device.source)

                    if shouldTakeLevel(device, over: existing.device) {
                        existing.device.level = device.level
                        existing.device.state = device.state
                        existing.device.source = device.source
                        existing.device.lastUpdate = device.lastUpdate
                    }

                    if existing.device.kind == .other && device.kind != .other {
                        existing.device.kind = device.kind
                    }
                    if !device.components.isEmpty && existing.device.components.isEmpty {
                        existing.device.components = device.components
                    }
                    if device.name.count > existing.device.name.count {
                        existing.device.name = device.name
                    }
                    if existing.device.address == nil { existing.device.address = device.address }
                    if existing.device.rssi == nil { existing.device.rssi = device.rssi }
                    existing.device.isConnected = existing.device.isConnected || device.isConnected
                    map[key] = existing
                } else {
                    var copy = device
                    copy.id = "dev:\(key)"
                    map[key] = Merged(device: copy, sources: [device.source])
                }
            }
        }

        var result: [PeripheralDevice] = []
        for (key, merged) in map {
            var device = merged.device
            device.id = "dev:\(key)"
            result.append(device)
        }

        // 只展示当前在线的设备：断开 / 休眠的直接移出列表
        result = result.filter { $0.isConnected }

        // 排序：有电量在前，其次按类型、名称
        result.sort { lhs, rhs in
            if (lhs.level != nil) != (rhs.level != nil) { return lhs.level != nil }
            if lhs.kind.sortIndex != rhs.kind.sortIndex { return lhs.kind.sortIndex < rhs.kind.sortIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        updateHistory(with: result)
        devices = result
        lastRefresh = Date()
        sourceSummary = summary(for: result)

        if ProcessInfo.processInfo.environment["PB_LOG"] != nil {
            let desc = result
                .map { "\($0.name)=\($0.levelText)[\($0.source.shortLabel)]" }
                .joined(separator: ", ")
            print("[PB] \(result.count) 台: \(desc)")
        }
    }

    private func shouldTakeLevel(_ candidate: PeripheralDevice, over current: PeripheralDevice) -> Bool {
        guard candidate.level != nil else { return false }
        if current.level == nil { return true }
        if candidate.source.priority != current.source.priority {
            return candidate.source.priority < current.source.priority
        }
        return candidate.lastUpdate > current.lastUpdate
    }

    private func updateHistory(with devices: [PeripheralDevice]) {
        for device in devices {
            guard let level = device.level else { continue }
            var samples = history[device.id] ?? []
            if samples.last != level {
                samples.append(level)
            } else {
                samples.append(level)
            }
            if samples.count > 48 {
                samples.removeFirst(samples.count - 48)
            }
            history[device.id] = samples
        }
        // 清理已消失设备的历史
        let ids = Set(devices.map(\.id))
        for key in history.keys where !ids.contains(key) {
            history.removeValue(forKey: key)
        }
    }

    private func summary(for devices: [PeripheralDevice]) -> String {
        let readable = devices.filter { $0.level != nil }
        if readable.isEmpty {
            return devices.isEmpty ? "未发现外设" : "已发现 \(devices.count) 台设备，未提供电量"
        }
        return "\(readable.count) 台设备在线"
    }
}
