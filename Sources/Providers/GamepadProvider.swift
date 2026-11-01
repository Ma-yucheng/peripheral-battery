import Foundation
import GameController

/// 手柄电量：Xbox / DualSense / DualShock / Switch Pro 等。
/// GameController 框架会把 batteryLevel 归一化到 0...1。
final class GamepadProvider {

    var onUpdate: (([PeripheralDevice]) -> Void)?

    private let queue = DispatchQueue(label: "peripheral-battery.gamepad", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var discoveryStopWorkItem: DispatchWorkItem?

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.pollNow()
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.pollNow()
        })
        queue.async { [weak self] in
            guard let self else { return }
            self.poll()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    func pollNow() {
        queue.async { [weak self] in self?.poll() }
    }

    /// 主动搜索无线手柄，devices 会将结果通过 onUpdate 推出来
    func startDiscovery(seconds: TimeInterval = 8) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GCController.startWirelessControllerDiscovery { [weak self] in
                self?.pollNow()
            }
            let item = DispatchWorkItem { GCController.stopWirelessControllerDiscovery() }
            self.discoveryStopWorkItem?.cancel()
            self.discoveryStopWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    private func poll() {
        var devices: [PeripheralDevice] = []
        let controllers = GCController.controllers()
        for (index, controller) in controllers.enumerated() {
            let name = controller.vendorName ?? controller.productCategory
            let battery = controller.battery
            var level: Int? = nil
            var state: ChargingState = .unknown
            if let battery {
                let raw = battery.batteryLevel
                if raw >= 0 {
                    level = min(100, max(0, Int((raw * 100).rounded())))
                }
                switch battery.batteryState {
                case .charging: state = .charging
                case .discharging: state = .discharging
                case .full: state = .full
                default: state = .unknown
                }
                if let level, level >= 100 { state = .full }
            }
            let displayName = controllers.count > 1 ? "\(name) #\(index + 1)" : name
            devices.append(PeripheralDevice(
                id: DeviceNameKey.id(for: .gamepad, address: controller.productCategory + name, name: displayName),
                name: displayName,
                kind: .gamepad,
                level: level,
                state: state,
                source: .gamepad,
                address: nil,
                rssi: nil,
                components: [],
                lastUpdate: Date(),
                isConnected: true
            ))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(devices)
        }
    }
}
