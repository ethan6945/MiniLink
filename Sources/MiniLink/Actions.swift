import AppKit

@MainActor
enum Actions {
    /// 所有路由都是同一台远程 Mac，host key 其实相同。用固定 HostKeyAlias 让它们
    /// 共用同一条 known_hosts 记录：接受一次后，无论走哪条路由、IP 怎么变都不再问。
    private static let hostKeyAlias = "minilink-remote"

    /// 打开终端执行 ssh。返回错误信息，成功返回 nil。
    static func openSSH(username: String, ip: String) -> String? {
        // accept-new：首次/换 IP 自动信任、不再弹 yes（密钥“真的变了”仍会拦截告警）
        // ConnectTimeout：掉线路由快速失败，不卡住
        let opts = "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o HostKeyAlias=\(hostKeyAlias)"
        let cmd = "ssh \(opts) \(username)@\(ip)"
        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        var errorDict: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorDict)
        if let e = errorDict {
            return e[NSAppleScript.errorMessage] as? String ?? "AppleScript 执行失败"
        }
        return nil
    }

    static func openSMB(username: String, ip: String) {
        let urlStr = username.isEmpty ? "smb://\(ip)" : "smb://\(username)@\(ip)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 弹出 SMB 挂载卷。返回错误信息，成功返回 nil。
    static func eject(mountPoint: String) -> String? {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: mountPoint))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
