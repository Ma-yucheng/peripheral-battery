import SwiftUI

// MARK: - 桌面小组件

struct WidgetView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings

    let onOpenSettings: () -> Void

    /// 窗口四周预留的透明边距，用来容纳阴影
    static let shadowMargin: CGFloat = 18

    private var visibleDevices: [PeripheralDevice] {
        store.devices.filter { settings.isVisible($0) }
    }

    private var lowestLevel: Int? {
        visibleDevices.compactMap(\.criticalLevel).min()
    }

    private var isDarkStyling: Bool {
        settings.widgetBackground == .gradient
    }

    private var mode: DisplayMode {
        settings.effectiveWidgetMode()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            BatteryContent(mode: mode,
                           devices: visibleDevices,
                           settings: settings,
                           history: { store.history(for: $0) },
                           widget: true)
        }
        .padding(13)
        .frame(width: settings.widgetSize.width, alignment: .leading)
        .background(background.opacity(settings.widgetOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(isDarkStyling ? 0.10 : 0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: 7)
        .padding(WidgetView.shadowMargin)
        .frame(width: settings.widgetSize.width + WidgetView.shadowMargin * 2, alignment: .center)
        .environment(\.colorScheme, isDarkStyling ? .dark : colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var header: some View {
        HStack(spacing: 6) {
            BatteryGlyph(level: lowestLevel, tint: Theme.levelColor(lowestLevel), size: 14)
            Text("外设电量")
                .font(.system(size: 11.5, weight: .semibold))
            Spacer(minLength: 4)
            Text("\(visibleDevices.count) 台")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.secondary)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 9))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
            .help("设置")
        }
    }

    @ViewBuilder
    private var background: some View {
        switch settings.widgetBackground {
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .solid:
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
        case .gradient:
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.19),
                                    Color(red: 0.16, green: 0.13, blue: 0.24)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        }
    }
}

// MARK: - 设置窗口

