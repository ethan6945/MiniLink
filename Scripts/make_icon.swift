// 生成 App 图标：1024x1024 PNG（squircle 渐变底 + MacBook、mini、连接线、状态灯）
// 用法: swift Scripts/make_icon.swift <输出.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let darkBlue = NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.42, alpha: 1)
let innerDark = NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.46, alpha: 1)

// 背景 squircle + 对角渐变
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.36, green: 0.64, blue: 0.99, alpha: 1),
    ending: darkBlue
)!
gradient.draw(in: bg, angle: -70)

// MacBook（左下）：屏幕外框 + 深色屏面 + 底座
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 200, y: 330, width: 330, height: 230), xRadius: 26, yRadius: 26).fill()
innerDark.setFill()
NSBezierPath(roundedRect: NSRect(x: 224, y: 354, width: 282, height: 182), xRadius: 14, yRadius: 14).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 168, y: 292, width: 394, height: 32), xRadius: 16, yRadius: 16).fill()

// Mac mini（右上）：扁平圆角方块 + 电源灯
NSBezierPath(roundedRect: NSRect(x: 600, y: 615, width: 250, height: 100), xRadius: 30, yRadius: 30).fill()
innerDark.setFill()
NSBezierPath(ovalIn: NSRect(x: 804, y: 655, width: 20, height: 20)).fill()

// 连接曲线
let link = NSBezierPath()
link.move(to: NSPoint(x: 545, y: 400))
link.curve(
    to: NSPoint(x: 700, y: 615),
    controlPoint1: NSPoint(x: 670, y: 400),
    controlPoint2: NSPoint(x: 700, y: 490)
)
NSColor.white.setStroke()
link.lineWidth = 30
link.lineCapStyle = .round
link.stroke()

// 曲线上的绿色状态灯（白圈包边）
let dot = NSPoint(x: 678, y: 510)
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: dot.x - 52, y: dot.y - 52, width: 104, height: 104)).fill()
NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.36, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: dot.x - 36, y: dot.y - 36, width: 72, height: 72)).fill()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)")
