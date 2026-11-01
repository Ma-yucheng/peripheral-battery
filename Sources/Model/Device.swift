import Foundation

// MARK: - 设备类型

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case mouse
    case keyboard
    case trackpad
    case gamepad
    case headset
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: return "鼠标"
        case .keyboard: return "键盘"
        case .trackpad: return "触控板"
        case .gamepad: return "手柄"
        case .headset: return "音频设备"
        case .other: return "其他外设"
        }
    }

    var symbolName: String {
        switch self {
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller"
        case .headset: return "headphones"
        case .other: return "square.stack.3d.up"
        }
    }

    var sortIndex: Int {
        switch self {
        case .mouse: return 0
        case .keyboard: return 1
        case .trackpad: return 2
        case .gamepad: return 3
        case .headset: return 4
        case .other: return 5
        }
    }
}

// MARK: - 数据来源

enum BatterySource: String, Codable {
    /// 蓝牙标准电池服务 0x180F / 0x2A19（可在本机实时读到，精度最高）
    case ble
    /// IOKit HID 属性（Apple 原厂外设的 BatteryPercent）
    case hid
    /// system_profiler 蓝牙设备信息（AirPods 等左/右/盒三路电量）
    case bluetooth
    /// GameController 框架（Xbox / DualSense / Switch Pro 等手柄）
    case gamepad
    /// 演示数据
    case demo

    var label: String {
        switch self {
        case .ble: return "BLE 电池服务"
        case .hid: return "IOKit HID"
        case .bluetooth: return "蓝牙系统信息"
        case .gamepad: return "GameController"
        case .demo: return "演示数据"
        }
    }

    var shortLabel: String {
        switch self {
        case .ble: return "BLE"
        case .hid: return "HID"
        case .bluetooth: return "BT"
        case .gamepad: return "GC"
        case .demo: return "DEMO"
        }
    }

    /// 融合时数值优先级，越小越可信
    var priority: Int {
        switch self {
        case .ble: return 0
        case .hid: return 1
        case .gamepad: return 2
        case .bluetooth: return 3
        case .demo: return 9
        }
    }
}

// MARK: - 充电状态

enum ChargingState: String, Codable {
    case unknown
    case charging
    case discharging
    case full

    var label: String {
        switch self {
        case .unknown: return "未知"
        case .charging: return "充电中"
        case .discharging: return "使用中"
        case .full: return "已充满"
        }
    }
}

// MARK: - 分量电量（AirPods 左/右/充电盒等）

struct BatteryComponent: Identifiable, Equatable, Codable {
    var label: String
    var level: Int

    var id: String { label }
}

// MARK: - 设备

struct PeripheralDevice: Identifiable, Equatable, Codable {
    /// 稳定标识：由来源 + 硬件地址（或名称）生成，用于选择框持久化
    var id: String
    var name: String
    var kind: DeviceKind
    /// 主电量 0...100，nil 表示设备未提供电量
    var level: Int?
    var state: ChargingState = .unknown
    var source: BatterySource
    var address: String?
    var rssi: Int?
    var components: [BatteryComponent] = []
    var lastUpdate: Date = Date()
    var isConnected: Bool = true
    var isDemo: Bool = false

    var levelText: String {
        guard let level = level else { return "--" }
        return "\(level)%"
    }

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 45
    }

    /// 有电量分量时，取最低分量作为"危险度"参考
    var criticalLevel: Int? {
        let all = components.map(\.level) + (level.map { [$0] } ?? [])
        return all.min()
    }
}

// MARK: - 名称归一化（跨数据源合并用）

enum DeviceNameKey {
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: "\u{00a0}", with: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s
    }

    static func id(for source: BatterySource, address: String?, name: String) -> String {
        if let address = address, !address.isEmpty {
            return "\(source.rawValue):\(address.lowercased())"
        }
        return "\(source.rawValue):\(normalize(name))"
    }
}

// MARK: - 名称推断设备类型（当系统未给出 minorType / usage 时兜底）

enum DeviceKindInference {
    private static let rules: [(DeviceKind, [String])] = [
        (.mouse, ["mouse", "鼠标", "magic mouse", "mx master", "mx anywhere", "basilisk", "deathadder", "viper", "razer", "logitech m", "trackball", "m720", "m590", "m650", "lift"]),
        (.keyboard, ["keyboard", "键盘", "keychron", "mx keys", "magic keyboard", "langtu", "nuphy", "anne pro", "hhkb", "k8", "k3 ", "游戏键盘"]),
        (.trackpad, ["trackpad", "触控板", "magic trackpad"]),
        (.gamepad, ["gamepad", "controller", "手柄", "xbox", "dualsense", "dualshock", "joy-con", "switch pro", "8bitdo", "vader", "flydigi", "飞智", "北通", "betop"]),
        (.headset, ["headphone", "headset", "耳机", "airpods", "speaker", "音箱", "buds", "edifier", "漫步者", "bose", "sony wh", "wh-", "qc", "soundcore"])
    ]

    static func infer(_ name: String) -> DeviceKind {
        let n = name.lowercased()
        for (kind, keywords) in rules {
            for keyword in keywords where n.contains(keyword) {
                return kind
            }
        }
        return .other
    }
}
