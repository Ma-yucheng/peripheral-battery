import Foundation
import IOKit
import IOKit.hid

/// Apple 原厂外设（Magic Mouse / Magic Keyboard / Magic Trackpad）的电量。
/// 这类设备不会对外暴露 BLE 电池服务，但会在 IORegistry 的
/// AppleDeviceManagementHIDEventService 节点上带 BatteryPercent 属性。
final class HIDBatteryProvider {

    var onUpdate: (([PeripheralDevice]) -> Void)?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "peripheral-battery.hid", qos: .utility)
    private var hidManager: IOHIDManager?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.setupHIDManager()
            self.poll()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        }
    }

    func pollNow() {
        queue.async { [weak self] in self?.poll() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            if let manager = self?.hidManager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
    }

    private func setupHIDManager() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        // 打开失败（缺少输入监控权限）也不影响读取设备属性
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager
    }

    private func poll() {
        var devices: [PeripheralDevice] = []
        var seenNames = Set<String>()

        for device in appleEventServices() {
            let key = DeviceNameKey.normalize(device.name)
            if seenNames.contains(key) { continue }
            seenNames.insert(key)
            devices.append(device)
        }

        for device in hidDevices() {
            let key = DeviceNameKey.normalize(device.name)
            if seenNames.contains(key) { continue }
            seenNames.insert(key)
            devices.append(device)
        }

        devices.sort { lhs, rhs in
            if lhs.kind.sortIndex != rhs.kind.sortIndex { return lhs.kind.sortIndex < rhs.kind.sortIndex }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(devices)
        }
    }

    // MARK: - IORegistry: AppleDeviceManagementHIDEventService

    private func appleEventServices() -> [PeripheralDevice] {
        var result: [PeripheralDevice] = []
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else { return result }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return result }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let name = (IORegistryProperty(service, "Product") as? String)
                ?? (IOServiceName(service) ?? "Apple 外设")
            guard let percent = batteryPercent(from: IORegistryProperty(service, "BatteryPercent")) else { continue }
            let transport = IORegistryProperty(service, "Transport") as? String
            let serial = IORegistryProperty(service, "SerialNumber") as? String
            var state: ChargingState = .discharging
            if let status = IORegistryProperty(service, "BatteryStatus") as? String {
                if status.localizedCaseInsensitiveContains("charging") || status == "Charging" {
                    state = .charging
                }
            }
            if percent >= 100 { state = .full }

            let kind: DeviceKind
            if let page = IORegistryProperty(service, "PrimaryUsagePage") as? Int,
               let usage = IORegistryProperty(service, "PrimaryUsage") as? Int {
                kind = Self.kind(usagePage: page, usage: usage, fallbackName: name)
            } else {
                kind = DeviceKindInference.infer(name)
            }

            result.append(PeripheralDevice(
                id: DeviceNameKey.id(for: .hid, address: serial ?? (transport ?? "") + name, name: name),
                name: name,
                kind: kind,
                level: percent,
                state: state,
                source: .hid,
                address: serial,
                rssi: nil,
                components: [],
                lastUpdate: Date(),
                isConnected: true
            ))
        }
        return result
    }

    // MARK: - IOHIDManager: 任意 HID 设备暴露的 BatteryPercent

    private func hidDevices() -> [PeripheralDevice] {
        guard let manager = hidManager else { return [] }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var result: [PeripheralDevice] = []

        for device in deviceSet {
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? ""
            guard !name.isEmpty else { continue }
            // 忽略内置键盘 / 触控板（由电池厂提供，没有独立电量意义）
            let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? ""
            if name.localizedCaseInsensitiveContains("Internal") { continue }
            if transport.uppercased() == "SPI" && vendorID == 1452 { continue }

            var percent: Int?
            for key in ["BatteryPercent", "BatteryLevel", "BatteryPercentage"] {
                if let value = IOHIDDeviceGetProperty(device, key as CFString) {
                    if let p = self.batteryPercent(from: value) {
                        percent = p
                        break
                    }
                }
            }
            guard let level = percent else { continue }

            let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
            let kind = Self.kind(usagePage: page, usage: usage, fallbackName: name)

            result.append(PeripheralDevice(
                id: DeviceNameKey.id(for: .hid, address: serial ?? name, name: name),
                name: name,
                kind: kind,
                level: level,
                state: level >= 100 ? .full : .discharging,
                source: .hid,
                address: serial,
                rssi: nil,
                components: [],
                lastUpdate: Date(),
                isConnected: true
            ))
        }
        return result
    }

    // MARK: - 工具

    private func batteryPercent(from value: Any?) -> Int? {
        if let number = value as? Int, number >= 0, number <= 100 { return number }
        if let number = value as? NSNumber {
            let intValue = number.intValue
            return (intValue >= 0 && intValue <= 100) ? intValue : nil
        }
        if let text = value as? String {
            let digits = text.prefix { $0.isNumber }
            if let p = Int(digits), p >= 0, p <= 100 { return p }
        }
        return nil
    }

    static func kind(usagePage: Int, usage: Int, fallbackName: String) -> DeviceKind {
        if usagePage == kHIDPage_GenericDesktop {
            switch usage {
            case kHIDUsage_GD_Mouse: return .mouse
            case kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad: return .keyboard
            case kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController: return .gamepad
            default: break
            }
        }
        if usagePage == 0x0C {
            return .headset
        }
        return DeviceKindInference.infer(fallbackName)
    }
}

// MARK: - IORegistry 辅助

private func IORegistryProperty(_ entry: io_object_t, _ key: String) -> Any? {
    guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
    return value.takeRetainedValue()
}

private func IOServiceName(_ entry: io_object_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 256)
    if IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS {
        return String(cString: buffer)
    }
    return nil
}
