import SwiftUI
import AppKit

/// `MiniLink --snapshot <输出目录>`：用演示数据离屏渲染四个页面的 PNG，
/// 供 README 使用。请用未打包的二进制运行（.build/release/MiniLink），
/// 避免演示数据写进正式 App 的 UserDefaults。
@MainActor
func runSnapshotModeIfNeeded() {
    guard let idx = CommandLine.arguments.firstIndex(of: "--snapshot"),
          CommandLine.arguments.count > idx + 1 else { return }
    let outDir = CommandLine.arguments[idx + 1]
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: .aqua)

    let settings = AppSettings()
    settings.username = "alex"
    let lan = Route(name: "LAN", ip: "192.168.0.50", symbol: "network")
    let ts = Route(name: "Tailscale", ip: "100.80.90.100", symbol: "point.3.filled.connected.trianglepath.dotted")
    let tb = Route(name: "Thunderbolt", ip: "169.254.100.2", symbol: "bolt.fill")
    settings.routes = [lan, ts, tb]
    let p22 = PortEntry(port: 22, label: "")
    let p445 = PortEntry(port: 445, label: "")
    let p5900 = PortEntry(port: 5900, label: "")
    let p11434 = PortEntry(port: 11434, label: "")
    settings.ports = [p22, p445, p5900, p11434]

    let monitor = StatusMonitor(settings: settings, autostart: false)
    monitor.frozen = true
    monitor.routeStatus = [
        lan.id: RouteStatus(reachable: true, latencyMs: 0.6, sshOpen: true, inboundPorts: [22]),
        ts.id: RouteStatus(reachable: true, latencyMs: 14.2, sshOpen: true),
        tb.id: RouteStatus(reachable: true, latencyMs: 0.3, sshOpen: false),
    ]
    monitor.portStates = [p22.id: .open, p445.id: .open, p5900.id: .closed, p11434.id: .open]
    monitor.mounts = [MountedShare(source: "//alex@192.168.0.50/Media", mountPoint: "/Volumes/Media")]
    monitor.lastRefresh = Date()
    monitor.performanceRouteID = lan.id
    monitor.remotePerformanceStatus = .available(RemotePerformance(
        processorLoad: 37,
        memoryUsedBytes: 10_737_418_240,
        memoryTotalBytes: 17_179_869_184
    ))
    monitor.scanResults = Defaults.commonScanPorts.map {
        ScanResult(port: $0, open: [22, 80, 445, 3000, 11434].contains($0))
    }

    let localInfo = LocalInfo()
    localInfo.frozen = true
    localInfo.username = "alex"
    localInfo.fullName = "Alex Doe"
    localInfo.hostName = "Alexs-MacBook-Air.local"
    localInfo.ips = [
        LocalIP(iface: "en0", kind: "wifi", ip: "192.168.0.42"),
        LocalIP(iface: "bridge0", kind: "thunderbolt", ip: "169.254.100.10"),
        LocalIP(iface: "utun3", kind: "tailscale", ip: "100.80.90.101"),
    ]
    localInfo.listening = [
        ListeningPort(port: 22, addr: "*", process: ""),
        ListeningPort(port: 445, addr: "*", process: ""),
        ListeningPort(port: 5000, addr: "*", process: "ControlCenter"),
        ListeningPort(port: 8080, addr: "127.0.0.1", process: "node"),
        ListeningPort(port: 11434, addr: "*", process: "ollama"),
    ]

    let shots: [(String, MainView.Tab, Language)] = [
        ("screenshot-status", .status, .en),
        ("screenshot-ports", .ports, .en),
        ("screenshot-local", .local, .en),
        ("screenshot-settings-zh", .settings, .zh),
    ]
    for (name, tab, lang) in shots {
        settings.language = lang
        // ImageRenderer 渲染不了 AppKit 实现的控件（Picker/ScrollView/Button），
        // 所以走真实 AppKit 管线：离屏窗口 + cacheDisplay
        let view = MainView(settings: settings, monitor: monitor, localInfo: localInfo, initialTab: tab)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // 跑一小段 runloop 让 SwiftUI 完成布局（监测类已 frozen，不会覆盖演示数据）
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("FAILED to render \(name)")
            continue
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
            print("saved \(name).png \(rep.pixelsWide)x\(rep.pixelsHigh)")
        }
        window.contentView = nil
    }
    exit(0)
}
