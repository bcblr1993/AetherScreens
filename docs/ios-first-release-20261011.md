# iOS 首次发布验收 — 2026-10-11

目标：在 iPhone 12 Pro 上验收可用版本，完成 App Store 提审与公开发布。

## 当前证据

- 真机 iPhone 12 Pro，USB 已配对，开发者模式开启，已解锁。
- 当前源代码真机 `build-for-testing` 成功；正式 bundle ID 的开发签名应用已安装并启动。
- 首轮受控测试选定缩放触控板边缘跟随、实际收到的手势、旋转映射、断线恢复。
- XCTest Runner 开启自动化超时，枚举只返回测试 bundle，未执行任何选定测试。验收脚本拒绝接受该结果。
- 证据：`build/iphone12pro-20261011-first/build.log`、`enumeration.log`、`enumeration.json`。
- 新增 iOS 隐私清单，声明 CA92.1、35F9.1、C617.1、3B52.1、E174.1；分别对应应用偏好、内部计时、应用容器/用户选择文件的元数据、落盘前空间检查。无跟踪声明。

- 新增隐私清单后的通用 iOS Release 构建成功，应用根目录包含有效的 `PrivacyInfo.xcprivacy`；构建日志 `/tmp/aetherscreens-ios-privacy-20261011.log`。

## 待完成

1. 手机允许 UI 自动化后重新执行上述测试，保留截图与实际服务端事件。
2. 连接 Mac mini 验证真实桌面、箭头光标、缩放点击、边缘跟随、键盘、前后台恢复和长时间连接。
3. 补齐应用内隐私政策入口、审核可用连接方式、iPhone/iPad 商店截图及中英文文案。
4. 检查 App Store Connect 应用记录、iOS 分发签名与导出合规问卷；SSH 加密不可未经核查直接标记为不使用非豁免加密。
5. Archive、上传、处理完成、提审、审核通过及公开链接分别核实。安装/构建成功不等于 App Store 已发布。

App Store Connect 当前浏览器未登录，需要账号登录。

参考：[Apple required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)、[提交审核](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)。

## 本轮进展

- 设置新增隐私政策与帮助支持入口，中文/英文完整本地化；官网两个地址已 HTTP 成功验证。
- 新入口后的 iOS Release 构建成功：`/tmp/aetherscreens-ios-support-links-20261011.log`；隐私清单仍存在于应用根目录，plist 校验通过。
- 商店文案草稿见 `docs/ios-app-store-metadata.md`，未上传、未提审。
- 手机仍处于解锁状态，但尚无用户确认 UI 自动化授权；不将安装成功视为交互验收。
- App Store Connect 页面刷新后仍停留登录失败页。

## 真机再次尝试

- `build/iphone12pro-20261011-usb-retry/build.log` 真机测试构建成功。
- Runner 启动后约 18 秒仍因 DTXProxyChannel Channel disconnected 退出；xcresult totalTestCount=0，不接受为通过。
- USB 枚举没有发现 iPhone，CoreDevice 仍使用 localNetwork。
- 当前含隐私政策/支持入口的开发签名应用已重新安装并启动，可以进行人工真机验收。
