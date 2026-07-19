import Foundation
import Network
import Darwin

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

// MARK: - mini 状态监测

@MainActor
@Observable
final class StatusMonitor {
    private let settings: AppSettings

    var routeStatus: [UUID: RouteStatus] = [:]
    var portStates: [UUID: PortState] = [:]
    var mounts: [MountedShare] = []
    var scanResults: [ScanResult]?
    var scanning = false
    var lastRefresh: Date?
    var windowOpen = false {
        didSet {
            if windowOpen && !oldValue {
                Task { await self.refreshAll() }
            }
        }
    }

    private var loopTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
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
        let routes = settings.routes
        var newStatus: [UUID: RouteStatus] = [:]
        await withTaskGroup(of: (UUID, RouteStatus).self) { group in
            for r in routes {
                group.addTask {
                    let st = await pingHost(r.ip)
                    return (r.id, st)
                }
            }
            for await (id, st) in group { newStatus[id] = st }
        }
        routeStatus = newStatus

        if let host = bestRoute?.ip {
            let entries = settings.ports
            var states: [UUID: PortState] = [:]
            await withTaskGroup(of: (UUID, Bool).self) { group in
                for e in entries {
                    group.addTask {
                        let open = await probePort(host: host, port: UInt16(e.port))
                        return (e.id, open)
                    }
                }
                for await (id, open) in group { states[id] = open ? .open : .closed }
            }
            portStates = states
        } else {
            portStates = [:]
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
@Observable
final class LocalInfo {
    let username = NSUserName()
    let fullName = NSFullUserName()
    var hostName: String { ProcessInfo.processInfo.hostName }

    var ips: [LocalIP] = []
    var listening: [ListeningPort] = []
    var loading = false

    func refresh() async {
        loading = true
        ips = Self.ipv4Interfaces()
        listening = await Self.listeningPorts()
        loading = false
    }

    nonisolated static func interfaceKind(iface: String, ip: String) -> String {
        if ip.hasPrefix("100.") && iface.hasPrefix("utun") { return "tailscale" }
        if ip.hasPrefix("169.254") { return "thunderbolt" }
        if iface == "en0" { return "wifi" }
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
