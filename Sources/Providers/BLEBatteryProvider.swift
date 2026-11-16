import Foundation
import CoreBluetooth

/// 蓝牙标准电池服务（0x180F / 0x2A19）读取。
/// 这是本机唯一能拿到第三方蓝牙外设"真实实时电量"的公开通道：
/// 通过 retrieveConnectedPeripherals 拿到系统已连接的外设（鼠标 / 键盘 / 手柄），
/// 再读取电池特征值，并订阅通知以获得实时变化。
final class BLEBatteryProvider: NSObject {

    struct Status {
        var poweredOn: Bool = false
        var authorized: Bool = true
        var detail: String = "初始化中"
    }

    var onUpdate: (([PeripheralDevice]) -> Void)?
    var onStatus: ((Status) -> Void)?

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelChar = CBUUID(string: "2A19")
    private static let batteryStatusChar = CBUUID(string: "2A1B")
    private static let hidService = CBUUID(string: "1812")

    private struct Entry {
        var name: String
        var level: Int?
        var state: ChargingState = .unknown
        var connected: Bool = false
        var systemConnected: Bool = true
        var hasBatteryService: Bool = false
        var lastUpdate: Date = .distantPast
        var lastConnectAttempt: Date = .distantPast
    }

    private let queue = DispatchQueue(label: "peripheral-battery.ble", qos: .utility)
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var batteryChars: [UUID: CBCharacteristic] = [:]
    private var entries: [UUID: Entry] = [:]
    private var pendingConnect: Set<UUID> = []
    private var timer: DispatchSourceTimer?
    private var scanTimer: DispatchSourceTimer?
    private var tick: Int = 0
    private var started = false
    private var status = Status()

    func start() {
        queue.async { [weak self] in
            guard let self, !self.started else { return }
            self.started = true
            self.central = CBCentralManager(delegate: self, queue: self.queue, options: nil)
        }
    }

    /// 立刻重新拉取一遍（用于面板里的"重新扫描"）
    func pollNow() {
        queue.async { [weak self] in
            guard let self else { return }
            self.refreshConnectedPeripherals()
            for (id, peripheral) in self.peripherals {
                guard let entry = self.entries[id], entry.connected else { continue }
                if let characteristic = self.batteryChars[id] {
                    self.readValue(for: peripheral, characteristic: characteristic)
                }
            }
            self.emit()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.scanTimer?.cancel()
            self.scanTimer = nil
            if let central = self.central, central.state == .poweredOn {
                central.stopScan()
            }
        }
    }

    // MARK: - 发现

    private func refreshConnectedPeripherals() {
        guard let central = central, central.state == .poweredOn else { return }

        var found: [CBPeripheral] = []
        let battery = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        found.append(contentsOf: battery)
        let hid = central.retrieveConnectedPeripherals(withServices: [Self.hidService])
        for peripheral in hid where !found.contains(where: { $0.identifier == peripheral.identifier }) {
            found.append(peripheral)
        }

        let knownIDs = Set(found.map(\.identifier))
        for (id, _) in entries where !knownIDs.contains(id) {
            // 设备已不在系统列表中，标记为断开（保留一小段时间用于展示）
            entries[id]?.systemConnected = false
            entries[id]?.connected = false
        }

        for peripheral in found {
            let id = peripheral.identifier
            var entry = entries[id] ?? Entry(name: peripheral.name ?? "未命名蓝牙设备")
            entry.name = peripheral.name ?? entry.name
            entry.systemConnected = true
            entries[id] = entry
            peripherals[id] = peripheral
            peripheral.delegate = self

            if peripheral.state == .connected {
                discoverBattery(on: peripheral)
            } else {
                connect(peripheral)
            }
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard !pendingConnect.contains(id) else { return }
        // 3 秒内不重复尝试，避免刷爆蓝牙栈
        if let entry = entries[id], Date().timeIntervalSince(entry.lastConnectAttempt) < 3 { return }
        entries[id]?.lastConnectAttempt = Date()
        pendingConnect.insert(id)
        central.connect(peripheral, options: nil)
    }

    private func discoverBattery(on peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard peripheral.state == .connected else {
            connect(peripheral)
            return
        }
        if let existing = batteryChars[id], existing.service?.peripheral != nil {
            readValue(for: peripheral, characteristic: existing)
            return
        }
        if (peripheral.services?.isEmpty ?? true) {
            peripheral.discoverServices([Self.batteryService])
        } else {
            if let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) {
                peripheral.discoverCharacteristics([Self.batteryLevelChar, Self.batteryStatusChar], for: service)
            }
        }
    }

