import SwiftUI

// MARK: - 卡片表面

struct CardSurface: ViewModifier {
    var widget: Bool = false
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(widget: Bool = false, radius: CGFloat = 12) -> some View {
        modifier(CardSurface(widget: widget, radius: radius))
    }
}

// MARK: - 模式容器

struct BatteryContent: View {
    let mode: DisplayMode
    let devices: [PeripheralDevice]
    let settings: AppSettings
    let history: (String) -> [Int]
    var widget: Bool = false

    var body: some View {
        if devices.isEmpty {
            EmptyDevicesView(widget: widget)
        } else {
            switch mode {
            case .cards:
                CardsMode(devices: devices, settings: settings, history: history, widget: widget)
            case .rings:
                RingsMode(devices: devices, settings: settings, widget: widget)
            case .bars:
                BarsMode(devices: devices, settings: settings, widget: widget)
            case .pills:
                PillsMode(devices: devices, widget: widget)
            case .minimal:
                MinimalMode(devices: devices, settings: settings, widget: widget)
            case .grid:
                GridMode(devices: devices, settings: settings, widget: widget)
            }
        }
    }
}

// MARK: - 空状态

struct EmptyDevicesView: View {
    var widget: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: widget ? 24 : 20, weight: .light))
                .foregroundStyle(Color.secondary)
            Text("暂无可读电量")
                .font(.system(size: widget ? 12 : 11.5, weight: .semibold))
            Text("请确认外设已通过蓝牙连接并授予蓝牙权限；\n若设备休眠，按一下鼠标或键盘即可唤醒")
                .font(.system(size: widget ? 10 : 9.5))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, widget ? 28 : 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 1. 卡片模式

struct CardsMode: View {
    let devices: [PeripheralDevice]
    let settings: AppSettings
    let history: (String) -> [Int]
    var widget: Bool = false

    private var groups: [DeviceGroup] {
        DeviceGrouping.group(devices, byKind: settings.groupByKind)
    }

    var body: some View {
        VStack(spacing: widget ? 9 : 8) {
            ForEach(groups) { group in
                if settings.groupByKind && groups.count > 1 {
                    GroupHeader(kind: group.kind, widget: widget)
                }
                ForEach(group.devices) { device in
                    DeviceCard(device: device,
                               settings: settings,
                               samples: history(device.id),
                               widget: widget)
                }
            }
        }
    }
}

