import Foundation

// 命令行自检：验证四路数据源在本机能否拿到真实电量
let store = BatteryStore()
store.start()

var rounds = 0
let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
    rounds += 1
    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("=== [\(stamp)] 蓝牙: \(store.bleStatus.detail) | \(store.sourceSummary)")
    if store.devices.isEmpty {
        print("    (暂无设备)")
    }
    for device in store.devices {
        let level = device.level.map { "\($0)%" } ?? "--"
        let comps = device.components.map { "\($0.label)=\($0.level)%" }.joined(separator: " ")
        let conn = device.isConnected ? "已连接" : "离线"
        print("    \(device.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(device.kind.title)  \(level.padding(toLength: 4, withPad: " ", startingAt: 0))  \(conn)  [\(device.source.shortLabel)]  \(comps)")
    }
    if rounds >= 3 { exit(0) }
}
RunLoop.main.run()
_ = timer
