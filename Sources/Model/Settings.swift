import Foundation
import Combine
import CoreGraphics

// MARK: - 显示模式

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case cards
    case rings
    case bars
    case pills
    case minimal
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "卡片"
        case .rings: return "环形"
        case .bars: return "条形"
        case .pills: return "胶囊"
        case .minimal: return "极简"
        case .grid: return "网格"
        }
    }

    var symbolName: String {
        switch self {
        case .cards: return "rectangle.grid.1x2"
        case .rings: return "circle.dashed"
        case .bars: return "chart.bar.fill"
        case .pills: return "capsule.fill"
        case .minimal: return "text.alignleft"
        case .grid: return "square.grid.2x2.fill"
        }
    }

    var detail: String {
        switch self {
        case .cards: return "每个设备一张大卡片，含进度条与走势"
        case .rings: return "环形仪表盘，一眼看百分比"
        case .bars: return "横向条形，排列最紧凑"
        case .pills: return "小胶囊，适合桌面常驻"
        case .minimal: return "只有名称和数字，极简风格"
        case .grid: return "方格矩阵，小图标 + 大数字"
        }
    }
}

// MARK: - 桌面组件

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 260
        case .medium: return 320
        case .large: return 400
        }
    }
}

enum WidgetLevel: String, Codable, CaseIterable, Identifiable {
    /// 贴在桌面层（和 macOS 原生小组件一样，被窗口盖住）
    case desktop
    /// 浮在所有窗口之上
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "桌面层（同原生小组件）"
        case .floating: return "浮于最前"
        }
    }

    var shortTitle: String {
        switch self {
        case .desktop: return "桌面层"
        case .floating: return "浮于最前"
        }
    }
}

enum WidgetBackground: String, Codable, CaseIterable, Identifiable {
    case glass
    case solid
    case gradient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: return "毛玻璃"
        case .solid: return "纯色"
        case .gradient: return "渐变"
        }
    }
}

