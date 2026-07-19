import Foundation

struct Route: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var ip: String
    var symbol: String
}

struct PortEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var port: Int
    var label: String
}

struct RouteStatus: Equatable, Sendable {
    var reachable = false
    var latencyMs: Double?
}

enum PortState: Sendable {
    case open, closed
}

struct MountedShare: Identifiable, Equatable, Sendable {
    var id: String { mountPoint }
    var source: String
    var mountPoint: String
    var volumeName: String { (mountPoint as NSString).lastPathComponent }
}

struct ScanResult: Identifiable, Sendable {
    var id: Int { port }
    var port: Int
    var open: Bool
}

struct LocalIP: Identifiable, Sendable {
    var id: String { iface + ip }
    var iface: String
    var kind: String // "wifi" / "thunderbolt" / "tailscale" / "bridge" / 网卡名
    var ip: String
}

struct ListeningPort: Identifiable, Sendable {
    var id: String { "\(addr):\(port)/\(process)" }
    var port: Int
    var addr: String
    var process: String
}

enum Defaults {
    // 示例 IP，首次使用请在「设置」里改成自己的
    static let routes: [Route] = [
        Route(name: "LAN", ip: "192.168.1.100", symbol: "network"),
        Route(name: "Tailscale", ip: "100.101.102.103", symbol: "point.3.filled.connected.trianglepath.dotted"),
        Route(name: "Thunderbolt", ip: "169.254.1.1", symbol: "bolt.fill"),
    ]

    // 默认监测端口；label 留空时界面按语言查 knownPortLabels
    static let ports: [PortEntry] = [
        PortEntry(port: 22, label: ""),
        PortEntry(port: 445, label: ""),
        PortEntry(port: 5900, label: ""),
    ]

    static let knownPortLabelsEn: [Int: String] = [
        21: "FTP",
        22: "SSH / Remote Login",
        53: "DNS",
        80: "HTTP",
        88: "Kerberos",
        139: "NetBIOS",
        443: "HTTPS",
        445: "SMB file sharing",
        548: "AFP file sharing",
        631: "Printing (CUPS)",
        1234: "LM Studio",
        3000: "Dev server",
        3283: "Apple Remote Desktop",
        3306: "MySQL",
        5000: "Dev server / AirPlay",
        5432: "PostgreSQL",
        5900: "Screen Sharing (VNC)",
        6379: "Redis",
        7000: "AirPlay",
        8000: "Dev server",
        8080: "HTTP alt",
        8188: "ComfyUI",
        8443: "HTTPS alt",
        8888: "Jupyter",
        9000: "Dev server",
        11434: "Ollama",
    ]

    static let knownPortLabelsZh: [Int: String] = [
        21: "FTP",
        22: "SSH / 远程登录",
        53: "DNS",
        80: "HTTP",
        88: "Kerberos",
        139: "NetBIOS",
        443: "HTTPS",
        445: "SMB 文件共享",
        548: "AFP 文件共享",
        631: "打印 CUPS",
        1234: "LM Studio",
        3000: "开发服务",
        3283: "远程管理 ARD",
        3306: "MySQL",
        5000: "开发服务 / AirPlay",
        5432: "PostgreSQL",
        5900: "屏幕共享 VNC",
        6379: "Redis",
        7000: "AirPlay",
        8000: "开发服务",
        8080: "HTTP 备用",
        8188: "ComfyUI",
        8443: "HTTPS 备用",
        8888: "Jupyter",
        9000: "开发服务",
        11434: "Ollama",
    ]

    static var commonScanPorts: [Int] { knownPortLabelsEn.keys.sorted() }
}

@MainActor
@Observable
final class AppSettings {
    nonisolated enum Keys {
        static let username = "sshUsername"
        static let interval = "refreshInterval"
        static let routes = "routes"
        static let ports = "monitoredPorts"
        static let language = "language"
    }

    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: Keys.username) }
    }
    var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Keys.interval) }
    }
    var routes: [Route] {
        didSet { Self.saveJSON(routes, key: Keys.routes) }
    }
    var ports: [PortEntry] {
        didSet { Self.saveJSON(ports, key: Keys.ports) }
    }
    var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    init() {
        let d = UserDefaults.standard
        username = d.string(forKey: Keys.username) ?? ""
        let iv = d.double(forKey: Keys.interval)
        refreshInterval = iv >= 2 ? iv : 5
        routes = Self.loadJSON([Route].self, key: Keys.routes) ?? Defaults.routes
        ports = Self.loadJSON([PortEntry].self, key: Keys.ports) ?? Defaults.ports
        language = d.string(forKey: Keys.language).flatMap(Language.init) ?? .system
    }

    // MARK: 国际化

    var resolvedLanguage: Language {
        if language != .system { return language }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .zh : .en
    }

    func t(_ key: String) -> String {
        let table = resolvedLanguage == .zh ? L10n.zh : L10n.en
        return table[key] ?? L10n.en[key] ?? key
    }

    func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    func portLabel(_ port: Int) -> String? {
        (resolvedLanguage == .zh ? Defaults.knownPortLabelsZh : Defaults.knownPortLabelsEn)[port]
    }

    // MARK: 持久化

    func resetDefaults() {
        routes = Defaults.routes
        ports = Defaults.ports
        refreshInterval = 5
    }

    nonisolated static func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    nonisolated static func loadJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
