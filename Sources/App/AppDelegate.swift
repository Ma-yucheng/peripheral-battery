import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let settings = AppSettings.shared
    private let store = BatteryStore()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var widgetPanel: NSPanel?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastWidgetHeight: CGFloat = 0
    private var widgetPlaced = false
    private var lastLoggedTitle: String = ""
    private let debugLog = ProcessInfo.processInfo.environment["PB_LOG"] != nil

    private func log(_ message: @autoclosure () -> String) {
        guard debugLog else { return }
        print("[PB] " + message())
        fflush(stdout)
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        log("启动 demo=\(settings.demoMode) widgetVisible=\(settings.widgetVisible) mode=\(settings.displayMode.rawValue)")
        store.start()
        setupStatusItem()
        setupPopover()
        bindObservers()
        updateStatusItem()
        applyWidgetSettings()
        startRefreshTimer()

        // 调试 / 截图用：--show-panel 启动后自动打开面板
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.openSettings()
            }
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        store.stop()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.make(level: nil)
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "外设电量"
        }
        statusItem = item
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let visible = store.devices.filter { settings.isVisible($0) }
        let connected = visible.filter { $0.isConnected }
        let pool = connected.isEmpty ? visible : connected
        let lowest = pool.compactMap(\.criticalLevel).min()
        button.image = MenuBarIcon.make(level: lowest)
        button.title = settings.menuBarShowsPercent ? (lowest.map { " \($0)%" } ?? " --") : ""
        if let lowest, lowest <= settings.lowThreshold {
            button.contentTintColor = NSColor.systemRed
        } else {
            button.contentTintColor = nil
        }
        if lastLoggedTitle != button.title {
            lastLoggedTitle = button.title
            log("状态栏 -> '\(button.title)' 设备数=\(visible.count) 在线=\(connected.count)")
        }
        let preview = pool.prefix(3)
            .map { "\($0.name) \($0.levelText)" }
            .joined(separator: "，")
        button.toolTip = preview.isEmpty ? "外设电量：未发现设备" : "外设电量：" + preview
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let openPanel = NSMenuItem(title: "打开面板", action: #selector(menuTogglePopover), keyEquivalent: "")
        openPanel.target = self
        menu.addItem(openPanel)

        let widgetItem = NSMenuItem(title: "桌面小组件", action: #selector(menuToggleWidget), keyEquivalent: "w")
        widgetItem.target = self
        widgetItem.state = settings.widgetVisible ? .on : .off
        menu.addItem(widgetItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let rescanItem = NSMenuItem(title: "重新扫描", action: #selector(menuRescan), keyEquivalent: "r")
        rescanItem.target = self
        menu.addItem(rescanItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出外设电量", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePopover() { togglePopover() }
    @objc private func menuToggleWidget() { settings.widgetVisible.toggle() }
    @objc private func menuOpenSettings() { openSettings() }
    @objc private func menuRescan() { store.rescan() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - 弹出面板

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: Layout.panelWidth,
                                     height: Layout.panelHeight(mode: settings.displayMode,
                                                                devices: store.devices,
                                                                showSparkline: settings.showSparkline,
                                                                selectorExpanded: settings.selectorExpanded))

        let root = DashboardView(
            store: store,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.popover?.performClose(nil)
                self?.openSettings()
            },
            onToggleWidget: { [weak self] in
                self?.settings.widgetVisible.toggle()
            },
            onRescan: { [weak self] in
                self?.store.rescan()
            }
        )
        popover.contentViewController = NSHostingController(rootView: root)
        self.popover = popover
    }

    private func syncPopoverSize() {
        guard let popover else { return }
        let visible = store.devices.filter { settings.isVisible($0) }
        let height = Layout.panelHeight(mode: settings.displayMode,
                                        devices: visible,
                                        showSparkline: settings.showSparkline,
                                        selectorExpanded: settings.selectorExpanded)
        if abs(popover.contentSize.height - height) > 0.5 {
            popover.contentSize = NSSize(width: Layout.panelWidth, height: height)
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - 设置窗口

    private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "外设电量 · 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.titlebarAppearsTransparent = false

        let root = SettingsView(
            store: store,
            settings: settings,
            onRescan: { [weak self] in self?.store.rescan() },
            onDiscoverGamepads: { [weak self] in self?.store.discoverGamepads() }
        )
        window.contentViewController = NSHostingController(rootView: root)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - 桌面小组件

    private var lastDemoMode = AppSettings.shared.demoMode

    private func applyWidgetSettings() {
        if settings.demoMode != lastDemoMode {
            lastDemoMode = settings.demoMode
            store.rescan()
        }
        if settings.widgetVisible {
            if widgetPanel == nil {
                createWidgetPanel()
            }
            applyWidgetAppearance()
            layoutWidget()
            widgetPanel?.orderFrontRegardless()
        } else {
            widgetPanel?.orderOut(nil)
        }
    }

    private func createWidgetPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 400, width: settings.widgetSize.width, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.delegate = self

        let root = WidgetView(
            store: store,
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        widgetPanel = panel
        log("创建小组件窗口 size=\(settings.widgetSize.width)x220")
    }

    private func applyWidgetAppearance() {
        guard let panel = widgetPanel else { return }
        // 注意：isFloatingPanel 会改写窗口层级，必须先设它再设 level
        panel.isFloatingPanel = (settings.widgetLevel == .floating)
        switch settings.widgetLevel {
        case .desktop:
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        case .floating:
            panel.level = .floating
        }
        panel.ignoresMouseEvents = false
        log("窗口层级 -> \(panel.level.rawValue) (\(settings.widgetLevel.rawValue)) 可见=\(panel.isVisible)")
    }

    private func layoutWidget() {
        guard let panel = widgetPanel, let content = panel.contentView else { return }
        let width = settings.widgetSize.width + WidgetView.shadowMargin * 2

        content.setFrameSize(NSSize(width: width, height: max(content.frame.height, 120)))
        content.layoutSubtreeIfNeeded()
        let height = max(96, content.fittingSize.height)

        if widgetPlaced && abs(height - lastWidgetHeight) < 0.5 && panel.frame.width == width {
            return
        }
        let previousTopRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        lastWidgetHeight = height

        var frame = panel.frame
        if widgetPlaced {
            // 靠近屏幕下方时固定底边向上生长，否则固定顶边向下生长
            let screenMidY = (panel.screen ?? NSScreen.main)?.visibleFrame.midY ?? 540
            let growUpward = panel.frame.midY < screenMidY
            frame.size = NSSize(width: width, height: height)
            frame.origin = NSPoint(x: previousTopRight.x - width,
                                   y: growUpward ? panel.frame.minY : previousTopRight.y - height)
        } else {
            let saved = settings.loadWidgetPosition() ?? defaultWidgetOrigin()
            frame = NSRect(x: saved.x, y: saved.y, width: width, height: height)
        }

        frame = clampedWidgetRect(frame)
        panel.setFrame(frame, display: true)
        widgetPlaced = true
        log("小组件布局 \(Int(width))x\(Int(height)) origin=\(Int(frame.origin.x)),\(Int(frame.origin.y)) level=\(panel.level.rawValue)")
    }

    private func defaultWidgetOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 80, y: 400) }
        let visible = screen.visibleFrame
        // 默认放在右下角：右上角是菜单栏面板展开的位置
        let canvasWidth = settings.widgetSize.width + WidgetView.shadowMargin * 2
        return NSPoint(x: visible.maxX - canvasWidth - 12,
                       y: visible.minY + 12)
    }

    /// 把窗口矩形限制在当前屏幕可见区域内
    private func clampedWidgetRect(_ rect: NSRect) -> NSRect {
        guard let screen = widgetPanel?.screen ?? NSScreen.main else { return rect }
        let visible = screen.visibleFrame
        var frame = rect
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        return frame
    }

    private func clampWidgetToScreen() {
        guard let panel = widgetPanel else { return }
        let frame = clampedWidgetRect(panel.frame)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: 记住组件位置

    func windowDidMove(_ notification: Notification) {
        guard let panel = widgetPanel, notification.object as? NSPanel === panel else { return }
        // 只记住完整落在屏幕内的位置，避免把越界坐标写进设置
        guard let screen = panel.screen ?? NSScreen.main else { return }
        if screen.visibleFrame.contains(panel.frame) {
            settings.saveWidgetPosition(panel.frame.origin)
        }
    }

    // MARK: - 观察变更

    private func bindObservers() {
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyWidgetSettings()
                    self?.updateStatusItem()
                    self?.syncPopoverSize()
                }
            }
            .store(in: &cancellables)

        store.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.syncPopoverSize()
                self?.layoutWidget()
            }
            .store(in: &cancellables)

        store.$bleStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}

// MARK: - 菜单栏图标

enum MenuBarIcon {

    static func make(level: Int?) -> NSImage {
        let size = NSSize(width: 24, height: 12)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 0.6, y: 1.6, width: 17.2, height: 8.8)
            let path = NSBezierPath(roundedRect: body, xRadius: 2.4, yRadius: 2.4)
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()

            let cap = NSRect(x: body.maxX + 0.9, y: 4.4, width: 1.9, height: 3.2)
            NSBezierPath(roundedRect: cap, xRadius: 0.9, yRadius: 0.9).fill()

            if let level {
                let ratio = CGFloat(max(0, min(100, level))) / 100
                let innerWidth = (body.width - 3.0) * ratio
                if innerWidth > 0.4 {
                    let fill = NSRect(x: body.minX + 1.5,
                                      y: body.minY + 1.5,
                                      width: innerWidth,
                                      height: body.height - 3.0)
                    NSBezierPath(roundedRect: fill, xRadius: 1.0, yRadius: 1.0).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
