# Apple Adaptive DCT 实现边界

审查日期：2026-10-05。本文是待审阅的实现合同，不是功能或验收通过回执。
参考固定为 rootshell-vnc 提交 `3950a452ad6ed75f82177964418092d1fa88a929`；审查的 16 个源码/文档字节均匹配该提交的 Git blob。

## 当前限制与最小范围

- **1011 就是 0x3f3。当前仅静态参考、保留 skip 标记；不实现、不运行 decoder 或 DCT fixture，也不广告该 encoding。**
- skip 不是已知 payload framing：收到未支持的图像 encoding 时安全失败，不猜长度、不盲跳字节、不发布为像素。
- 只有人类明确解除既有 decoder 限制，才能进入实现阶段；解除该限制不扩大凭据、抓包、设备、签名或发布授权。
- 建议窄范围适配连接级 decoder 与必需的 C kernel，接入现有 RFB/Framebuffer；先保留 Raw、CopyRect、Zlib、ZRLE 回退。
- 不直接引入整个 rootshell-vnc 包。整包另依赖 BigInt、SwiftNIO、NIOSSL、NIOTransportServices，须独立评估新增依赖。
- Standard TCP 的多阶段细化、HEVC 高性能路径与半尺寸缩放分别验收；半尺寸、单次有损 DCT 或 HEVC 码率变化不能替代 progressive。

## 公开源码所支持的判断

- 1011 的参考实现具有 base、refinement、quantization 消息及跨矩形缓存，提供渐进细化的源码线索；它不是 Apple 官方协议规范。
- 正数 1000、1001 只有 native viewer 允许值线索，没有足够 payload/decoder 合同；`appleJPEG = -1000` 不能混用。
- 1002 的参考实现明确因缺少 framing/parser 而排除；不能随 1011 一起广告。
- 当前 AetherScreens 只有 Raw、CopyRect、Zlib、ZRLE 图像解码，progressive 仍是未实现、未验收的首版要求。

## 获准实现后必须满足的边界

- 输入：显式限制 payload 字节、画布像素、矩形数、解码工作量及总分配；长度、尺寸乘法和坐标加法均检查溢出。
- 缓冲：累计接收数据不能线性滞留；系数、图块缓存及排队帧必须有字节预算，不能只依靠单包上限。
- 状态：一条连接拥有一个串行 decoder；不跨连接共享缓存、量化表或临时指针；重连从干净状态开始。
- 顺序：refinement 必须对应有效 base/代际；复制引用不能制造目的图块系数，过期引用不能污染新画面。
- 区域：分别处理部分矩形、非整块边缘和跨行复制；只有实际图像更新计入新画面，量化控制不能计帧。
- resize：清除旧系数和缓存，明确保留或重建量化状态的合同；同尺寸重连也不能继承旧状态。
- 失败：截断、越界、非法缓存键、未知类型或未证实语义均失败关闭；不压制错误或以旧帧计通过。
- 协商：只有 framing、decoder、renderer 完整实现且验证后才广告；Apple 元数据或注册编号不是 codec 可用证明。

## 测试与真实验收门槛

- 获准后先测长度不符、空/截断/超限数据、位读取边界、非法缓存键、矩形越界及内存预算；审批前不运行这些 fixture。
- 测 base/refinement 顺序、缺失 base、部分区域、水平/垂直及跨行复制、过期代际、缓存环绕和量化变更。
- 测 resize、断线重连、连续更新与回退协商；验证没有跨会话残留、泄漏或错误的新帧统计。
- 保留 golden，但参考仓库的 golden 来自旧 decoder，不能作为唯一 oracle；须有独立期望值和独立复核。
- 真实验证须使用已授权的正常认证、已知测试图案和固定缩放，证明同一区域先有 base、后有可测的细节改善。
- 12Pro 到 Macmini 的实际客户端至少连续 60 秒新画面；验收运动后恢复、受限链路恢复、输入可用性及 resize/reconnect。
- 单屏通过不能替代双屏：屏 1、屏 2、All 都需真实新画面与输入验收；现有单屏环境不自动满足此门槛。
- Mac/iOS 实际编译、UIKit/GPU 渲染和实体操作独立验收；合成负载、源码测试或旧候选结果不能继承为当前通过。

## 认证、捕获与许可证来源

- 正常 Type 33/35 路径使用调用方凭据并检查服务器结果/证明；不采用认证绕过、PoC 或诊断探测路径。
- 不采用仓库外部 `ADCTCAP1` captures。其原始采集者、授权、系统/客户端版本和认证回执未随源码提供。
- 名称为 Captured 的 header 测试含人工填充；性能文档明确是合成负载，不是 live FPS 或本产品验收。
- 不照搬上游握手 hex、桌面名称、包前缀或帧落盘诊断；保持本任务固定白名单回执，不保存真实凭据、输入或桌面像素。
- 仓库 MIT 版权归 Rootshell LLC / Kit Knox；若适配，须保留其版权与完整许可通知并记录固定提交。
- C kernel 注明派生自 stb_image 的公共领域/MIT 实现；采用前复核上游来源和许可选择，保留适用的上游版权/许可 notice。

## 固定提交的原始来源

- [Encoding 与 framing 能力](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBProtocol/Types/Encoding.swift)；[协商与 transport](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBTransport/Session/TransportSession.swift)
- [连接级 decoder](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBRendering/Framebuffer/AppleAdaptiveDCTDecoder.swift)；[C kernel 与来源注释](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBRenderingC/AppleDCTKernel.c)
- [正常 Type 33](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBTransport/Crypto/MacAuthenticator.swift)；[正常 Type 35](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBTransport/Crypto/SRPAuthenticator.swift)
- [构造数据测试](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Tests/rootshellVNCTests/rootshellVNCTests.swift)；[golden 与边界测试](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Tests/rootshellVNCTests/AppleDCTPerformanceTests.swift)
- [外部 capture 与诊断入口](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Tests/rootshellVNCTests/LiveStandardModeProbeTests.swift)；[性能测量范围](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Tools/Diagnostics/DCT_PERFORMANCE.md)
- [MIT LICENSE](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/LICENSE)；[README](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/README.md)；[整包依赖](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Package.swift)
