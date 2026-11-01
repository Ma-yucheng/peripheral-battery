import SwiftUI

// MARK: - 尺寸与配色

enum Layout {
    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 620
    static let cardRadius: CGFloat = 14
    static let contentMinHeight: CGFloat = 92
    static let contentMaxHeight: CGFloat = 560
    static let selectorRowHeight: CGFloat = 24

    /// 内容区高度：按显示模式与设备列表估算（卡片模式会算上走势线与分量电量）
    static func contentHeight(mode: DisplayMode,
                              devices: [PeripheralDevice],
                              showSparkline: Bool) -> CGFloat {
        let count = max(1, devices.count)
        let raw: CGFloat
        switch mode {
        case .cards:
            let perCard = devices.reduce(CGFloat(0)) { sum, device in
                var height: CGFloat = 88
                if showSparkline { height += 16 }
                if !device.components.isEmpty { height += 30 }
                if !device.isConnected { height += 6 }
                return sum + height
            }
            raw = (devices.isEmpty ? 78 : perCard) + 20
        case .rings:
            raw = CGFloat((count + 1) / 2) * 110 + 20
        case .bars:
            raw = CGFloat(count) * 38 + 18
        case .pills:
            raw = CGFloat((count + 1) / 2) * 36 + 20
        case .minimal:
            raw = CGFloat(count) * 33 + 18
        case .grid:
            raw = CGFloat((count + 2) / 3) * 68 + 18
        }
        return min(max(raw, contentMinHeight), contentMaxHeight)
    }

    /// 整个面板高度：头部 + 模式栏 + 内容 + 设备选择 + 底部状态
    static func panelHeight(mode: DisplayMode,
                            devices: [PeripheralDevice],
                            showSparkline: Bool,
                            selectorExpanded: Bool) -> CGFloat {
        let base: CGFloat = 154
        let content = contentHeight(mode: mode, devices: devices, showSparkline: showSparkline)
        let listHeight = selectorExpanded ? min(CGFloat(max(1, devices.count)) * selectorRowHeight + 10, 200) : 0
        return min(800, base + content + listHeight)
    }
}

extension View {
    /// 离线（休眠）设备整体压暗，避免和实时读数混淆
    func offlineDim(_ device: PeripheralDevice) -> some View {
        opacity(device.isConnected ? 1.0 : 0.52)
    }
}

enum Theme {

    /// 电量 → 颜色：红 / 橙 / 黄 / 绿 / 青
    static func levelColor(_ level: Int?) -> Color {
        guard let level else { return Color.secondary }
        switch level {
        case ..<15:
            return Color(red: 0.87, green: 0.20, blue: 0.24)
        case ..<35:
            return Color(red: 0.90, green: 0.47, blue: 0.05)
        case ..<60:
            return Color(red: 0.72, green: 0.56, blue: 0.02)
        case ..<85:
            return Color(red: 0.13, green: 0.60, blue: 0.32)
        default:
            return Color(red: 0.04, green: 0.53, blue: 0.47)
        }
    }

    static func color(for device: PeripheralDevice) -> Color {
        if device.state == .charging { return Color(red: 0.16, green: 0.50, blue: 0.92) }
        return levelColor(device.level)
    }

    static func nsColor(for level: Int?) -> NSColor {
        guard let level else { return NSColor.secondaryLabelColor }
        switch level {
        case ..<15: return NSColor.systemRed
        case ..<35: return NSColor.systemOrange
        case ..<60: return NSColor.systemYellow
        case ..<85: return NSColor.systemGreen
        default: return NSColor.systemTeal
        }
    }

    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.075)
    static let track = Color.primary.opacity(0.10)
    static let subtleText = Color.secondary
}

// MARK: - 通用小组件

/// 设备类型图标
struct DeviceIconBadge: View {
    let kind: DeviceKind
    var size: CGFloat = 34
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(tint.opacity(0.15))
            Image(systemName: kind.symbolName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

/// 电池图标：外形 + 比例填充
struct BatteryGlyph: View {
    var level: Int?
    var tint: Color
    var size: CGFloat = 20
    var charging: Bool = false

    private var progress: CGFloat {
        guard let level else { return 0 }
        return CGFloat(max(0, min(100, level))) / 100
    }

    private var bodyWidth: CGFloat { size * 1.72 }
    private var inset: CGFloat { size * 0.11 }
    private var innerWidth: CGFloat { (bodyWidth - inset * 2) * progress }

    var body: some View {
        HStack(spacing: size * 0.07) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .stroke(Color.primary.opacity(0.28), lineWidth: max(1, size * 0.06))
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, innerWidth))
                    .padding(inset)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: bodyWidth, height: size)

            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: max(1, size * 0.12), height: size * 0.36)
        }
    }
}

/// 横向电量条
struct LevelBar: View {
    let progress: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.72), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(max(0, min(1, progress)))))
            }
        }
        .frame(height: height)
    }
}

/// 环形仪表
struct RingGauge<Content: View>: View {
    var progress: Double?
    var tint: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            if let progress, progress > 0 {
                Circle()
                    .trim(from: 0, to: max(0.004, min(1, progress)))
                    .stroke(AngularGradient(gradient: Gradient(colors: [tint.opacity(0.5), tint]),
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: progress)
            }
            content()
        }
    }
}

/// 电量走势线（按样本区间自适应缩放，微小变化也能看清）
struct Sparkline: View {
    var values: [Int]
    var tint: Color
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let points = points(in: geo.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.addLines(points)
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.015)],
                                         startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(tint.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: height)
        .opacity(values.count > 1 ? 1 : 0)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lowest = CGFloat(values.min() ?? 0) - 4
        let highest = CGFloat(values.max() ?? 100) + 4
        let span = max(10, highest - lowest)
        let inset: CGFloat = 1.5

        var result: [CGPoint] = []
        result.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let ratio = (CGFloat(value) - lowest) / span
            let y = inset + (size.height - inset * 2) * (1 - ratio)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }
}

/// 小圆点
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// 显示模式切换按钮
struct ModeButton: View {
    let mode: DisplayMode
    let active: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: compact ? 11 : 13, weight: .medium))
                Text(mode.title)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 5 : 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(active ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 分组
struct DeviceGroup: Identifiable {
    let kind: DeviceKind
    let devices: [PeripheralDevice]
    var id: String { kind.rawValue }
}

enum DeviceGrouping {
    static func group(_ devices: [PeripheralDevice], byKind: Bool) -> [DeviceGroup] {
        guard byKind else {
            return devices.isEmpty ? [] : [DeviceGroup(kind: .other, devices: devices)]
        }
        var buckets: [DeviceKind: [PeripheralDevice]] = [:]
        for device in devices {
            buckets[device.kind, default: []].append(device)
        }
        return DeviceKind.allCases
            .compactMap { kind in
                guard let list = buckets[kind], !list.isEmpty else { return nil }
                return DeviceGroup(kind: kind, devices: list)
            }
    }
}

/// 分组标题
struct GroupHeader: View {
    let kind: DeviceKind
    var widget: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbolName)
                .font(.system(size: widget ? 10 : 9, weight: .semibold))
            Text(kind.title)
                .font(.system(size: widget ? 11 : 10, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.secondary)
        .padding(.leading, 2)
        .padding(.top, 2)
    }
}
