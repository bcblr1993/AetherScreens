# iPhone 首发准备 — 2026-10-22

状态：已正式提交 Apple 审核；App Store Connect 显示“正在等待审核”。尚未审核通过或公开上架，审核通过后手动发布。

## 发布配置

- App Store Connect App ID：6825592400；Bundle ID：com.aethernative.aetherscreens.ios。
- 版本 1.3.4；新构建 2026102202 已于本机时间 11:26 上传成功，11:37 核实 Apple 处理完成，现已替换草稿中的旧构建关联并保存；新构建包含本轮 iCloud 状态刷新修复。本次仅 iPhone，iPad 暂缓。
- 美国基础价 US$1.00，重新打开服务器端当前价格明细已核实；其他商店使用 Apple 自动对应价格。
- 供应范围已保存为 144 个国家或地区；按用户要求排除中国大陆、香港、澳门、台湾及欧盟 27 国（含法国）。
- 用户已本人签署付费 App 协议并填写银行及税表；最近后台仍显示协议“等待用户信息”、银行信息“正在处理”，两张美国税表仍提示缺少信息。需继续核实 Apple 处理状态；不代填或签署税务声明。首发已排除欧盟，DSA 账户声明仍待核实。
- 按用户授权沿用开发者账户的非公开审核联系资料，未在此文档记录私人联系方式。
- 搭载 Apple 芯片 Mac 及 Apple Vision Pro 的兼容分发已关闭并保存；仅 iPhone 首发。
- 隐私答复“未收集数据”经用户确认后已发布；中英文隐私政策链接已保存。

## 已完成的技术准备

- 配置专用容器 iCloud.com.aethernative.aetherscreens 并关联 App ID。
- CloudKit 类型 AetherScreensComputerLibrary（journal BYTES、schema INT64）已部署生产环境；应用使用私有数据库。
- 补齐 iCloud entitlement 与中英文 Face ID 用途说明。
- 正式 Archive、App Store 导出及上传成功。分发签名包含 Production iCloud 环境，get-task-allow=false，UIDeviceFamily=[1]。
- 上传日志：build/app-store-20261022/upload.log。最终包：build/app-store-20261022/export-final/AetherScreensIOS.ipa。
- swift test：855 项，30 项按环境跳过，0 失败；此结果不替代真机或真实 Mac 服务验收。
- 正式应用包隐私扫描通过：build/app-store-20261022/distribution-privacy.log。
- 中英文版本文案、支持及营销链接已存入 App Store Connect 草稿；分类已设为效率／工具，年龄问卷计算为 4+，已保存。
- 官网隐私更新独立分支 PR #16：补充可选 iCloud 同步及连接安全说明；230 项测试、570 个页面、19,035 个链接和三个签名更新源验证通过，中英文页面视觉检查完成。PR #16 已合并，主分支提交 97a51478a94dfb0c791e355061c62e510a92e134 的 Cloudflare 检查通过；生产环境中英文页面已在浏览器核实生效。

## 真机验收边界

- 原设备：iPhone 16 Pro Max；用户随后改用 USB 连接的 iPhone 12 Pro（iOS 27.0.1，开发者模式开启，已解锁）。
- 开启应用本地网络权限后，受控服务已收到真实画面、指针及键盘事件，且断线后产生第二条连接。
- 旧恢复测试要求出现手动重试按钮，与当前自动重连行为不符；测试改为要求新 TCP 连接及真实画面，并继续校验输入。
- physical-paid-release 在测试发现阶段因手机锁定及开发者证书未信任而失败，未执行选定测试。用户随后确认已信任证书并保持解锁。
- physical-trusted-release 实际执行 6 项：中英文手势各 1 项通过，其余 4 项失败，0 跳过，0 runtime warnings。失败分别涉及首次画面等待、手势事件及快速连接界面；尚未完成发布验收。
- live-trusted-cloudkit-and-mac 在开启 iCloud 同步后，用户更换手机导致设备连接中断（CoreDevice unavailable），未验证同步成功或真实 Mac 桌面。旧手机的同步开关原为关闭，测试中断使恢复状态无法核实，后续需在该手机检查。
- 新 iPhone 12 Pro 的 physical-replacement-release 构建成功，但开启自动化模式超时，未执行选定测试；已请用户在新手机开启“设置 → 开发者 → 启用 UI 自动化”。
- 用户确认已开启自动化后，physical-replacement-enabled 因设备未出现在 Xcode 目标列表而未运行；刷新调试连接后的 physical-replacement-connected 构建成功，但安装测试产品时报 IXRemoteErrorDomain 6（Connection interrupted），仍未执行选定测试。
- 已刷新现有配对、核实签名有效且描述文件包含新手机、检查 DDI 兼容，并单独尝试安装；单独安装也因远端连接关闭而失败。用户换 USB 接口后，此前 USB 硬件清单暂未枚举 iPhone；用户换数据线后 Finder 已可见，调试链路恢复。
- 新手机 physical-finder-visible 实际执行 6 项，全部失败；失败画面提示远程端口拒绝连接，受控服务未收到事件。用户确认新手机 Safari 也无法访问 10.8.5.253:8968。Mac 另有 Wi-Fi 地址 172.16.3.110，已将受控服务切到该地址并本机核实返回 []，用户已确认新手机能访问该 Wi-Fi 地址。
- physical-wifi-path 实际执行 6 项但均失败：5 项被“开发者 App 证书未受信任”阻止启动，最后一项被系统“无法验证 App”弹窗干扰。签名严格校验、签名证书与描述文件指纹匹配、设备授权均通过；用户随后确认手机已验证且手动打开正常。
- physical-wifi-verified-native 被测试运行器证书校验阻止，本轮未执行用例。保留已安装二进制、直接启动的 physical-wifi-without-rebuild 实际执行 1 项，收到真实画面并完成部分后续输入，但首帧等待、单击、双击、拖动等累计 8 条断言失败；本轮不能验收。
- physical-cloudkit-phone12 因证书验证被阻止，未验证私有数据库读写；保留二进制后的 physical-cloudkit-phone12-warm 实际执行 1 项失败。失败层级证实 iCloud 开关一直为关闭：SwiftUI 暴露了整行与内层开关，旧测试点行中心未打开同步，不能视为 CloudKit 网络失败。进一步读取手机偏好确认实际服务已同步成功但 UI 开关未更新。修复设置分区对 ComputerSyncService 的直接观察后，physical-observed-sync-native 的 iCloud 用例通过；读回偏好确认本轮有新的同步时间，且已恢复原先关闭状态。同批手势用例仍有 6 条输入断言失败，未验收通过。
- physical-real-mac-phone12：手机连接现有 Mac 并收到真实桌面，用例 1/1 通过，0 跳过、0 runtime warnings；Mac 未运行 AetherScreens 客户端。
- 用户最新要求仅在手机运行验收。已关闭本次本地网页预览服务；Mac 没有运行 AetherScreens 应用。Mac 仅用于构建／安装／驱动手机及提供手机连接的受控测试服务。

