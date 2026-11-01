// 生成 AppIcon.icns 的图标渲染器
// 用法：swiftc -O tools/make-icon.swift -o .build/make-icon && .build/make-icon
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let scale = size / canvas
    ctx.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // 1. 底盘渐变
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    let backdrop = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0x2F3A57), color(0x0B141F)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(backdrop,
                           start: CGPoint(x: 170, y: 900),
                           end: CGPoint(x: 880, y: 130),
                           options: [])

    // 2. 顶部柔光（线性，避免出现光斑）
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0xBFEFE2, alpha: 0.13), color(0xBFEFE2, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(glow,
                           start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 470),
                           options: [])

    // 3. 内侧描边，浅色背景下更有轮廓
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.10))
    ctx.setLineWidth(3)
    ctx.addPath(bodyPath)
    ctx.strokePath()
    ctx.restoreGState()

    let simplified = size <= 48

    // 4. 量规环：底部开口、经过顶部
    if !simplified {
        let center = CGPoint(x: 512, y: 512)
        let radius: CGFloat = 330
        ctx.setLineCap(.round)

        ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.10))
        ctx.setLineWidth(34)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addArc(center: center, radius: radius,
                   startAngle: -.pi * 0.25, endAngle: .pi * 1.25, clockwise: false)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let ringGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [color(0x6CF3C4), color(0x14C08D)] as CFArray,
                                      locations: [0, 1])!
        ctx.drawLinearGradient(ringGradient,
                               start: CGPoint(x: 220, y: 800),
                               end: CGPoint(x: 800, y: 240),
                               options: [])
        ctx.restoreGState()
    }

    // 5. 电池外壳
    let shell = CGRect(x: 316, y: 410, width: 384, height: 204)
    let nub = CGRect(x: 706, y: 470, width: 40, height: 84)
    let shellPath = CGPath(roundedRect: shell, cornerWidth: 54, cornerHeight: 54, transform: nil)
    let nubPath = CGPath(roundedRect: nub, cornerWidth: 20, cornerHeight: 20, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 48,
                  color: color(0x000000, alpha: 0.45))
    ctx.setFillColor(color(0xFFFFFF, alpha: 0.95))
    ctx.addPath(nubPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40,
                  color: color(0x000000, alpha: 0.38))
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.96))
    ctx.setLineWidth(30)
    ctx.addPath(shellPath)
    ctx.strokePath()
    ctx.restoreGState()

    // 6. 电量填充（约 72%）
    let inset: CGFloat = 30
    let innerHeight = shell.height - inset * 2
    let ratio: CGFloat = 0.72
    let fillRect = CGRect(x: shell.minX + inset,
                          y: shell.minY + inset,
                          width: (shell.width - inset * 2) * ratio,
                          height: innerHeight)
    let fillPath = CGPath(roundedRect: fillRect, cornerWidth: 30, cornerHeight: 30, transform: nil)

    ctx.saveGState()
    ctx.addPath(fillPath)
    ctx.clip()
    let fillGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color(0x7BF3C9), color(0x0FAE7A)] as CFArray,
                                  locations: [0, 1])!
    ctx.drawLinearGradient(fillGradient,
                           start: CGPoint(x: fillRect.minX, y: fillRect.maxY),
                           end: CGPoint(x: fillRect.maxX, y: fillRect.minY),
                           options: [])
    ctx.restoreGState()

    // 7. 填充上的高光条
    if !simplified {
        let shine = CGRect(x: fillRect.minX + 10, y: fillRect.maxY - 42,
                           width: max(0, fillRect.width - 26), height: 16)
        ctx.setFillColor(color(0xFFFFFF, alpha: 0.30))
        ctx.addPath(CGPath(roundedRect: shine, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
    }
}

func renderPNG(size: Int) -> Data? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, size: CGFloat(size))
    guard let image = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in variants {
    guard let data = renderPNG(size: size) else {
        FileHandle.standardError.write("render failed: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(name))
    print("rendered \(name) (\(size)px)")
}

// 输出一张 1024 预览，方便人工检查
try renderPNG(size: 1024)?.write(to: root.appendingPathComponent(".build/AppIcon-preview.png"))

let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus == 0 {
    print("wrote \(icnsURL.path)")
} else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
