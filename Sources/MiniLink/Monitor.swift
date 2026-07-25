import Foundation
import Network
import Darwin
import CoreWLAN
import Combine

/// 本机 Wi-Fi 网卡的 BSD 名（笔记本通常 en0；Mac mini / Studio 因有内建以太网通常是 en1）。
/// 用 CoreWLAN 动态获取，避免把 Wi-Fi 写死成某个固定的 enX。惰性求值、只算一次。
private let wifiBSDName: String? = CWWiFiClient.shared().interface()?.interfaceName

// MARK: - 底层探测工具

func runProcess(_ path: String, _ args: [String]) async -> (status: Int32, output: String) {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
            } catch {
                cont.resume(returning: (-1, ""))
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            cont.resume(returning: (proc.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
        }
    }
}

func pingHost(_ ip: String) async -> RouteStatus {
    let (status, out) = await runProcess("/sbin/ping", ["-c", "1", "-W", "1500", "-t", "2", ip])
    guard status == 0, let range = out.range(of: "time=") else {
        return RouteStatus(reachable: false, latencyMs: nil)
    }
    let numStr = out[range.upperBound...].prefix { "0123456789.".contains($0) }
    return RouteStatus(reachable: true, latencyMs: Double(numStr))
}

private final class ProbeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

func probePort(host: String, port: UInt16, timeoutMs: Int = 2000) async -> Bool {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
    return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let flag = ProbeFlag()
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if flag.take() { conn.cancel(); cont.resume(returning: true) }
            case .failed, .waiting:
                if flag.take() { conn.cancel(); cont.resume(returning: false) }
            default:
                break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
            if flag.take() { conn.cancel(); cont.resume(returning: false) }
        }
    }
}

/// 通过非交互 SSH 读取远端 macOS 的 CPU 与内存占用。
/// BatchMode 可确保没有配置密钥登录时立即失败，而不是弹密码提示或挂起后台刷新。
func remotePerformance(username: String, host: String) async -> RemotePerformance? {
    let target = "\(username)@\(host)"
    let command = """
    printf 'MEMTOTAL='; /usr/sbin/sysctl -n hw.memsize; \
    LC_ALL=C /usr/bin/top -l 1 -n 0 | /usr/bin/grep -E '^(CPU usage|PhysMem):'
    """
    var arguments = [
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "HostKeyAlias=\(Defaults.sshHostKeyAlias)",
        "-o", "ConnectTimeout=3",
        "-o", "ConnectionAttempts=1",
        "-o", "ServerAliveInterval=2",
        "-o", "ServerAliveCountMax=1",
    ]
    let miniLinkKey = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".ssh/minilink_ed25519")
    if FileManager.default.fileExists(atPath: miniLinkKey) {
        arguments += ["-i", miniLinkKey, "-o", "IdentitiesOnly=yes"]
    }
    arguments += [target, command]
    let result = await runProcess("/usr/bin/ssh", arguments)
    guard result.status == 0 else { return nil }
    return parseRemotePerformance(result.output)
}

private func remotePerformanceIfAvailable(
    _ available: Bool,
    username: String,
    host: String
) async -> RemotePerformance? {
    guard available else { return nil }
    return await remotePerformance(username: username, host: host)
}

/// 解析 macOS `top` 的稳定英文标签；独立成纯函数，便于用样本输出验证边界情况。
func parseRemotePerformance(_ output: String) -> RemotePerformance? {
    let lines = output.split(separator: "\n").map(String.init)
    guard
        let totalLine = lines.first(where: { $0.hasPrefix("MEMTOTAL=") }),
        let totalBytes = UInt64(totalLine.dropFirst("MEMTOTAL=".count)),
        totalBytes > 0,
        let cpuLine = lines.first(where: { $0.hasPrefix("CPU usage:") }),
        let memoryLine = lines.first(where: { $0.hasPrefix("PhysMem:") }),
        let idle = firstNumber(in: cpuLine, before: "% idle"),
        let usedBytes = memoryBytes(in: memoryLine, before: " used")
    else {
        return nil
    }

    return RemotePerformance(
        processorLoad: min(max(100 - idle, 0), 100),
        memoryUsedBytes: min(usedBytes, totalBytes),
        memoryTotalBytes: totalBytes
    )
}

