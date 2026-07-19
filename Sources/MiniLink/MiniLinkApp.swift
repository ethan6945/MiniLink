import SwiftUI

@main
struct MiniLinkApp: App {
    @State private var settings: AppSettings
    @State private var monitor: StatusMonitor
    @State private var localInfo = LocalInfo()

    init() {
        runCheckModeIfNeeded()
        runSnapshotModeIfNeeded()
        let s = AppSettings()
        _settings = State(initialValue: s)
        _monitor = State(initialValue: StatusMonitor(settings: s))
    }

    var body: some Scene {
        MenuBarExtra {
            MainView(settings: settings, monitor: monitor, localInfo: localInfo)
        } label: {
            Image(systemName: monitor.anyReachable
                ? "desktopcomputer"
                : "desktopcomputer.trianglebadge.exclamationmark")
        }
        .menuBarExtraStyle(.window)
    }
}

/// `MiniLink --check`：命令行自检模式，打印线路与端口状态后退出。
/// 用于构建后快速验证探测逻辑，不启动 UI。
@MainActor
private func runCheckModeIfNeeded() {
    guard CommandLine.arguments.contains("--check") else { return }
    let routes = AppSettings.loadJSON([Route].self, key: AppSettings.Keys.routes) ?? Defaults.routes
    let ports = AppSettings.loadJSON([PortEntry].self, key: AppSettings.Keys.ports) ?? Defaults.ports
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        print("== Routes ==")
        var best: (Route, Double)?
        for r in routes {
            let st = await pingHost(r.ip)
            let desc = st.reachable
                ? "reachable \(st.latencyMs.map { String(format: "%.1f ms", $0) } ?? "")"
                : "unreachable"
            print("\(r.name) \(r.ip): \(desc)")
            if st.reachable, let ms = st.latencyMs, best == nil || ms < best!.1 {
                best = (r, ms)
            }
        }
        if let (r, _) = best {
            print("== Ports (via \(r.name) \(r.ip)) ==")
            for p in ports {
                let open = await probePort(host: r.ip, port: UInt16(p.port))
                let label = p.label.isEmpty ? (Defaults.knownPortLabelsEn[p.port] ?? "") : p.label
                print("\(p.port) \(label): \(open ? "open" : "closed")")
            }
        } else {
            print("All routes unreachable, skipping port checks")
        }
        let mounts = await currentSMBMounts()
        print("== Mounted SMB ==")
        if mounts.isEmpty {
            print("(none)")
        } else {
            for m in mounts { print("\(m.volumeName) ← \(m.source)") }
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}
