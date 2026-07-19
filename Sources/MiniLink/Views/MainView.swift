import SwiftUI
import ServiceManagement

struct MainView: View {
    @Bindable var settings: AppSettings
    var monitor: StatusMonitor
    var localInfo: LocalInfo

    enum Tab: Hashable { case status, ports, local, settings }
    @State private var tab: Tab
    @State private var alertMsg: String?

    init(settings: AppSettings, monitor: StatusMonitor, localInfo: LocalInfo, initialTab: Tab = .status) {
        _settings = Bindable(settings)
        self.monitor = monitor
        self.localInfo = localInfo
        _tab = State(initialValue: initialTab)
        _alertMsg = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(settings.t("tab.status")).tag(Tab.status)
                Text(settings.t("tab.ports")).tag(Tab.ports)
                Text(settings.t("tab.local")).tag(Tab.local)
                Text(settings.t("tab.settings")).tag(Tab.settings)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            ScrollView {
                switch tab {
                case .status:
                    StatusTab(settings: settings, monitor: monitor, localInfo: localInfo, alertMsg: $alertMsg)
                case .ports:
                    PortsTab(settings: settings, monitor: monitor)
                case .local:
                    LocalTab(settings: settings, localInfo: localInfo)
                case .settings:
                    SettingsTab(settings: settings, alertMsg: $alertMsg)
                }
            }
            .frame(height: 430)

            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { monitor.windowOpen = true }
        .onDisappear { monitor.windowOpen = false }
        .alert(settings.t("alert.title"), isPresented: Binding(
            get: { alertMsg != nil },
            set: { if !$0 { alertMsg = nil } }
        )) {
            Button(settings.t("alert.ok"), role: .cancel) {}
        } message: {
            Text(alertMsg ?? "")
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await monitor.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(settings.t("footer.refreshHelp"))
            if let t = monitor.lastRefresh {
                Text(settings.f("footer.refreshedAt", t.formatted(date: .omitted, time: .standard)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !Defaults.donateURL.isEmpty {
                Button("☕") {
                    if let url = URL(string: Defaults.donateURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
                .help(settings.t("support.button"))
            }
            Button(settings.t("footer.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Tab 1 状态

struct StatusTab: View {
    @Bindable var settings: AppSettings
    var monitor: StatusMonitor
    var localInfo: LocalInfo
    @Binding var alertMsg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.f("status.greeting", localInfo.username)).font(.title3.bold())
                Text(settings.t("status.subtitle")).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(settings.routes) { route in
                routeCard(route)
            }

            if !monitor.mounts.isEmpty {
                mountsSection
            }
        }
        .padding(12)
    }

    private func routeCard(_ route: Route) -> some View {
        let st = monitor.routeStatus[route.id]
        let reachable = st?.reachable == true
        let isFastest = reachable && monitor.bestRoute?.id == route.id && monitor.reachableRoutes.count > 1
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: route.symbol)
                    .foregroundStyle(reachable ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(route.name).fontWeight(.medium)
                if isFastest {
                    Text(settings.t("status.fastest"))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
                Spacer()
                statusView(st)
            }
            HStack {
                Text(route.ip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button("SSH") { sshTapped(route) }
                    .controlSize(.small)
                    .disabled(!reachable)
                Button("SMB") { Actions.openSMB(username: settings.effectiveUsername, ip: route.ip) }
                    .controlSize(.small)
                    .disabled(!reachable)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private func statusView(_ st: RouteStatus?) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(st == nil ? Color.gray : (st!.reachable ? Color.green : Color.red))
                .frame(width: 7, height: 7)
            if let st {
                if st.reachable {
                    Text(st.latencyMs.map { String(format: "%.1f ms", $0) } ?? settings.t("status.up"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(settings.t("status.down")).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text(settings.t("status.checking")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sshTapped(_ route: Route) {
        if let err = Actions.openSSH(username: settings.effectiveUsername, ip: route.ip) {
            alertMsg = settings.f("status.terminalFailed", err)
        }
    }

    private var mountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("status.mounted")).font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.mounts) { m in
                HStack {
                    Image(systemName: "externaldrive.fill.badge.checkmark")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.volumeName).font(.callout)
                        Text(m.source)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: m.mountPoint))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(settings.t("status.openInFinder"))
                    Button {
                        if let err = Actions.eject(mountPoint: m.mountPoint) {
                            alertMsg = settings.f("status.ejectFailed", err)
                        } else {
                            Task { await monitor.refreshAll() }
                        }
                    } label: {
                        Image(systemName: "eject.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(settings.t("status.eject"))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
        }
    }
}

// MARK: - Tab 2 端口

struct PortsTab: View {
    @Bindable var settings: AppSettings
    var monitor: StatusMonitor
    @State private var newPort = ""
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(settings.t("ports.title")).font(.headline)
                Spacer()
                Text(monitor.bestRoute.map { settings.f("ports.via", $0.name) } ?? settings.t("ports.hostDown"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(settings.ports) { entry in
                portRow(entry)
            }

            HStack(spacing: 6) {
                TextField(settings.t("ports.portPlaceholder"), text: $newPort)
                    .frame(width: 55)
                TextField(settings.t("ports.labelPlaceholder"), text: $newLabel)
                Button { addPort() } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(Int(newPort) == nil)
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)

            Divider().padding(.vertical, 2)

            HStack {
                Text(settings.t("ports.scanTitle")).font(.headline)
                Spacer()
                Button(monitor.scanning ? settings.t("ports.scanning") : settings.t("ports.scanStart")) {
                    Task { await monitor.scanCommonPorts() }
                }
                .controlSize(.small)
                .disabled(monitor.scanning || monitor.bestRoute == nil)
            }
            scanResultsView
        }
        .padding(12)
    }

    private func portRow(_ entry: PortEntry) -> some View {
        HStack {
            Text(String(entry.port))
                .font(.callout.monospacedDigit().bold())
                .frame(width: 48, alignment: .leading)
            Text(entry.label.isEmpty ? (settings.portLabel(entry.port) ?? "") : entry.label)
                .font(.callout)
            Spacer()
            portStateView(entry)
            Button {
                settings.ports.removeAll { $0.id == entry.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    private func portStateView(_ entry: PortEntry) -> some View {
        HStack(spacing: 4) {
            switch monitor.portStates[entry.id] {
            case .open:
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(settings.t("ports.open")).font(.caption).foregroundStyle(.green)
            case .closed:
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(settings.t("ports.closed")).font(.caption).foregroundStyle(.red)
            case nil:
                Circle().fill(Color.gray).frame(width: 6, height: 6)
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addPort() {
        guard let p = Int(newPort), (1...65535).contains(p) else { return }
        guard !settings.ports.contains(where: { $0.port == p }) else {
            newPort = ""
            return
        }
        let label = newLabel.isEmpty ? (settings.portLabel(p) ?? "") : newLabel
        settings.ports.append(PortEntry(port: p, label: label))
        newPort = ""
        newLabel = ""
        Task { await monitor.refreshAll() }
    }

    @ViewBuilder
    private var scanResultsView: some View {
        if let results = monitor.scanResults {
            let openOnes = results.filter(\.open)
            if openOnes.isEmpty {
                Text(settings.f("ports.scanNoneFound", results.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openOnes) { r in
                    HStack {
                        Text(String(r.port))
                            .font(.callout.monospacedDigit().bold())
                            .frame(width: 48, alignment: .leading)
                        Text(settings.portLabel(r.port) ?? settings.t("ports.unknownService"))
                            .font(.callout)
                        Spacer()
                        if settings.ports.contains(where: { $0.port == r.port }) {
                            Text(settings.t("ports.monitored")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(settings.t("ports.addMonitor")) {
                                settings.ports.append(PortEntry(port: r.port, label: settings.portLabel(r.port) ?? ""))
                            }
                            .controlSize(.small)
                        }
                    }
                }
                Text(settings.f("ports.scanSummary", openOnes.count, results.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(settings.f("ports.scanHint", Defaults.commonScanPorts.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tab 3 本机

struct LocalTab: View {
    var settings: AppSettings
    var localInfo: LocalInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.f("status.greeting", localInfo.username)).font(.title3.bold())
                Text("\(localInfo.fullName) · \(localInfo.hostName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t("local.connectHint")).font(.caption).foregroundStyle(.secondary)
                ForEach(localInfo.ips) { item in
                    HStack {
                        Text(kindText(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        Text("ssh \(localInfo.username)@\(item.ip)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            Actions.copyToClipboard("ssh \(localInfo.username)@\(item.ip)")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(settings.t("local.copy"))
                    }
                }
            }

            Divider()

            HStack {
                Text(settings.t("local.listeningTitle")).font(.headline)
                Spacer()
                Button {
                    Task { await localInfo.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            if localInfo.loading && localInfo.listening.isEmpty {
                ProgressView().controlSize(.small)
            }

            ForEach(localInfo.listening) { p in
                HStack {
                    Text(String(p.port))
                        .font(.callout.monospacedDigit().bold())
                        .frame(width: 52, alignment: .leading)
                    Text(p.process.isEmpty ? settings.t("local.systemProcess") : p.process)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(scopeText(p.addr))
                        .font(.caption2)
                        .foregroundStyle(p.addr == "127.0.0.1" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                }
            }
        }
        .padding(12)
        .task { await localInfo.refresh() }
    }

    private func kindText(_ item: LocalIP) -> String {
        switch item.kind {
        case "wifi": return "Wi‑Fi"
        case "thunderbolt": return settings.t("local.thunderbolt")
        case "tailscale": return "Tailscale"
        case "bridge": return settings.t("local.bridge")
        default: return item.kind
        }
    }

    private func scopeText(_ addr: String) -> String {
        switch addr {
        case "*": return settings.t("local.allInterfaces")
        case "127.0.0.1": return settings.t("local.localhostOnly")
        default: return addr
        }
    }
}

// MARK: - Tab 4 设置

struct SettingsTab: View {
    @Bindable var settings: AppSettings
    @Binding var alertMsg: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t("settings.language")).font(.headline)
                Picker("", selection: $settings.language) {
                    Text(settings.t("settings.langSystem")).tag(Language.system)
                    Text("中文").tag(Language.zh)
                    Text("English").tag(Language.en)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(settings.t("settings.usernameTitle")).font(.headline)
                TextField(settings.t("settings.usernamePlaceholder"), text: $settings.username)
                    .textFieldStyle(.roundedBorder)
                Text(settings.t("settings.usernameHint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(settings.f("settings.intervalTitle", Int(settings.refreshInterval))).font(.headline)
                Slider(value: $settings.refreshInterval, in: 2...30, step: 1)
                Text(settings.t("settings.intervalHint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.t("settings.routesTitle")).font(.headline)
                ForEach($settings.routes) { $route in
                    HStack(spacing: 6) {
                        TextField(settings.t("settings.routeNamePlaceholder"), text: $route.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        TextField("IP", text: $route.ip)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                        Button {
                            settings.routes.removeAll { $0.id == route.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(settings.routes.count == 1)
                    }
                }
                Button {
                    settings.routes.append(Route(name: settings.t("settings.newRoute"), ip: "", symbol: "network"))
                } label: {
                    Label(settings.t("settings.addRoute"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Toggle(settings.t("settings.launchAtLogin"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }

            if !Defaults.donateURL.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.t("support.title")).font(.headline)
                    Text(settings.t("support.hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(settings.t("support.button")) {
                        if let url = URL(string: Defaults.donateURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                Button(settings.t("settings.resetDefaults")) { settings.resetDefaults() }
                    .controlSize(.small)
                Spacer()
                Text("MiniLink 1.1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let current = SMAppService.mainApp.status == .enabled
        guard current != on else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            alertMsg = settings.f("settings.launchFailed", error.localizedDescription)
        }
    }
}