private func firstNumber(in text: String, before marker: String) -> Double? {
    guard let markerRange = text.range(of: marker) else { return nil }
    let prefix = text[..<markerRange.lowerBound]
    let start = prefix.lastIndex(where: { !$0.isNumber && $0 != "." }).map {
        prefix.index(after: $0)
    } ?? prefix.startIndex
    return Double(prefix[start...])
}

private func memoryBytes(in text: String, before marker: String) -> UInt64? {
    guard let markerRange = text.range(of: marker) else { return nil }
    let prefix = text[..<markerRange.lowerBound]
    guard let unitIndex = prefix.lastIndex(where: { "KMGTP".contains($0) }) else { return nil }
    let numberPrefix = prefix[..<unitIndex]
    let numberStart = numberPrefix.lastIndex(where: { !$0.isNumber && $0 != "." }).map {
        numberPrefix.index(after: $0)
    } ?? numberPrefix.startIndex
    guard let value = Double(numberPrefix[numberStart...]) else { return nil }
    let exponent: Int
    switch prefix[unitIndex] {
    case "K": exponent = 1
    case "M": exponent = 2
    case "G": exponent = 3
    case "T": exponent = 4
    case "P": exponent = 5
    default: return nil
    }
    return UInt64(value * pow(1024, Double(exponent)))
}

func currentSMBMounts() async -> [MountedShare] {
    let (_, out) = await runProcess("/sbin/mount", [])
    return out.split(separator: "\n").compactMap { line -> MountedShare? in
        guard line.contains("smbfs") else { return nil }
        // 格式: //user@host/share on /Volumes/Share (smbfs, nodev, ...)
        guard let onRange = line.range(of: " on /"),
              let parenRange = line.range(of: " (", options: .backwards) else { return nil }
        let source = String(line[line.startIndex..<onRange.lowerBound])
        let mountStart = line.index(onRange.lowerBound, offsetBy: 4)
        guard mountStart < parenRange.lowerBound else { return nil }
        let mountPoint = String(line[mountStart..<parenRange.lowerBound])
        return MountedShare(source: source, mountPoint: mountPoint)
    }
}

/// 检测「对方连着我」的入站连接。一次 netstat 同时拿本机监听端口和建立态连接，
/// 只保留「对方连到本机某个监听端口」的连接——这样能区分「对方连我」与「我连对方」
/// （我主动外连时本机端口是临时端口，不在监听集合里，会被排除）。
/// 返回：对方 IP -> 该 IP 连到本机的监听端口列表（升序）。
func establishedInbound() async -> [String: [Int]] {
    let (_, out) = await runProcess("/usr/sbin/netstat", ["-an", "-p", "tcp"])
    var listen = Set<Int>()
    var estab: [(fip: String, lport: Int)] = []
    for line in out.split(separator: "\n") where line.hasPrefix("tcp") {
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        guard cols.count >= 4 else { continue }
        let local = String(cols[3]) // 本机 ip.port，如 192.168.1.50.22 或 *.22
        guard let d = local.lastIndex(of: "."),
              let lport = Int(local[local.index(after: d)...]) else { continue }
        if line.contains("LISTEN") {
            listen.insert(lport)
        } else if line.contains("ESTABLISHED"), cols.count >= 5 {
            let foreign = String(cols[4]) // 对方 ip.port
            guard let fd = foreign.lastIndex(of: ".") else { continue }
            estab.append((String(foreign[..<fd]), lport))
        }
    }
    var map: [String: Set<Int>] = [:]
    for e in estab where listen.contains(e.lport) {
        map[e.fip, default: []].insert(e.lport)
    }
    return map.mapValues { $0.sorted() }
}

