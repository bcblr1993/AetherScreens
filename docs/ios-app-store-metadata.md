# AetherScreens iOS — App Store 文案草稿

App Store Connect 的 1.3.4（2026102202）已于 2026-10-22 正式提交，当前“正在等待审核”，审核通过后手动发布；未通过的手势验证仍需后续处理。首发仅支持 iPhone，iPad 暂缓。

首发定价：美国基础价格 US$1.00，其他商店采用 Apple 对应本币价格。销售地区选择 144 个，排除中国大陆、香港、澳门、台湾及欧盟 27 国（含法国）。用户已签署付费 App 协议并填写银行及税表，Apple 后台处理状态仍需继续核实。

## 中文

- 名称：AetherScreens
- 副标题：在 iPhone 上连接和操控你的 Mac
- 关键词：远程桌面,屏幕共享,VNC,Mac,触控板,SSH,Tailscale
- 描述：

AetherScreens 让你通过 iPhone 连接开启屏幕共享的 Mac，以及兼容的 VNC 服务。保存常用电脑，在局域网发现设备，或使用已配置的 Tailscale 网络连接远端电脑。

使用触控板或直接触控操作远程桌面，缩放查看细节，通过快捷键工具栏输入常用组合键，并按网络情况选择显示质量。支持配置 SSH 隧道和校验服务器主机密钥。兼容的 Mac 屏幕共享服务可使用文件传输；普通 VNC 服务器的功能取决于服务端支持。

连接需要目标电脑开启屏幕共享或 VNC 服务，并具有网络访问权限和有效登录凭据。跨网络连接需要事先配置网络或 Tailscale；AetherScreens 不提供中继服务。

可选 iCloud 同步可在你的设备之间同步已保存的电脑配置。密码、SSH 私钥及其他凭据仅保存在本机钥匙串中，不参与 iCloud 电脑列表同步。

## English

- Name: AetherScreens
- Subtitle: Remote Desktop for Your Mac
- Keywords: remote desktop,screen sharing,VNC,Mac,trackpad,SSH,Tailscale
- Description:

Connect from your iPhone to a Mac with Screen Sharing enabled, or to a compatible VNC server. Save computers, discover nearby devices, and connect through an existing Tailscale network.

Control your remote desktop with trackpad or direct-touch input. Zoom in, use the shortcut toolbar, and choose display quality to suit your connection. Configure SSH tunnels with server host-key verification. File transfer is available with compatible Mac Screen Sharing services; capabilities on other VNC servers depend on server support.

The remote computer must have Screen Sharing or a VNC service enabled, be reachable over the network, and have valid login credentials. Connections across networks require prior network or Tailscale configuration. AetherScreens does not provide a relay service.

Optional iCloud sync keeps saved computer configurations available across your devices. Passwords, SSH private keys, and other credentials remain in the local Keychain and are excluded from computer-library synchronization.

## Links

- Privacy: https://aethernative.com/apps/aetherscreens/privacy/
- Support: https://aethernative.com/apps/aetherscreens/support/
- Marketing: https://aethernative.com/apps/aetherscreens/

## 审核说明草稿

The app connects to a user-controlled Mac or VNC server. To test with a Mac on the same network, enable System Settings > General > Sharing > Screen Sharing. Open AetherScreens, add the Mac address, and use the authorized Mac account to connect. The app itself does not require an AetherScreens account.

Before submission, attach a physical-device demonstration covering connection, zoomed input, keyboard and disconnection, and arrange a reachable review connection if requested. Never include the user's home-computer password or Tailscale API token in public metadata.

## 发布前必须确认

- 真机 iCloud 同步及真实 Mac 桌面已验证；受控手势仍有失败。按用户最新授权先提审，审核通过后手动发布。
- iPhone 截图为实际应用界面，符合 Apple 当前尺寸要求；本次不提交 iPad 版。
- 隐私问卷、加密出口合规、年龄分级、价格与销售地区以账号和代码实际情况填写。
- 检查 iOS 分发证书与描述文件，使用正确版本/唯一构建号上传。
- 提交审核与公开上架状态分别验证，不以成功上传替代发布。
