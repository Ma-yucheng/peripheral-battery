import SwiftUI

final class WelcomeModel: ObservableObject {
    @Published var backgroundEnabled: Bool

    init(backgroundEnabled: Bool) {
        self.backgroundEnabled = backgroundEnabled
    }
}

/// 首次安装并打开时的一次性说明页
struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    let canRegisterLoginItem: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用外设电量")
                        .font(.system(size: 18, weight: .bold))
                    Text("一个常驻后台、只在你本机运行的电量监控小工具")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 11) {
                WelcomeRow(symbol: "menubar.rectangle",
                           title: "菜单栏常驻",
                           detail: "没有 Dock 图标。关掉窗口不会退出，随时点菜单栏图标打开面板。")
                WelcomeRow(symbol: "bolt.horizontal.circle",
                           title: "后台持续监控",
                           detail: "已在系统层面对本 App 关闭「自动终止」「突然终止」和 App Nap，刷新不会被打断。")
                WelcomeRow(symbol: "power",
                           title: "登录时自动启动",
                           detail: "通过登录项（LaunchAgent）在开机登录后自动回到菜单栏，不用每次手动打开。")
                WelcomeRow(symbol: "xmark.circle",
                           title: "想退出的时候",
                           detail: "点菜单栏图标右键 →「退出外设电量」，或在设置里关掉「登录时自动启动」。")
                WelcomeRow(symbol: "lock.shield",
                           title: "完全本地",
                           detail: "电量数据只留在本机，不联网、不上传。")
            }

            Toggle("登录时自动启动，并常驻后台", isOn: $model.backgroundEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 11.5))

            if !canRegisterLoginItem {
                Text("提示：当前 App 不在「应用程序」目录中，登录项不会注册；把 App 拖进 /Applications 后重新打开即可生效。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("这项设置随时可以在「设置 → 后台与启动」里改")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button("开始使用", action: onStart)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .frame(width: 500)
    }
}

struct WelcomeRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