// MARK: - mini 状态监测

@MainActor
final class StatusMonitor: ObservableObject {
    private let settings: AppSettings

    @Published var routeStatus: [UUID: RouteStatus] = [:]
    @Published var portStates: [UUID: PortState] = [:]
    @Published var mounts: [MountedShare] = []
    @Published var scanResults: [ScanResult]?
    @Published var scanning = false
    @Published var lastRefresh: Date?
    @Published var remotePerformanceStatus: RemotePerformanceStatus = .checking
    @Published var performanceRouteID: UUID?
    @Published var windowOpen = false {
        didSet {
            if windowOpen && !oldValue {
                Task { await self.refreshAll() }
            }
        }
    }

    private var loopTask: Task<Void, Never>?

    /// 截图模式下置 true：refreshAll 变为空操作，保持注入的演示数据不被真实探测覆盖
    var frozen = false

    init(settings: AppSettings, autostart: Bool = true) {
        self.settings = settings
        guard autostart else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                let interval = self.windowOpen
                    ? self.settings.refreshInterval
                    : max(self.settings.refreshInterval, 20)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    var reachableRoutes: [Route] {
        settings.routes.filter { routeStatus[$0.id]?.reachable == true }
    }

    var bestRoute: Route? {
        reachableRoutes.min {
            (routeStatus[$0.id]?.latencyMs ?? .infinity) < (routeStatus[$1.id]?.latencyMs ?? .infinity)
        }
    }

    var anyReachable: Bool { !reachableRoutes.isEmpty }

    func refreshAll() async {
        guard !frozen else { return }
        let routes = settings.routes
        // 与逐路由探测并发跑一次 netstat，拿到所有入站连接
        async let inboundMap = establishedInbound()
        var newStatus: [UUID: RouteStatus] = [:]
        await withTaskGroup(of: (UUID, RouteStatus).self) { group in
            for r in routes {
                group.addTask {
                    async let ping = pingHost(r.ip)
                    async let ssh = probePort(host: r.ip, port: 22) // SSH 是否通
                    var st = await ping
                    st.sshOpen = await ssh
                    return (r.id, st)
                }
            }
            for await (id, st) in group { newStatus[id] = st }
        }
        let inbound = await inboundMap
        for r in routes { newStatus[r.id]?.inboundPorts = inbound[r.ip] ?? [] }
        routeStatus = newStatus

        if let route = bestRoute {
            let entries = settings.ports
            var states: [UUID: PortState] = [:]
            let performanceRoute = routes
                .filter { newStatus[$0.id]?.reachable == true && newStatus[$0.id]?.sshOpen == true }
                .min {
                    (newStatus[$0.id]?.latencyMs ?? .infinity)
                        < (newStatus[$1.id]?.latencyMs ?? .infinity)
                }
            if case .available = remotePerformanceStatus {
                // 刷新时保留上次读数，避免进度条闪回“读取中”。
            } else {
                remotePerformanceStatus = .checking
            }
            performanceRouteID = performanceRoute?.id ?? route.id
            let canReadPerformance = performanceRoute != nil
            async let performance = remotePerformanceIfAvailable(
                canReadPerformance,
                username: settings.effectiveUsername,
                host: performanceRoute?.ip ?? route.ip
            )
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for e in entries {
                    group.addTask {
                        let open = await probePort(host: route.ip, port: UInt16(e.port))
                        return (e.id, open)
                    }
                }
                for await (id, open) in group { states[id] = open ? .open : .closed }
            }
            portStates = states
            if canReadPerformance {
                if let metrics = await performance {
                    remotePerformanceStatus = .available(metrics)
                } else {
                    remotePerformanceStatus = .unavailable(.sshAccessRequired)
                }
            } else {
                remotePerformanceStatus = .unavailable(.sshUnavailable)
            }
        } else {
            portStates = [:]
            performanceRouteID = nil
            remotePerformanceStatus = .unavailable(.hostUnreachable)
        }

        mounts = await currentSMBMounts()
        lastRefresh = Date()
    }

