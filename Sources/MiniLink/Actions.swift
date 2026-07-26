import AppKit

@MainActor
enum Actions {
    /// 打开终端执行 ssh。返回错误信息，成功返回 nil。
    static func openSSH(username: String, ip: String) -> String? {
        // accept-new：首次/换 IP 自动信任、不再弹 yes（密钥“真的变了”仍会拦截告警）
        // ConnectTimeout：掉线路由快速失败，不卡住
        let opts = "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o HostKeyAlias=\(Defaults.sshHostKeyAlias)"
        let cmd = "/usr/bin/ssh \(opts) \(shellQuoted("\(username)@\(ip)"))"
        return runInTerminal(cmd)
    }

    /// 创建 MiniLink 专用密钥，通过一次交互式密码登录把公钥加入远端，并顺手把远端
    /// 家目录权限收回到 755（去掉 group/other 写）。否则家目录若可被写，sshd 的
    /// StrictModes 会拒绝一切密钥登录——公钥装了也读不到性能。私钥始终只留在本机 ~/.ssh。
    static func setupSSHKey(
        username: String,
        ip: String,
        successMessage: String
    ) -> String? {
        let target = shellQuoted("\(username)@\(ip)")
        let baseOptions =
            "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "
            + "-o HostKeyAlias=\(Defaults.sshHostKeyAlias)"
        let copyOptions = "\(baseOptions) -o IdentitiesOnly=yes"
        let script = """
        KEY="$HOME/.ssh/minilink_ed25519"; \
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" && \
        { test -f "$KEY" || /usr/bin/ssh-keygen -q -t ed25519 -N '' -C MiniLink -f "$KEY"; } && \
        /usr/bin/ssh \(baseOptions) \(target) 'chmod go-w ~' && \
        /usr/bin/ssh-copy-id -i "$KEY.pub" \(copyOptions) \(target) && \
        /usr/bin/printf '\\n%s\\n' \(shellQuoted(successMessage))
        """
        return runInTerminal(script)
    }

    private static func runInTerminal(_ command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var errorDict: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorDict)
        if let e = errorDict {
            return e[NSAppleScript.errorMessage] as? String ?? "AppleScript 执行失败"
        }
        return nil
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
