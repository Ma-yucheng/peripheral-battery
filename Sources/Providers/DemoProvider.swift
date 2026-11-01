import Foundation

/// 演示数据：用于预览 6 种显示模式与桌面组件效果。
/// 默认关闭，开关位于设置面板，所有演示条目都会带 "演示" 标记。
final class DemoProvider {

    var onUpdate: (([PeripheralDevice]) -> Void)?

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "peripheral-battery.demo", qos: .utility)
    private var tick: Double = 0

    private struct Seed {
        var name: String
        var kind: DeviceKind
        var base: Double
        var amplitude: Double
        var phase: Double
    }

    private let seeds: [Seed] = [
        Seed(name: "MX Master 3S", kind: .mouse, base: 68, amplitude: 6, phase: 0),
        Seed(name: "Magic Keyboard", kind: .keyboard, base: 46, amplitude: 4, phase: 1.2),
        Seed(name: "DualSense 手柄", kind: .gamepad, base: 23, amplitude: 3, phase: 2.4),
        Seed(name: "AirPods Pro", kind: .headset, base: 82, amplitude: 5, phase: 3.6)
    ]

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.emit()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1.5, repeating: 1.5)
            timer.setEventHandler { [weak self] in
                self?.tick += 1.5
                self?.emit()
            }
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

    private func emit() {
        var devices: [PeripheralDevice] = []
        for (index, seed) in seeds.enumerated() {
            let drift = sin(tick / 26.0 + seed.phase) * seed.amplitude + cos(tick / 61.0 + seed.phase) * 3
            let level = Int(max(3, min(100, seed.base + drift)))
            var device = PeripheralDevice(
                id: "demo:\(index)",
                name: seed.name,
                kind: seed.kind,
                level: level,
                state: level <= 20 ? .charging : .discharging,
                source: .demo,
                address: "DEMO-\(index)",
                rssi: nil,
                components: [],
                lastUpdate: Date(),
                isConnected: true
            )
            device.isDemo = true
            if seed.kind == .headset {
                device.components = [
                    BatteryComponent(label: "左耳", level: max(1, level - 4)),
                    BatteryComponent(label: "右耳", level: max(1, level - 2)),
                    BatteryComponent(label: "充电盒", level: min(100, level + 9))
                ]
            }
            devices.append(device)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(devices)
        }
    }
}