struct DeviceCard: View {
    let device: PeripheralDevice
    let settings: AppSettings
    let samples: [Int]
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }
    private var progress: Double { Double(device.level ?? 0) / 100.0 }
    private var subtitle: String { statusText }

    private var statusText: String {
        var parts: [String] = [device.kind.title]
        if device.isDemo {
            parts.append("演示")
        } else if settings.showSourceBadge {
            parts.append(device.source.shortLabel)
        }
        if device.state == .charging { parts.append("充电中") }
        if !device.isConnected { parts.append("离线") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: widget ? 8 : 6) {
            HStack(spacing: 10) {
                DeviceIconBadge(kind: device.kind, size: widget ? 38 : 32, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: widget ? 13.5 : 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(statusText)
                        .font(.system(size: widget ? 10.5 : 9.5))
                        .foregroundStyle(Theme.subtleText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    if settings.showPercent {
                        Text(device.levelText)
                            .font(.system(size: widget ? 21 : 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                    }
                    BatteryGlyph(level: device.level,
                                 tint: tint,
                                 size: widget ? 17 : 15,
                                 charging: device.state == .charging)
                }
            }

            LevelBar(progress: progress, tint: tint, height: widget ? 6 : 5)

            if settings.showSparkline && samples.count > 2 {
                Sparkline(values: samples, tint: tint, height: widget ? 14 : 10)
            }

            if !device.components.isEmpty {
                componentsRow
            }
        }
        .padding(widget ? 12 : 9)
        .cardSurface(widget: widget)
        .offlineDim(device)
    }

    private var componentsRow: some View {
        HStack(spacing: 5) {
            ForEach(device.components) { component in
                Text("\(component.label) \(component.level)%")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.levelColor(component.level).opacity(0.14)))
                    .foregroundStyle(Theme.levelColor(component.level))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 2. 环形模式

struct RingsMode: View {
    let devices: [PeripheralDevice]
    let settings: AppSettings
    var widget: Bool = false

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: widget ? 10 : 8) {
            ForEach(devices) { device in
                RingTile(device: device, settings: settings, widget: widget)
            }
        }
    }
}

struct RingTile: View {
    let device: PeripheralDevice
    let settings: AppSettings
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }
    private var progress: Double? {
        guard let level = device.level else { return nil }
        return Double(level) / 100.0
    }

    var body: some View {
        VStack(spacing: 5) {
            RingGauge(progress: progress, tint: tint, lineWidth: widget ? 9 : 7) {
                VStack(spacing: 0) {
                    Text(device.levelText)
                        .font(.system(size: widget ? 21 : 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Text(device.kind.title)
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.subtleText)
                }
            }
            .frame(width: widget ? 84 : 68, height: widget ? 84 : 68)

            Text(device.name)
                .font(.system(size: widget ? 11 : 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, widget ? 10 : 8)
        .cardSurface(widget: widget)
        .offlineDim(device)
    }
}

// MARK: - 3. 条形模式

struct BarsMode: View {
    let devices: [PeripheralDevice]
    let settings: AppSettings
    var widget: Bool = false

    private var groups: [DeviceGroup] {
        DeviceGrouping.group(devices, byKind: settings.groupByKind)
    }

    var body: some View {
        VStack(spacing: widget ? 8 : 7) {
            ForEach(groups) { group in
                if settings.groupByKind && groups.count > 1 {
                    GroupHeader(kind: group.kind, widget: widget)
                }
                ForEach(group.devices) { device in
                    BarRow(device: device, settings: settings, widget: widget)
                }
            }
        }
    }
}

struct BarRow: View {
    let device: PeripheralDevice
    let settings: AppSettings
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }
    private var progress: Double { Double(device.level ?? 0) / 100.0 }

    var body: some View {
        HStack(spacing: 9) {
            DeviceIconBadge(kind: device.kind, size: widget ? 24 : 22, tint: tint)
            Text(device.name)
                .font(.system(size: widget ? 12 : 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: widget ? 168 : 150, alignment: .leading)
            LevelBar(progress: progress, tint: tint, height: 5)
            if settings.showPercent {
                Text(device.levelText)
                    .font(.system(size: widget ? 12 : 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, widget ? 12 : 10)
        .padding(.vertical, widget ? 9 : 8)
        .cardSurface(widget: widget)
        .offlineDim(device)
    }
}

// MARK: - 4. 胶囊模式

struct PillsMode: View {
    let devices: [PeripheralDevice]
    var widget: Bool = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: widget ? 168 : 152), spacing: 6)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(devices) { device in
                PillChip(device: device, widget: widget)
            }
        }
    }
}

struct PillChip: View {
    let device: PeripheralDevice
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: device.kind.symbolName)
                .font(.system(size: widget ? 10 : 9, weight: .medium))
            Text(device.name)
                .font(.system(size: widget ? 11.5 : 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Text(device.levelText)
                .font(.system(size: widget ? 11.5 : 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, widget ? 9 : 8)
        .padding(.vertical, widget ? 6 : 5)
        .background(Capsule().fill(tint.opacity(0.13)))
        .overlay(Capsule().stroke(tint.opacity(0.26), lineWidth: 1))
        .foregroundStyle(tint)
        .offlineDim(device)
    }
}

// MARK: - 5. 极简模式

struct MinimalMode: View {
    let devices: [PeripheralDevice]
    let settings: AppSettings
    var widget: Bool = false

    private var groups: [DeviceGroup] {
        DeviceGrouping.group(devices, byKind: settings.groupByKind)
    }

    var body: some View {
        VStack(spacing: widget ? 6 : 5) {
            ForEach(groups) { group in
                if settings.groupByKind && groups.count > 1 {
                    GroupHeader(kind: group.kind, widget: widget)
                }
                ForEach(group.devices) { device in
                    MinimalRow(device: device, settings: settings, widget: widget)
                }
            }
        }
    }
}

struct MinimalRow: View {
    let device: PeripheralDevice
    let settings: AppSettings
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.kind.symbolName)
                .font(.system(size: widget ? 11 : 10))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(device.name)
                .font(.system(size: widget ? 12 : 11.5))
                .lineLimit(1)
            Spacer(minLength: 6)
            LevelBar(progress: Double(device.level ?? 0) / 100.0, tint: tint, height: 3)
                .frame(width: widget ? 56 : 44)
            if settings.showPercent {
                Text(device.levelText)
                    .font(.system(size: widget ? 12 : 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.horizontal, widget ? 10 : 8)
        .padding(.vertical, widget ? 7 : 6)
        .cardSurface(widget: widget, radius: 9)
        .offlineDim(device)
    }
}

// MARK: - 6. 网格模式

struct GridMode: View {
    let devices: [PeripheralDevice]
    let settings: AppSettings
    var widget: Bool = false

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 6),
         GridItem(.flexible(), spacing: 6),
         GridItem(.flexible(), spacing: 6)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(devices) { device in
                GridTile(device: device, settings: settings, widget: widget)
            }
        }
    }
}

struct GridTile: View {
    let device: PeripheralDevice
    let settings: AppSettings
    var widget: Bool = false

    private var tint: Color { Theme.color(for: device) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: device.kind.symbolName)
                    .font(.system(size: widget ? 11 : 10, weight: .medium))
                    .foregroundStyle(tint)
                if settings.showPercent {
                    Text(device.levelText)
                        .font(.system(size: widget ? 17 : 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
            }
            Text(device.name)
                .font(.system(size: widget ? 9.5 : 9))
                .foregroundStyle(Theme.subtleText)
                .lineLimit(1)
                .truncationMode(.middle)
            LevelBar(progress: Double(device.level ?? 0) / 100.0, tint: tint, height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, widget ? 10 : 9)
        .padding(.horizontal, 4)
        .cardSurface(widget: widget)
        .offlineDim(device)
    }
}
