import AppKit
import SwiftUI

/// 预设视觉风格：决定面板 / 小组件的背景与明暗基调
enum VisualStyle: String, Codable, CaseIterable, Identifiable {
    case aurora
    case midnight
    case graphite
    case cream
    case mint
    case sunset
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "极光"
        case .midnight: return "午夜"
        case .graphite: return "石墨"
        case .cream: return "奶油"
        case .mint: return "薄荷"
        case .sunset: return "落日"
        case .custom: return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .aurora: return "深空蓝绿"
        case .midnight: return "纯黑冷调"
        case .graphite: return "中性灰"
        case .cream: return "暖白米色"
        case .mint: return "浅青薄荷"
        case .sunset: return "深棕暖橙"
        case .custom: return "用自己的背景图"
        }
    }

    /// 背景偏亮时需要强制浅色外观（黑字）
    var isLight: Bool {
        switch self {
        case .cream, .mint: return true
        default: return false
        }
    }

    var gradient: [Color] {
        switch self {
        case .aurora: return [Self.rgb(0x1E2A48), Self.rgb(0x0A101C)]
        case .midnight: return [Self.rgb(0x0A0A0E), Self.rgb(0x17171E)]
        case .graphite: return [Self.rgb(0x1A1A1F), Self.rgb(0x2D2D34)]
        case .cream: return [Self.rgb(0xFDF8EF), Self.rgb(0xEFE1CD)]
        case .mint: return [Self.rgb(0xF0FBF6), Self.rgb(0xD0ECE1)]
        case .sunset: return [Self.rgb(0x34170F), Self.rgb(0x1B0C08)]
        case .custom: return [Self.rgb(0x12141C), Self.rgb(0x1C2029)]
        }
    }

    static func rgb(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// 用户上传的背景图：拷到 App 支持目录、缓存、并按平均亮度决定文字明暗
enum CustomBackground {

    private static var cachedImage: NSImage?
    private static var cachedStamp: Date?

    static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support
            .appendingPathComponent("PeripheralBattery", isDirectory: true)
            .appendingPathComponent("custom-background.img")
    }

    static func current() -> NSImage? {
        let path = url.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let stamp = attributes[.modificationDate] as? Date else {
            cachedImage = nil
            cachedStamp = nil
            return nil
        }
        if let cachedImage, let cachedStamp, cachedStamp == stamp {
            return cachedImage
        }
        let image = NSImage(contentsOfFile: path)
        cachedImage = image
        cachedStamp = stamp
        return image
    }

    static func save(from source: URL) -> Bool {
        do {
            let data = try Data(contentsOf: source)
            guard !data.isEmpty, data.count <= 30_000_000 else { return false }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            invalidate()
            return true
        } catch {
            return false
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
        invalidate()
    }

    static func invalidate() {
        cachedImage = nil
        cachedStamp = nil
    }

    /// true 表示背景偏暗、应该用浅色文字
    static func prefersLightText(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return true
        }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return true }
        let pixels = data.bindMemory(to: UInt8.self, capacity: 4)
        let luminance = (0.299 * Double(pixels[0]) + 0.587 * Double(pixels[1]) + 0.114 * Double(pixels[2])) / 255.0
        return luminance < 0.55
    }
}