## 仍需完成

1. 私有 iCloud 同步与真实 Mac 桌面已通过本轮手机验证；受控手势仍有失败，保留为审核期间的待办，不再作为用户授权提审的前置条件。
2. 不含个人电脑资料的真实 iPhone 商店截图已上传并保存：英文 2 张、简体中文 1 张。
3. 年龄分级、分类、中英文隐私链接及隐私标签已保存；隐私答复经用户确认后发布。最终送审构建为 2026102202，出口问卷按标准加密算法、法国不分发回答并保存。
4. 2026-10-22 约 11:40 正式提交审核，Apple 确认“已提交 1 个项目”，随后版本状态显示“正在等待审核”。
5. 后续待 Apple 审核结果；审核通过后仍需手动发布，并单独验证公开供应。当前不声称已公开上架。

## 优先提交审核的最新检查

- 用户要求先提交 Apple 审核（如果可行），不再把继续补测作为提交动作的先决条件；未通过的手势测试结果保留并如实说明。
- 已实际点击“添加以供审核”。Apple 当前只返回一项必填缺失：带灵动岛的 iPhone（中等显示屏）截图。可接受 1179×2556、1206×2622 及横屏对应尺寸；新手机 12 Pro 原图 1170×2532 不直接匹配。
- 用户原选连接中屏动态岛机型；实际设备为 iPhone 16 Pro Max，用户已明确同意改用这台手机采集真实截图，并用代码等比排版至 Apple 规定尺寸，不生成或伪造应用界面。
- 只采集上架所需页面，不重跑全套验收；避免拍摄私人电脑列表、真实工作桌面及账户资料。
- 发布方式已保存为审核通过后手动发布。截图补齐和新构建处理完毕后继续实际提交；当前仍未提审。
- 新构建日志 upload-build02.log 明确记录 Upload succeeded；Archive、导出、生产 iCloud entitlement、分发签名及隐私扫描通过。最终 IPA 为 export-build02/AetherScreensIOS.ipa。
- iPhone 16 Pro Max 已实际采集两张英文、一张中文无私人资料的原始截图（1320×2868）；通过代码完整等比排版为 1206×2622。原图、最终图、原图对应关系及 SHA-256 均保留在 build/app-store-20261022/store-capture-originals 和 store-screenshots。
- 截图专用用例的前三张附件完整取得并视觉检查；最后的中文快速连接画面被系统通知打断，用例记录失败，不作为功能验收通过。该失败画面未用于商店。没有新增或保存电脑，没有连接私人桌面。
- Apple 已接受并保存英文 2 张、简体中文 1 张 1206×2622 截图，分别读取到 2/10 与 1/10 张 App 截屏。网页凭据 asc-english-screenshots-uploaded.png、asc-chinese-screenshot-uploaded.png；等待新构建处理后替换并提审。
- 新构建 2026102202 的出口问卷已按标准加密算法、法国不分发保存；版本草稿已关联新构建并保存，继续执行送审校验。
- 最终实际点击“添加以供审核”并通过必填校验；草稿提交包含 1.3.4 (2026102202)。随后点击“提交以供审核”，Apple 返回“已提交 1 个项目”。重新读取版本页，显示“1.3.4 正在等待审核”，构建链接仍为 2026102202。
- 审核提交 ID：6ae4fdec-dde0-45b0-8dc2-6a5c9827407e。成功凭据：build/app-store-20261022/asc-submitted-confirmation.png。
