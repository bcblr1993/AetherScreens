# AetherScreens iOS — App Store 文案草稿

尚未提交；必须在真机验收后逐项核实。

## 中文

- 名称：AetherScreens
- 副标题：连接 Mac 的远程桌面
- 关键词：远程桌面,屏幕共享,VNC,Mac,触控板,SSH,Tailscale
- 描述：

AetherScreens 让你通过 iPhone 或 iPad 连接开启屏幕共享的 Mac，以及兼容的 VNC 服务。保存常用电脑，在局域网发现设备，或使用已配置的 Tailscale 网络连接远端电脑。

使用触控板或直接触控操作远程桌面，缩放查看细节，通过快捷键工具栏输入常用组合键，并按网络情况选择显示质量。支持配置 SSH 隧道和校验服务器主机密钥。兼容的 Mac 屏幕共享服务可使用文件传输；普通 VNC 服务器的功能取决于服务端支持。

连接需要目标电脑开启屏幕共享或 VNC 服务，并具有网络访问权限和有效登录凭据。跨网络连接需要事先配置网络或 Tailscale；AetherScreens 不提供中继服务。

## English

- Name: AetherScreens
- Subtitle: Remote desktop for your Mac
- Keywords: remote desktop,screen sharing,VNC,Mac,trackpad,SSH,Tailscale
- Description:

Connect from your iPhone or iPad to a Mac with Screen Sharing enabled, or to a compatible VNC server. Save computers, discover nearby devices, and connect through an existing Tailscale network.

Control your remote desktop with trackpad or direct-touch input. Zoom in, use the shortcut toolbar, and choose display quality to suit your connection. Configure SSH tunnels with server host-key verification. File transfer is available with compatible Mac Screen Sharing services; capabilities on other VNC servers depend on server support.

The remote computer must have Screen Sharing or a VNC service enabled, be reachable over the network, and have valid login credentials. Connections across networks require prior network or Tailscale configuration. AetherScreens does not provide a relay service.

## Links

- Privacy: https://aethernative.com/apps/aetherscreens/privacy/
- Support: https://aethernative.com/apps/aetherscreens/support/
- Marketing: https://aethernative.com/apps/aetherscreens/

## 审核说明草稿

The app connects to a user-controlled Mac or VNC server. To test with a Mac on the same network, enable System Settings > General > Sharing > Screen Sharing. Open AetherScreens, add the Mac address, and use the authorized Mac account to connect. The app itself does not require an AetherScreens account.

Before submission, attach a physical-device demonstration covering connection, zoomed input, keyboard and disconnection, and arrange a reachable review connection if requested. Never include the user's home-computer password or Tailscale API token in public metadata.

## 发布前必须确认

- 真机测试与真实 Mac 服务端验收通过。
- iPhone/iPad 截图为实际应用界面，符合 Apple 当前尺寸要求。
- 隐私问卷、加密出口合规、年龄分级、价格与销售地区以账号和代码实际情况填写。
- 检查 iOS 分发证书与描述文件，使用正确版本/唯一构建号上传。
- 提交审核与公开上架状态分别验证，不以成功上传替代发布。
