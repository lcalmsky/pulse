// 앱 아이콘(assets/AppIcon.icns)을 다시 만든다. 사용법: swift scripts/make-icon.swift
// 링·파형 비율과 꼭짓점은 Popover/PopoverHeader.swift 의 PulseLogo, PulseCore/PulseGlyph.swift 와 맞춘다.
import AppKit

let wave: [CGPoint] = [
    CGPoint(x: -0.6, y: 0),
    CGPoint(x: -0.26, y: 0),
    CGPoint(x: -0.1, y: 0.43),
    CGPoint(x: 0.1, y: -0.43),
    CGPoint(x: 0.26, y: 0),
    CGPoint(x: 0.6, y: 0),
]

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let attention = rgb(0xff, 0x9f, 0x0a)
let working = rgb(0x0a, 0x84, 0xff)
let done = rgb(0x30, 0xd1, 0x58)
let purple = rgb(0xbf, 0x5a, 0xf2)

func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(rgb(0x1c, 0x1c, 0x22))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: space, colors: [rgb(0x30, 0x30, 0x3c), rgb(0x16, 0x16, 0x1c)] as CFArray, locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    let side: CGFloat = 560
    let center = CGPoint(x: 512, y: 512)
    let line = side * 0.13
    let radius = (side - line) / 2

    context.saveGState()
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.addPath(ring.copy(strokingWithWidth: line, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
    context.clip()
    // CoreGraphics 에는 원뿔 그라데이션이 없어 SwiftUI AngularGradient 를 부채꼴 조각으로 흉내 낸다.
    let steps = 360
    for step in 0..<steps {
        let t = CGFloat(step) / CGFloat(steps)
        let mix = t < 0.5 ? t * 2 : (1 - t) * 2
        let a = working.components!, b = purple.components!
        let color = CGColor(
            srgbRed: a[0] + (b[0] - a[0]) * mix, green: a[1] + (b[1] - a[1]) * mix,
            blue: a[2] + (b[2] - a[2]) * mix, alpha: 1
        )
        let start = -t * 2 * .pi
        let end = start - 2 * .pi / CGFloat(steps) * 1.5
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius + line, startAngle: start, endAngle: end, clockwise: true)
        wedge.closeSubpath()
        context.addPath(wedge)
        context.setFillColor(color)
        context.fillPath()
    }
    context.restoreGState()

    let wavePath = CGMutablePath()
    for (index, point) in wave.enumerated() {
        let target = CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
        if index == 0 { wavePath.move(to: target) } else { wavePath.addLine(to: target) }
    }
    context.saveGState()
    context.addPath(wavePath.copy(strokingWithWidth: side * 0.085, lineCap: .round, lineJoin: .round, miterLimit: 10))
    context.clip()
    let waveGradient = CGGradient(
        colorsSpace: space, colors: [attention, working, done] as CFArray, locations: [0.15, 0.5, 0.85]
    )!
    context.drawLinearGradient(
        waveGradient,
        start: CGPoint(x: center.x + wave.first!.x * radius, y: center.y),
        end: CGPoint(x: center.x + wave.last!.x * radius, y: center.y),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let assets = root.appendingPathComponent("assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let output = assets.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }
try? FileManager.default.removeItem(at: iconset)
print(output.path)