    private func readValue(for peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.read) else { return }
        peripheral.readValue(for: characteristic)
    }

    // MARK: - 输出

    private func emit() {
        var devices: [PeripheralDevice] = []
        for (id, entry) in entries {
            // 只展示有电池服务或曾拿到电量的外设
            guard entry.hasBatteryService || entry.level != nil else { continue }
            var device = PeripheralDevice(
                id: "ble:\(id.uuidString)",
                name: entry.name,
                kind: DeviceKindInference.infer(entry.name),
                level: entry.level,
                state: entry.state,
                source: .ble,
                address: id.uuidString,
                rssi: nil,
                components: [],
                lastUpdate: entry.lastUpdate,
                isConnected: entry.connected
            )
            device.isDemo = false
            devices.append(device)
        }
        devices.sort { lhs, rhs in
            if lhs.kind.sortIndex != rhs.kind.sortIndex { return lhs.kind.sortIndex < rhs.kind.sortIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        let snapshot = devices
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }

    private func pushStatus() {
        let current = status
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(current)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBatteryProvider: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status.authorized = CBManager.authorization != .denied
        switch central.state {
        case .poweredOn:
            status.poweredOn = true
            status.detail = "蓝牙已开启"
            pushStatus()
            refreshConnectedPeripherals()
            startTimers()
        case .poweredOff:
            status.poweredOn = false
            status.detail = "蓝牙已关闭"
            pushStatus()
        case .unauthorized:
            status.authorized = false
            status.poweredOn = false
            status.detail = "未获得蓝牙权限"
            pushStatus()
        case .unsupported:
            status.poweredOn = false
            status.detail = "此设备不支持蓝牙"
            pushStatus()
        default:
            status.detail = "蓝牙状态切换中"
            pushStatus()
        }
    }

    private func startTimers() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.tick += 1
            // 每 3 秒：读取已连接设备电量
            for (id, peripheral) in self.peripherals {
                guard let entry = self.entries[id], entry.connected else { continue }
                if let characteristic = self.batteryChars[id] {
                    self.readValue(for: peripheral, characteristic: characteristic)
                } else if let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) {
                    peripheral.discoverCharacteristics([Self.batteryLevelChar, Self.batteryStatusChar], for: service)
                }
            }
            // 每 9 秒：重新拉取系统已连接外设列表（新设备接入时自动出现）
            if self.tick % 3 == 0 {
                self.refreshConnectedPeripherals()
            }
            self.emit()
        }
        timer.resume()
        self.timer = timer

        // 每 60 秒做一次 6 秒的广播扫描，捕捉未接入系统但可读电量的外设
        let scanTimer = DispatchSource.makeTimerSource(queue: queue)
        scanTimer.schedule(deadline: .now() + 5, repeating: 60)
        scanTimer.setEventHandler { [weak self] in
            guard let self, let central = self.central, central.state == .poweredOn else { return }
            central.scanForPeripherals(
                withServices: [Self.batteryService],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            self.queue.asyncAfter(deadline: .now() + 6) {
                central.stopScan()
            }
        }
        scanTimer.resume()
        self.scanTimer = scanTimer
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // 只接受同时暴露 HID 服务的设备，避免把其他带电池服务的蓝牙设备混进来
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        guard services.contains(Self.hidService) else { return }

        let id = peripheral.identifier
        if entries[id] == nil {
            entries[id] = Entry(name: peripheral.name ?? "未命名蓝牙设备", systemConnected: false)
        }
        peripherals[id] = peripheral
        peripheral.delegate = self
        if peripheral.state != .connected {
            connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        pendingConnect.remove(id)
        entries[id]?.connected = true
        entries[id]?.lastUpdate = Date()
        peripheral.discoverServices([Self.batteryService])
        emit()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        pendingConnect.remove(id)
        entries[id]?.connected = false
        emit()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        pendingConnect.remove(id)
        entries[id]?.connected = false
        batteryChars[id] = nil
        emit()
        // 稍后重连，让电量持续可读
        queue.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.entries[id]?.systemConnected == true else { return }
            if peripheral.state != .connected { self.connect(peripheral) }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEBatteryProvider: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let id = peripheral.identifier
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            entries[id]?.hasBatteryService = false
            emit()
            return
        }
        entries[id]?.hasBatteryService = true
        peripheral.discoverCharacteristics([Self.batteryLevelChar, Self.batteryStatusChar], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.batteryLevelChar {
                batteryChars[id] = characteristic
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                readValue(for: peripheral, characteristic: characteristic)
            } else if characteristic.uuid == Self.batteryStatusChar {
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        entries[id]?.hasBatteryService = true
        emit()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = peripheral.identifier
        guard let data = characteristic.value, !data.isEmpty else { return }

        if characteristic.uuid == Self.batteryLevelChar {
            let raw = data[data.startIndex]
            // 0xFF 与 >100 视为"未知"
            if raw <= 100 {
                let level = Int(raw)
                entries[id]?.level = level
                entries[id]?.lastUpdate = Date()
                entries[id]?.connected = true
                if level >= 100 {
                    entries[id]?.state = .full
                }
            }
        } else if characteristic.uuid == Self.batteryStatusChar {
            let flags = UInt16(data[data.startIndex])
            if flags & 0b100 != 0 {
                entries[id]?.state = .charging
            } else if flags & 0b1000 != 0 {
                entries[id]?.state = .discharging
            }
        }
        emit()
    }
}