// MARK: - 设置

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let displayMode = "pb.displayMode"
        static let widgetMode = "pb.widgetMode"
        static let showPercent = "pb.showPercent"
        static let showSparkline = "pb.showSparkline"
        static let showSourceBadge = "pb.showSourceBadge"
        static let groupByKind = "pb.groupByKind"
        static let refreshInterval = "pb.refreshInterval"
        static let hiddenDevices = "pb.hiddenDeviceIDs"
        static let widgetVisible = "pb.widgetVisible"
        static let widgetSize = "pb.widgetSize"
        static let widgetLevel = "pb.widgetLevel"
        static let widgetBackground = "pb.widgetBackground"
        static let widgetOpacity = "pb.widgetOpacity"
        static let widgetOwnMode = "pb.widgetOwnMode"
        static let lowThreshold = "pb.lowThreshold"
        static let menuBarShowsPercent = "pb.menuBarShowsPercent"
        static let demoMode = "pb.demoMode"
        static let accentStyle = "pb.accentStyle"
        static let widgetX = "pb.widgetX"
        static let widgetY = "pb.widgetY"
    }

    private let defaults: UserDefaults

    @Published var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    @Published var widgetMode: DisplayMode {
        didSet { defaults.set(widgetMode.rawValue, forKey: Key.widgetMode) }
    }

    @Published var showPercent: Bool {
        didSet { defaults.set(showPercent, forKey: Key.showPercent) }
    }

    @Published var showSparkline: Bool {
        didSet { defaults.set(showSparkline, forKey: Key.showSparkline) }
    }

    @Published var showSourceBadge: Bool {
        didSet { defaults.set(showSourceBadge, forKey: Key.showSourceBadge) }
    }

    @Published var groupByKind: Bool {
        didSet { defaults.set(groupByKind, forKey: Key.groupByKind) }
    }

    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    /// 被用户取消勾选的设备（默认全部显示，新设备自动出现）
    @Published var hiddenDeviceIDs: Set<String> {
        didSet { defaults.set(Array(hiddenDeviceIDs), forKey: Key.hiddenDevices) }
    }

    @Published var widgetVisible: Bool {
        didSet { defaults.set(widgetVisible, forKey: Key.widgetVisible) }
    }

    @Published var widgetSize: WidgetSize {
        didSet { defaults.set(widgetSize.rawValue, forKey: Key.widgetSize) }
    }

    @Published var widgetLevel: WidgetLevel {
        didSet { defaults.set(widgetLevel.rawValue, forKey: Key.widgetLevel) }
    }

    @Published var widgetBackground: WidgetBackground {
        didSet { defaults.set(widgetBackground.rawValue, forKey: Key.widgetBackground) }
    }

    @Published var widgetOpacity: Double {
        didSet { defaults.set(widgetOpacity, forKey: Key.widgetOpacity) }
    }

    /// 桌面组件是否独立于面板使用自己的显示模式
    @Published var widgetOwnMode: Bool {
        didSet { defaults.set(widgetOwnMode, forKey: Key.widgetOwnMode) }
    }

    @Published var lowThreshold: Int {
        didSet { defaults.set(lowThreshold, forKey: Key.lowThreshold) }
    }

    @Published var menuBarShowsPercent: Bool {
        didSet { defaults.set(menuBarShowsPercent, forKey: Key.menuBarShowsPercent) }
    }

    @Published var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }

    @Published var accentStyle: String {
        didSet { defaults.set(accentStyle, forKey: Key.accentStyle) }
    }

    /// 面板里「设备选择」区块是否展开（仅内存，不持久化）
    @Published var selectorExpanded: Bool = true

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        func rawMode(_ key: String, fallback: DisplayMode) -> DisplayMode {
            guard let raw = defaults.string(forKey: key), let mode = DisplayMode(rawValue: raw) else { return fallback }
            return mode
        }
        func rawWidgetSize(_ key: String) -> WidgetSize {
            guard let raw = defaults.string(forKey: key), let size = WidgetSize(rawValue: raw) else { return .medium }
            return size
        }
        func rawWidgetLevel(_ key: String) -> WidgetLevel {
            guard let raw = defaults.string(forKey: key), let level = WidgetLevel(rawValue: raw) else { return .desktop }
            return level
        }
        func rawBackground(_ key: String) -> WidgetBackground {
            guard let raw = defaults.string(forKey: key), let bg = WidgetBackground(rawValue: raw) else { return .glass }
            return bg
        }

        displayMode = rawMode(Key.displayMode, fallback: .cards)
        widgetMode = rawMode(Key.widgetMode, fallback: .rings)
        showPercent = defaults.object(forKey: Key.showPercent) as? Bool ?? true
        showSparkline = defaults.object(forKey: Key.showSparkline) as? Bool ?? true
        showSourceBadge = defaults.object(forKey: Key.showSourceBadge) as? Bool ?? true
        groupByKind = defaults.object(forKey: Key.groupByKind) as? Bool ?? true
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double ?? 1.0
        hiddenDeviceIDs = Set(defaults.stringArray(forKey: Key.hiddenDevices) ?? [])
        widgetVisible = defaults.object(forKey: Key.widgetVisible) as? Bool ?? true
        widgetSize = rawWidgetSize(Key.widgetSize)
        widgetLevel = rawWidgetLevel(Key.widgetLevel)
        widgetBackground = rawBackground(Key.widgetBackground)
        widgetOpacity = defaults.object(forKey: Key.widgetOpacity) as? Double ?? 0.92
        widgetOwnMode = defaults.object(forKey: Key.widgetOwnMode) as? Bool ?? false
        lowThreshold = defaults.object(forKey: Key.lowThreshold) as? Int ?? 20
        menuBarShowsPercent = defaults.object(forKey: Key.menuBarShowsPercent) as? Bool ?? true
        demoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? false
        accentStyle = defaults.string(forKey: Key.accentStyle) ?? "aurora"
    }

    // MARK: 选择框

    func isVisible(_ device: PeripheralDevice) -> Bool {
        !hiddenDeviceIDs.contains(device.id)
    }

    func setVisible(_ visible: Bool, for device: PeripheralDevice) {
        if visible {
            hiddenDeviceIDs.remove(device.id)
        } else {
            hiddenDeviceIDs.insert(device.id)
        }
    }

    func toggleVisibility(_ device: PeripheralDevice) {
        setVisible(!isVisible(device), for: device)
    }

    func showAll(_ devices: [PeripheralDevice]) {
        var hidden = hiddenDeviceIDs
        for device in devices { hidden.remove(device.id) }
        hiddenDeviceIDs = hidden
    }

    func hideAll(_ devices: [PeripheralDevice]) {
        var hidden = hiddenDeviceIDs
        for device in devices { hidden.insert(device.id) }
        hiddenDeviceIDs = hidden
    }

    // MARK: 桌面组件位置

    func saveWidgetPosition(_ point: CGPoint) {
        defaults.set(Double(point.x), forKey: Key.widgetX)
        defaults.set(Double(point.y), forKey: Key.widgetY)
    }

    func loadWidgetPosition() -> CGPoint? {
        guard defaults.object(forKey: Key.widgetX) != nil, defaults.object(forKey: Key.widgetY) != nil else { return nil }
        let x = defaults.double(forKey: Key.widgetX)
        let y = defaults.double(forKey: Key.widgetY)
        if x == 0 && y == 0 { return nil }
        return CGPoint(x: x, y: y)
    }

    /// 面板与组件共用的模式
    func effectiveWidgetMode() -> DisplayMode {
        widgetOwnMode ? widgetMode : displayMode
    }
}
