<p align="center">
  <img src="docs/icon.png" width="128" alt="MiniLink 图标">
</p>

<h1 align="center">MiniLink</h1>

<p align="center">
  macOS <b>菜单栏工具</b>：监测并一键连接你的远程 Mac ——<br>
  支持 <b>局域网、Tailscale、雷雳直连</b> 多线路，一键 <b>SSH / SMB</b>，实时延迟，内置<b>端口扫描</b>。
</p>

<p align="center">
  简体中文 · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="platform">
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" alt="swift">
  <img src="https://img.shields.io/badge/UI-SwiftUI-green" alt="swiftui">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="license">
</p>

---

## 为什么做这个？

如果你有一台**无头 Mac mini / Mac Studio** 当家庭服务器、编译机或 AI 主机，你多半在为同一台机器记好几个 IP：在家用局域网地址、在外面走 **Tailscale**、传大文件时插**雷雳线直连**。每次连接前都要想：*现在哪条线路通？雷雳线到底插没插好？SSH 开着吗？切了网络之后 SMB 挂载是不是卡死了？*

MiniLink 把这些答案放进菜单栏，一眼看清、一键连接。

## 功能

- 🚦 **多线路状态** — 给同一台机器定义任意多条线路（局域网 / Tailscale / 雷雳 / VPN…），每条实时显示连通状态灯和 **ping 延迟**，最快的线路带「最快」标记
- ⚡ **一键连接** — `SSH` 打开终端执行 `ssh 用户名@IP`；`SMB` 在访达中挂载共享（凭据走钥匙串）
- 🔌 **端口监测** — 盯住你关心的端口（SSH 22、SMB 445、屏幕共享 5900 或自己的服务），经由最快线路实时探测开放/关闭
- 🔍 **常用端口扫描** — 一键扫描 ~26 个常用端口（SSH、SMB、AFP、VNC、**Ollama、LM Studio、ComfyUI、Jupyter**、开发服务…），发现开放的可直接加入监测列表
- 💾 **SMB 挂载管理** — 显示当前已挂载的共享，**一键弹出**（告别切网后访达卡死）
- 🖥️ **「本机」页** — 本机用户名、主机名、每张网卡的 IP（组成可复制的 `ssh 用户名@IP` 命令，方便别的机器连回来），以及**本机所有监听端口和对应进程**——立刻看清哪些服务暴露在所有网卡、哪些只在本机
- 🌐 **中文 & English** — 设置里随时切换，也可跟随系统语言
- 🪶 **原生轻量** — 纯 SwiftUI + Network.framework，无 Electron、零依赖、无遥测，所有数据只留在本机

## 安装

从源码构建（需要 Xcode Command Line Tools，macOS 14+）：

```bash
git clone https://github.com/Junxian0405/MiniLink.git
cd MiniLink
./build.sh
open build/MiniLink.app     # 或拖进「应用程序」文件夹
```

首次使用：

- 默认线路 IP 是**示例值**——打开弹窗里的**设置**页，改成你自己的 IP、SSH 用户名，线路可任意增删
- 第一次点 **SSH** 时 macOS 会询问「控制终端」权限，点允许
- 想用**开机自启**，请从「应用程序」文件夹运行

## 命令行自检

同一个二进制也能当命令行网络检测工具，适合脚本和排查：

```bash
./build/MiniLink.app/Contents/MacOS/MiniLink --check
```

## 实现原理

- **延迟**：每轮刷新对每条线路发一次 ICMP ping（`/sbin/ping` 子进程），无需特殊权限
- **端口探测**：`Network.framework` `NWConnection` TCP 握手，2 秒超时
- **本机端口**：`netstat` 拿完整监听列表，`lsof` 标注进程名
- **挂载**：解析 `mount` 输出，`NSWorkspace` 弹出
- 所有检测并发执行；弹窗关闭时自动降低频率省电

## 适用场景

无头 Mac mini 家庭服务器 · 通过 Tailscale 远程访问自己的 Mac · 两台 Mac 之间雷雳网桥直连 · 监控跑 Ollama / LM Studio / ComfyUI 的机器 · 传大文件前先看哪条线路最快 · 快速查看自己的 Mac 对外暴露了哪些端口。

## 许可证

[MIT](LICENSE) © Ethan Tan
