import SwiftUI

// MARK: - 图标按钮

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .help(help)
    }
}

// MARK: - 主面板

struct DashboardView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings

    let onOpenSettings: () -> Void
    let onToggleWidget: () -> Void
    let onRescan: () -> Void

    private var visibleDevices: [PeripheralDevice] {
        store.devices.filter { settings.isVisible($0) }
    }

    private var lowestLevel: Int? {
        visibleDevices.compactMap(\.criticalLevel).min()
    }

    private var contentHeight: CGFloat {
        Layout.contentHeight(mode: settings.displayMode,
                             devices: visibleDevices,
                             showSparkline: settings.showSparkline)
    }

    private var panelHeight: CGFloat {
        Layout.panelHeight(mode: settings.displayMode,
                           devices: visibleDevices,
                           showSparkline: settings.showSparkline,
                           selectorExpanded: settings.selectorExpanded)
    }

    private var subtitle: String {
        let time = DateFormatter.localizedString(from: store.lastRefresh, dateStyle: .none, timeStyle: .medium)
        return "\(visibleDevices.count)/\(store.devices.count) 台显示 · 更新 \(time)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.18)
            modeRow
            Divider().opacity(0.12)
            contentArea
            Divider().opacity(0.12)
            selectorArea
            Divider().opacity(0.12)
            footer
        }
        .frame(width: Layout.panelWidth, height: panelHeight)
        .background(Color.clear)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 9) {
            BatteryGlyph(level: lowestLevel,
                         tint: Theme.levelColor(lowestLevel),
                         size: 18,
                         charging: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("外设电量")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton(symbol: "arrow.clockwise", help: "重新扫描", action: onRescan)
            IconButton(symbol: settings.widgetVisible ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle",
                       help: "桌面小组件",
                       active: settings.widgetVisible,
                       action: onToggleWidget)
            IconButton(symbol: "gearshape", help: "设置", action: onOpenSettings)
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    // MARK: 模式选择

    private var modeRow: some View {
        HStack(spacing: 3) {
            ForEach(DisplayMode.allCases) { mode in
                ModeButton(mode: mode, active: settings.displayMode == mode, compact: true) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        settings.displayMode = mode
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: 内容

    private var contentArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            BatteryContent(mode: settings.displayMode,
                           devices: visibleDevices,
                           settings: settings,
                           history: { store.history(for: $0) })
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
        }
        .frame(height: contentHeight)
    }

    // MARK: 设备选择

    private var selectorArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { settings.selectorExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .medium))
                        Text("设备选择")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("\(visibleDevices.count)/\(store.devices.count)")
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                        Image(systemName: settings.selectorExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if settings.selectorExpanded {
                    Button("全部显示") { settings.showAll(store.devices) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.accentColor)
                    Button("全部隐藏") { settings.hideAll(store.devices) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)

            if settings.selectorExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        if store.devices.isEmpty {
                            Text("暂未发现外设")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                        }
                        ForEach(store.devices) { device in
                            DeviceToggleRow(device: device, settings: settings)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: 底部状态

    private var footer: some View {
        HStack(spacing: 6) {
            StatusDot(color: store.bleStatus.poweredOn ? Color.green : Color.orange, size: 5)
            Text(store.bleStatus.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.secondary)
            if settings.demoMode {
                Text("演示数据")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(Color.orange)
            }
            Spacer()
            Button {
                onOpenSettings()
            } label: {
                Text("更多设置")
                    .font(.system(size: 9.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }
}

// MARK: - 设备选择行

struct DeviceToggleRow: View {
    let device: PeripheralDevice
    @ObservedObject var settings: AppSettings

    private var visible: Bool { settings.isVisible(device) }

    var body: some View {
        Button {
            settings.toggleVisibility(device)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: visible ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(visible ? Color.accentColor : Color.secondary)
                DeviceIconBadge(kind: device.kind, size: 17, tint: Theme.color(for: device))
                Text(device.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(visible ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Text(device.source.shortLabel)
                    .font(.system(size: 8.5, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .foregroundStyle(Color.secondary)
                Text(device.levelText)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(visible ? Theme.color(for: device) : Color.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
