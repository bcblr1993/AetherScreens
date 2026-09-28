# AetherScreens 📱🖥️

> **像 Screens 一样优雅地在 iPhone / iPad 与 Apple Silicon Mac 上通过 Tailscale 与局域网远程控制你的 Mac。**
> 
> A sleek, high-performance remote desktop client designed specifically for macOS Screen Sharing over Tailscale & Local Network, deeply inspired by Edovia Screens 5. Seamlessly runs on both **iOS** (iPhone & iPad) and **macOS** (Apple Silicon M1/M2/M3/M4).

[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-iOS%2017%2B%20%7C%20macOS%2014%2B%20(Apple%20Silicon)-blue.svg)](https://developer.apple.com)
[![Renderer](https://img.shields.io/badge/Renderer-Metal%20(60%2F120%20FPS%20ProMotion)-purple.svg)](https://developer.apple.com/metal/)
[![Protocol](https://img.shields.io/badge/Protocol-RFB%203.8%20(VNC)-green.svg)](https://datatracker.ietf.org/doc/html/rfc6143)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

---

## 🌟 核心特性 (Features - 照着 Screens 抄作业复刻)

### 1. 🚀 双端原生与极致丝滑 (iOS & Apple Silicon Mac)
* **iOS / iPadOS 极致触控体验**：
  * **虚拟触控板引擎**：植入 macOS 物理加速度曲线，支持单指轻敲左键、双指轻敲右键、长按拖拽、双指平滑自然滚动。
  * **双击快速缩放**：双击任意区域在“适合屏幕 (Fit)”与“100% 原始点对点像素 (Actual Size)”之间丝滑弹簧切换。
  * **触感反馈 (Tactile Haptics)**：每一次轻敲、点击与粘滞键锁定均提供触觉振动反馈 (`UIImpactFeedbackGenerator`)。
  * **iPadOS Magic Keyboard & Trackpad 专属支持**：支持指针悬停跟踪 (`.onContinuousHover`) 与硬件鼠标。
* **Apple Silicon (M系列) Mac 原生体验**：
  * **原生物理鼠标无缝透传**：运行在 Mac 上时直接透传原生光标与悬停，无需虚拟光标圆圈，支持高精度惯性滚轮与中键。
  * **系统级物理按键透传**：通过 AppKit `flagsChanged` 精准捕获 `Command`、`Option`、`Control`、`Shift`，热键无阻断透传至远端 Mac。
  * **现代三栏式布局**：基于 `NavigationSplitView` 的现代 Mac 原生侧边栏管理。

### 2. ⚡ Metal 硬件加速渲染管线 (60 / 120 FPS ProMotion)
* **GPU 直推渲染**：自主实现 Metal Shading Language (MSL) 动态着色管线，32位 BGRA 纹理直接上传至 Apple GPU，告别 CPU 绘图发热与掉帧。
* **ProMotion 120Hz 支持**：支持 MacBook Pro Liquid Retina XDR 与 iPhone Pro 屏幕的 120Hz 高刷新率，画面顺滑如镜。
* **实时性能诊断 HUD**：悬浮药丸胶囊实时监测并展示 **FPS 帧率**、**RTT 往返延迟 (ms)**、**吞吐带宽 (MB/s)** 与 Tailscale P2P 穿透状态。

### 3. 🛡️ Screens 5 独占高阶特性深度复刻
* **幕帘模式 (Curtain Mode)**：在外远程控制 Mac 时，一键锁定或黑屏实体显示器，防范路人窥屏，保护隐私；视口顶部显示胶囊隐私横幅。
* **多显示器自由切换 (Multi-Display Switcher)**：远端 Mac 接入外接显示器或双屏时，智能识别并提供“主屏幕”、“副屏幕”或“全景拼合”一键瞬时切换，并在视口中精准执行坐标空间重映射。
* **Mac 专属辅助键盘 (Mac Keyboard Toolbar)**：
  * **三态粘滞修饰键 (Screens 独家体验)**：`⌘`、`⌥`、`⌃`、`⇧` 支持单敲生效下个键、双击永久锁定 (🔒)、再次点击解锁。
  * **快捷输入抽屉 (Type to Mac)**：提供弹出手写/软键盘文字输入条，任意中英文字符、密码一键瞬传至远端 Mac。
  * **F1 - F12 完整功能键栏** 与高频系统动作：聚焦搜索 (`⌘ Space`)、调度中心 (`⌃ ↑`)、App 切换 (`⌘ Tab`)、一键锁屏 (`⌃ ⌘ Q`)、显示桌面 (`⌘ F3`)、强制退出 (`⌥ ⌘ Esc`)。
* **双向剪贴板无缝同步**：手机/客户端与远端 Mac 剪贴板文字一键秒级互通。
* **桌面快照预览卡片 (Desktop Snapshots)**：每次连接实时截取并持久化远端桌面的高清缩略图，在计算机列表卡片中直观呈现。

### 4. 🌐 局域网 Bonjour 自动发现与 Tailscale 远程穿透
* **局域网 Bonjour 零配置发现**：通过 `Network.framework` `NWBrowser` 自动扫描局域网内的 Mac (`_rfb._tcp`)，打开 App 即可直接在“附近设备”中一键直连！
* **网络唤醒 (Wake-on-LAN)**：支持向睡眠中的 Mac 发送标准 102 字节魔术数据包 (Magic Packet)，一键远程唤醒。
* **Tailscale REST API 自动同步**：输入 Tailscale API Token，一键秒级获取并合并 Tailnet 内所有在线 Mac / PC 节点。
* **WireGuard 点对点穿透**：无惧 NAT 阻隔与运营商内网，直接通过 `100.x.y.z` 建立端到端加密连接。

---

## 🏗️ 架构设计 (Architecture)

```
┌────────────────────────────────────────────────────────────────────────┐
│                   AetherScreens (iOS & Apple Silicon Mac)                │
├────────────────────┬───────────────────────────────────────────────────┤
│ UI 表现层          │ DeviceListView (macOS 三栏 / iOS 响应式 / Bonjour 发现)│
│                    │ RemoteDesktopView (双端视口渲染 / 双击缩放 / 悬停)   │
│                    │ MacKeyboardToolbar (三态粘滞修饰键 / F1-F12 / 文字发送)│
│                    │ PerformanceHUDView (FPS / 延迟 / 带宽诊断)           │
├────────────────────┼───────────────────────────────────────────────────┤
│ 渲染引擎层 (Metal) │ MetalScreenRenderer (MSL 60/120Hz 管线 / Apple GPU) │
│                    │ MetalScreenView (MTKView 双端适配封装)             │
│                    │ PerformanceMetrics (实时性能统计算法)               │
├────────────────────┼───────────────────────────────────────────────────┤
│ Screens 特性层     │ CurtainModeManager (防窥幕帘模式控制)               │
│                    │ MultiDisplayManager (多显示器识别 / 坐标转换 / 裁剪)│
│                    │ ThumbnailStore (桌面快照缩略图缓存)                 │
├────────────────────┼───────────────────────────────────────────────────┤
│ 交互与输入层       │ TrackpadEngine (iOS 虚拟触控板加速度 / 自然滚动)     │
│                    │ MacNativeInputHandler (macOS flagsChanged / 物理键鼠)│
│                    │ MacKeyMap (X11 KeySym 与 Mac 快捷键映射)            │
├────────────────────┼───────────────────────────────────────────────────┤
│ 协议与网络层       │ RFBClient (基于 Network.framework 流缓冲重组)       │
│                    │ VNCAuthCrypto (纯 Swift DES 挑战应答)               │
│                    │ Framebuffer (脏矩形合成与内存缓冲)                  │
├────────────────────┼───────────────────────────────────────────────────┤
│ 发现与网络工具     │ BonjourDiscoveryService (NWBrowser 局域网 Mac 发现) │
│                    │ WakeOnLANService (102字节 Magic Packet 网络唤醒)   │
│                    │ TailscaleClient (Tailnet 节点自动同步)              │
│                    │ DeviceStore & KeychainStore (安全持久化)            │
└────────────────────┴───────────────────────────────────────────────────┘
```

---

## 🚀 编译与运行

### 1. 运行 macOS 原生桌面端
```bash
# 编译并直接启动 macOS 原生 App
swift run AetherScreensApp
```

### 2. 运行 iPhone / iPad App
```bash
xcodegen generate --spec ios/project.yml --project ios
open ios/AetherScreensIOS.xcodeproj
```
在 Xcode 中选择 `AetherScreensIOS` scheme 和 iPhone 模拟器或已签名的真机。`ios/project.yml` 会生成含启动画面和局域网权限声明的 iOS App target。

### 3. 编译所有模块
```bash
swift build
```

### 4. 运行自动化测试
```bash
swift test
# iPhone 模拟器 UI 测试：选择 AetherScreensIOS scheme 后在 Xcode 中运行 Test
```

真实 Tailscale 首帧测试依赖可用的远端屏幕共享服务，不能用模拟服务器通过来代替。默认跳过，需要时指定被控 Mac 的地址运行：

```bash
AETHERSCREENS_LIVE_HOST=100.x.y.z swift test --filter TailscaleLiveHandshakeTests
```

---

## 🧪 自动化测试套件

| 模块 | 测试内容 | 状态 |
| :--- | :--- | :---: |
| `MetalScreenRendererTests` | Apple Silicon GPU (M1/M2/M3/M4) Metal 渲染管线与着色器验证 | ✅ Passed |
| `CurtainModeManagerTests` | 幕帘模式状态机与系统锁屏联动触发 | ✅ Passed |
| `MultiDisplayManagerTests` | 单双显示器自适应检测、显示器切换计算与坐标空间重映射 | ✅ Passed |
| `WakeOnLANTests` | MAC 地址格式多变体解析与 102 字节魔术数据包构造验证 | ✅ Passed |
| `BonjourDiscoveryTests` | Bonjour 局域网服务发现与 `DiscoveredMac` 转换验证 | ✅ Passed |
| `ThumbnailStoreTests` | 桌面高清缩略图内存与磁盘持久化缓存验证 | ✅ Passed |
| `RFBStreamBufferTests` | TCP 分段流缓冲累加与大尺寸帧缓冲区组装测试 | ✅ Passed |
| `StickyModifierTests` | 三态粘滞键 (Inactive -> ActiveOnce -> Locked) 状态机验证 | ✅ Passed |
| `PerformanceMetricsTests` | FPS 滑动窗口均值计算、指数平滑往返延迟 (ms)、带宽计数 | ✅ Passed |
| `RFBPacketTests` | 协议版本协商、SecurityTypes、ServerInit、Pointer/Key 封包 | ✅ Passed |
| `VNCAuthCryptoTests` | 标准 DES ECB 加密测试向量 (NBS/NIST 标准)、Bit Reversal | ✅ Passed |
| `TrackpadEngineTests` | 触控加速度非线性物理曲线、视口边缘裁剪、双指滚轮 | ✅ Passed |
| `MacKeyMapTests` | ASCII 映射与全部 Mac 系统快捷键键序闭环 | ✅ Passed |
| `TailscaleModelsTests`| Tailscale REST API 数据解析、IPv4 过滤提取、Mac 识别 | ✅ Passed |
| `DeviceStoreTests` | 本地存储管理、Keychain 安全存储、Tailnet 节点状态合并 | ✅ Passed |

---

## 🌐 官网与发布

- 官网条目：`website_content/apps/aetherscreens/`，是 [aethernative.com](https://aethernative.com/apps/aetherscreens/) 页面的源文件。修改后运行 `./scripts/sync_to_website.sh` 复制到本地的 `aethernative-site` 仓库，再在那边提交。
- 发布 GitHub Release 时，`.github/workflows/aethernative-sync.yml` 会通知官网自动同步版本（需要仓库 Secret `AETHERNATIVE_SITE_TOKEN`）。
- 正式打包：`./scripts/package_release.sh`。签名证书名称写在 `scripts/signing.local.env`（`AETHERSCREENS_SIGNING_IDENTITY="Developer ID Application: …"`），该文件不进仓库。
- Bundle ID：macOS `com.aethernative.aetherscreens`，iOS `com.aethernative.aetherscreens.ios`。

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
