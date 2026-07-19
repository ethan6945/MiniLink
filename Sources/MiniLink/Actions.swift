import AppKit

@MainActor
enum Actions {
    /// 打开终端执行 ssh。返回错误信息，成功返回 nil。
    static func openSSH(username: String, ip: String) -> String? {
        let cmd = "ssh \(username)@\(ip)"
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