struct SettingsView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings

    let onRescan: () -> Void
    let onDiscoverGamepads: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                modeSection
                displaySection
                widgetSection
                deviceSection
                sourceSection
                aboutSection
            }
            .padding(18)
        }
        .frame(width: 560, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 显示模式

    private var modeSection: some View {
        SettingsSection(title: "显示模式", subtitle: "面板与桌面组件可各用一套模式，共 6 种") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(DisplayMode.allCases) { mode in
                    ModePreviewTile(mode: mode,
                                    active: settings.displayMode == mode,
                                    action: { settings.displayMode = mode })
                }
            }
        }
    }

    // MARK: 显示选项

    private var displaySection: some View {
        SettingsSection(title: "显示选项") {
            VStack(spacing: 8) {
                ToggleRow(title: "显示电量百分比", isOn: $settings.showPercent)
                ToggleRow(title: "显示电量走势线（卡片模式）", isOn: $settings.showSparkline)
                ToggleRow(title: "显示数据来源标签", isOn: $settings.showSourceBadge)
                ToggleRow(title: "按设备类型分组", isOn: $settings.groupByKind)
                ToggleRow(title: "菜单栏显示百分比", isOn: $settings.menuBarShowsPercent)
            }
        }
    }

    // MARK: 桌面组件

    private var widgetSection: some View {
        SettingsSection(title: "桌面小组件", subtitle: "可拖动摆放在桌面上，位置与设置自动保存") {
            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(title: "在桌面显示小组件", isOn: $settings.widgetVisible)

                HStack(spacing: 10) {
                    Text("尺寸").font(.system(size: 11)).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.widgetSize) {
                        ForEach(WidgetSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 10) {
                    Text("层级").font(.system(size: 11)).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.widgetLevel) {
                        ForEach(WidgetLevel.allCases) { level in
                            Text(level.shortTitle).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 10) {
                    Text("背景").font(.system(size: 11)).frame(width: 80, alignment: .leading)
                    Picker("", selection: $settings.widgetBackground) {
                        ForEach(WidgetBackground.allCases) { bg in
                            Text(bg.title).tag(bg)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack(spacing: 10) {
                    Text("不透明度").font(.system(size: 11)).frame(width: 80, alignment: .leading)
                    Slider(value: $settings.widgetOpacity, in: 0.45...1.0)
                    Text(String(format: "%.0f%%", settings.widgetOpacity * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                ToggleRow(title: "组件使用独立显示模式", isOn: $settings.widgetOwnMode)
                if settings.widgetOwnMode {
                    Picker("", selection: $settings.widgetMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: 设备选择

    private var deviceSection: some View {
        SettingsSection(title: "设备选择", subtitle: "勾选需要显示的外设，面板与小组件同时生效") {
            VStack(spacing: 0) {
                if store.devices.isEmpty {
                    Text("暂未发现可读电量的外设")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                ForEach(store.devices) { device in
                    DeviceCheckboxRow(device: device, settings: settings)
                    if device.id != store.devices.last?.id {
                        Divider().opacity(0.08)
                    }
                }
                HStack(spacing: 10) {
                    Button("全部显示") { settings.showAll(store.devices) }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5))
                    Button("全部隐藏") { settings.hideAll(store.devices) }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5))
                    Spacer()
                    Text("\(store.devices.filter { settings.isVisible($0) }.count)/\(store.devices.count) 已选中")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: 数据源

    private var sourceSection: some View {
        SettingsSection(title: "数据源", subtitle: "四路并行采集，同名设备自动合并，取最可信来源") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    StatusDot(color: store.bleStatus.poweredOn ? Color.green : Color.orange, size: 6)
                    Text("蓝牙：\(store.bleStatus.detail)")
                        .font(.system(size: 11))
                    Spacer()
                    Button("重新扫描") { onRescan() }
                        .buttonStyle(.link)
                        .font(.system(size: 10.5))
                }

                SourceRow(symbol: "dot.radiowaves.left.and.right",
                          title: "BLE 电池服务",
                          detail: "0x180F / 0x2A19，第三方鼠标键盘的实时电量")
                SourceRow(symbol: "keyboard.badge.ellipsis",
                          title: "IOKit HID",
                          detail: "Apple 原厂外设的 BatteryPercent")
                SourceRow(symbol: "gamecontroller",
                          title: "GameController",
                          detail: "Xbox / DualSense / Switch Pro 手柄")
                SourceRow(symbol: "antenna.radiowaves.left.and.right",
                          title: "蓝牙系统信息",
                          detail: "AirPods 等设备的左 / 右 / 充电盒电量")

                Divider().opacity(0.1)

                HStack(spacing: 10) {
                    Button("搜索无线手柄") { onDiscoverGamepads() }
                        .font(.system(size: 10.5))
                    Spacer()
                    ToggleRow(title: "演示模式（假数据预览）", isOn: $settings.demoMode)
                        .frame(width: 220)
                }
            }
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        SettingsSection(title: "说明") {
            VStack(alignment: .leading, spacing: 5) {
                Text("• 首次运行会请求蓝牙权限，允许后才能读取外设电量。")
                Text("• 部分 2.4G 接收器外设（如部分罗技 / 雷蛇型号）不对外暴露电量接口，会显示为「--」。")
                Text("• 数据全部在本机读取，不联网、不上传。")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 设置组件

struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 11))
    }
}

struct ModePreviewTile: View {
    let mode: DisplayMode
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 11, weight: .medium))
                    Text(mode.title)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                Text(mode.detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(active ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1)
            )
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SourceRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

struct DeviceCheckboxRow: View {
    let device: PeripheralDevice
    @ObservedObject var settings: AppSettings

    private var visible: Bool { settings.isVisible(device) }

    var body: some View {
        Button {
            settings.toggleVisibility(device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: visible ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12.5))
                    .foregroundStyle(visible ? Color.accentColor : Color.secondary)
                DeviceIconBadge(kind: device.kind, size: 18, tint: Theme.color(for: device))
                Text(device.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text(device.source.shortLabel)
                    .font(.system(size: 8.5, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 4)
                Text(device.levelText)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.color(for: device))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