    func scanCommonPorts() async {
        guard let host = bestRoute?.ip else { return }
        scanning = true
        defer { scanning = false }
        var results: [ScanResult] = []
        await withTaskGroup(of: ScanResult.self) { group in
            for port in Defaults.commonScanPorts {
                group.addTask {
                    let open = await probePort(host: host, port: UInt16(port), timeoutMs: 1500)
                    return ScanResult(port: port, open: open)
                }
            }
            for await r in group { results.append(r) }
        }
        scanResults = results.sorted { $0.port < $1.port }
    }
}

// MARK: - 本机信息

@MainActor
final class LocalInfo: ObservableObject {
    @Published var username = NSUserName()
    @Published var fullName = NSFullUserName()
    @Published var hostName: String = ProcessInfo.processInfo.hostName

    @Published var ips: [LocalIP] = []
    @Published var listening: [ListeningPort] = []
    @Published var loading = false

    /// 截图模式下置 true：refresh 变为空操作
    var frozen = false

    func refresh() async {
        guard !frozen else { return }
        loading = true
        ips = Self.ipv4Interfaces()
        listening = await Self.listeningPorts()
        loading = false
    }

    nonisolated static func interfaceKind(iface: String, ip: String) -> String {
        if ip.hasPrefix("100.") && iface.hasPrefix("utun") { return "tailscale" }
        if ip.hasPrefix("169.254") { return "thunderbolt" }
        if let wifi = wifiBSDName, iface == wifi { return "wifi" }
        if iface.hasPrefix("bridge") { return "bridge" }
        return iface
    }

    nonisolated static func ipv4Interfaces() -> [LocalIP] {
        var result: [LocalIP] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard (ifa.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name != "lo0" else { continue }
            var sin = sockaddr_in()
            memcpy(&sin, sa, MemoryLayout<sockaddr_in>.size)
            let ip = String(cString: inet_ntoa(sin.sin_addr))
            result.append(LocalIP(iface: name, kind: interfaceKind(iface: name, ip: ip), ip: ip))
        }
        let priority: (LocalIP) -> Int = {
            switch $0.kind {
            case "wifi": return 0
            case "thunderbolt": return 1
            case "tailscale": return 2
            default: return 3
            }
        }
        return result.sorted { priority($0) < priority($1) }
    }

    nonisolated static func listeningPorts() async -> [ListeningPort] {
        async let netstatResult = runProcess("/usr/sbin/netstat", ["-an", "-p", "tcp"])
        async let lsofResult = runProcess("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "cn"])
        let (_, netstatOut) = await netstatResult
        let (_, lsofOut) = await lsofResult

        var procByPort: [Int: String] = [:]
        var currentCmd = ""
        for line in lsofOut.split(separator: "\n") {
            if line.hasPrefix("c") {
                currentCmd = String(line.dropFirst())
            } else if line.hasPrefix("n") {
                let name = line.dropFirst()
                if let idx = name.lastIndex(of: ":"), let port = Int(name[name.index(after: idx)...]) {
                    if procByPort[port] == nil { procByPort[port] = currentCmd }
                }
            }
        }

        var seen = Set<String>()
        var result: [ListeningPort] = []
        for line in netstatOut.split(separator: "\n")
        where line.hasPrefix("tcp") && line.contains("LISTEN") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4 else { continue }
            let local = String(cols[3]) // 例如 *.22 或 127.0.0.1.5000
            guard let dotIdx = local.lastIndex(of: "."),
                  let port = Int(local[local.index(after: dotIdx)...]) else { continue }
            var addr = String(local[..<dotIdx])
            if addr == "::1" { addr = "127.0.0.1" }
            let key = "\(addr):\(port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(ListeningPort(port: port, addr: addr, process: procByPort[port] ?? ""))
        }
        return result.sorted { $0.port < $1.port }
    }
}
