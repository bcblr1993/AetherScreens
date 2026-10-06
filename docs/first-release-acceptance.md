# 首版验收状态

## 2026-10-05：Mac mini 开发与验收路线

用户已删除 Tart 虚拟机，并明确将后续测试迁移到 `chenxu@192.168.50.226`。五分钟只读监控 `vm-aetherscreens-ui` 已删除。源码以 `/Users/chenxu/.codex/worktrees/screens-sync/mysterious-davinci` 为准；下方旧候选、VM、安装与测试记录均为历史，不能继承为本轮通过。

每轮构建/测试开始前必须清除上一轮已闭合的自有产物。`scripts/qa/rotate_owned_artifacts.py` 先绑定归属回执、文件清单和哈希，再默认只读审计，显式 apply 后核实目录消失；保留源码、Package.resolved、冻结 QA34 和小型摘要。固定本机新轮目录为 `build/qa-current`，本机构建产物预算 8 GiB。Mac mini 使用固定自有目录 `/Users/chenxu/aetherscreens-first-release-qa/current`，上一轮残留时拒绝启动新轮；专用工具留在同根的 `toolchain`，不修改系统工具。远端单轮预算 24 GiB、最少空闲空间 8 GiB。任何其他项目、系统缓存或未知产物都不属于清理范围。

依赖下载失败时可独立运行 `protocol-tests`：复制当前清单锁定的五个生产协议源码和原始 Curtain/DisplayLayout 两份 XCTest 文件，使用无第三方依赖的临时 target。它验证对应编码、状态与布局断言，单独报告实际计数；不能替代完整 Core、RFB transport、App 编译或 UI/实体验收，也不修改或跳过完整 Core 清单的断言。

本轮源码新增 Live Activity 生命周期及共享 Attributes、锁屏/Dynamic Island 双语界面，真实后台关闭输入和连接，临时 inactive/生物认证保持会话，前台不自动重连。普通单元测试改用私有偏好设置、内存凭据和注入剪贴板；真实 Keychain 与保存凭据的验收保持独立的明确 opt-in。以上代码尚须当前候选的编译及运行证据，不能用静态检查或模拟驱动代替系统展示。

已核对固定公开源码中的 Apple Adaptive DCT 渐进解码合同；此前“0x3f3 仅参考/跳过、不解码”的限制仍有效，解除限制的问题待用户答复，实施边界见 `docs/apple-adaptive-dct-implementation-boundary.md`。50% 服务器缩放不能替代它。当前编码协商仅声明已实现的解码器，遇到未实现的 Apple 编码不得猜解码。Curtain 已有独立的正常认证协议候选、能力与新 metadata 确认、关闭恢复及超时状态。未确认恢复的提示保留在独立于会话窗口的进程内记录中，电脑列表可重连原目标；新会话或旧请求的迟到回调不能清除后来的隐藏义务。这项记录不会跨 App 重启持久化，仍须当前候选的包测试、编译和解锁桌面的实体黑屏验收。公开正常客户端也未提供完整原生文件拖放合同；SFTP 和路径文本不替代它。真实 iCloud 多设备、Widget/Shortcuts 系统运行、实体输入和双屏/off-LAN/iPad 外屏/Pencil 仍须真实验收。

QA34 的冻结证据仍在 `build/shipping-owned-generator-path-qa/current-candidate-receipt.json`；其 native/Core/iOS/Mac/external/physical 未接受结果不随环境迁移而改变。本轮改动须建立新的清单与回执，测试数量从实际运行统计。QA 编号不是 App 版本；private compile build 29 仍未接受。全部功能与真实验收完成后才邀请用户首次正式审阅；审阅前不 commit/push/tag/publish/同步官网。

### QA39 的实际 Mac mini 结果

QA39 冻结 266 项输入。原样运行的 Curtain/DisplayLayout 协议子集实际执行 25 项，25 项通过、0 失败、0 跳过，耗时 14.496 秒；只接受对应协议断言，不接受完整 Core、恢复记录的 App 集成、画面或实体隐私结果。十个依赖按原 `Package.resolved` 的版本与提交准备完成，130 次 Git 命令均终态成功，完整输入哈希独立复核通过；这属于可复用的固定工具输入，不属于功能验收。

随后完整 Core 命令终态失败（Swift 退出码 1，12.265 秒，实际测试数 0），现有安全分类未捕获原因，原因仍未知。不能将依赖名大小写假设或旧失败归为本次原因。两轮已闭合的自有产物均实际清除，分别释放 177,922,048 和 190,779,392 字节；固定依赖、源码、工具和 QA34 冻结证据保留。

对应小型回执为 `build/qa-maintenance-evidence/protocol-tests-terminal.json`、`seed-inputs-terminal-verified.json`、`core-tests-terminal.json` 和 `remote-last-cleanup.json`。后续候选只按自己的实际运行接受结果；复用固定依赖时保留 QA39 制备来源和原锁文件绑定，不改写为新的运行通过。完整 Core、Mac/iOS 编译及所有真实验收仍未完成。

## 历史：候选 C 的 41/43 项 VM UI 记录

在12Pro尺寸的中英文界面，新增“保持触控板模式，连续缩小/放大后点击”断言复现2/2失败：缩小后画布仍336.381pt，适应大小应219.375pt；实际测试服务收到22次右键保持mask4和一次松开，录像箭头为红色。完整失败归档ad9c5284139e573ee050b7bbfc2a16cdd0d7539eb5a5d569433de34df1dc07e7，12pro-trackpad-pinch-cycles-two-failed-verified.json，不把旧的放大后单击通过当作完整缩放验收。

生产修改仅IOSRemoteInputView：缩放不等待双指双击失败，缩放期间抑制长按拖动与滚轮；双指pan可与pinch识别并行，pinch开始释放已开始的触摸拖动。新候选C的12Pro双语4项通过：两轮缩小/放大实际改变画布，每次点击保持坐标并只有一组按下/松开；原单击、双击、右/中键及长按拖动、Observe断言保留，双指全屏也通过。pinch-priority-12pro-four-qa-verified.json，独立完整归档3bf839ac70e89b3b1ab7ea7b6dc412fd72ccdcd30efd9574f8f72dc0aec57cea；8组缩放后点击事件独立校验，无右键/滚轮误发，截图白色已松开箭头已视觉核对。

C Release重新编译、严格签名和两机profile资格均通过，binary663e16b243f14766ef7096a5ba7a78a64de297faf88ed9d4cc92d6773670aec9；pinch-priority-device-release-build-receipt.json。12Pro与16ProMax安装终态0且系统成功回执bundleID已核对，pinch-priority-candidate-installations-verified.json。当前不宣称真实iOS27点击已修好，实际原大小/放大/缩小复测仍待用户回复；主机XCTest控制手机授权仍待答。 当前C真机QA App/Runner已构建并重新核对137项源、两份二进制和严格签名，两机profile资格通过；仅准备，未安装测试Runner或执行真机UI，pinch-priority-physical-qa-current-source-verified.json。

C新生产源清单pinch-priority-production-source-manifest.json；完整137冻结源pinch-priority-final-ios-vm-queue-source-manifest.json。独立队列pid见pinch-priority-final-ios-vm-queue-job.json，串行运行controlled26、library8、clipboard4、account2、url1、tablet2共43项。当前controlled26完整通过：26通过、0失败、0跳过，归档SHA256 45b3a3980e368af1fae0c25d700ae3309f0f21c5112b51647dbc6ae82c4baeb1，pinch-priority-full-controlled26-qa-verified.json；当前五批完整通过41/43：controlled26、library8、clipboard4、account2、url1均严格接受。最后tablet2在2026-10-02 14:31:07 UTC的VM重启期间中断，worker已消失且无终态回执，不能接受；原队列真实终态已停止，未盲重启。独立完整中断归档037e0da193fe3618792a9d07920fe9cdd73253b4cabb884d2fbaac55b763ad9a，pinch-priority-tablet-reboot-interrupted-verified.json。每批严格树/摘要/附件与独立归档通过后才接受，任何失败停止后续。实际worker和状态以current-full-controlled-active.json及现场进程为准。 现有macos27图形实例pid63797在运行但尚未登录桌面，已发出登录请求。自建loopback RFB/账号/SSH测试服务已恢复并只读探测，新SSH public metadata pinch-priority-after-reboot-ssh-fixture-metadata.json；旧port49418证据保留为历史。待桌面登录后，用新目录补跑tablet2并严格重验六批合计43个唯一用例，再运行run_pinch_priority_post_ios_gates.py完成当前单元321和Mac6；不得自动重复已经存在的worker。C Mac QA包已实际构建并严格签名，pinch-priority-current-mac-qa-build.json，尚未执行当前Mac6。此前B2的完整单元315通过6明确opt-in跳过、页面8通过、剪贴板4通过与12Pro8通过均保留为历史证据；C完整门禁尚未接受，完整单元和Mac6仍需核验，不混用旧候选完成计数。

实际192.168.50.226当前源只读兼容性及临时密码纠正各1项通过仍为原生产证据，不能替代本机Apple双屏或两手机真机验收。完整功能/Screens差距、IME/手感与用户审阅未完成，不发布/push/tag/同步官网。仅清理已闭合且独立哈希核对的自建VM产物；保留活动DerivedData、worker及用户数据。 本轮六批闭合自建结果及重复guest归档经独立核对后清理257314816字节（约245MiB），所有host归档与worker保留，closed-pinch-candidate-batches-cleanup-verified.json。当前12张截图（双语横屏输入、连续缩放后的白箭头、单屏crop、快速连接和剪贴板菜单等）已视觉检查，pinch-priority-current-ui-visual-reviewed.json；不将其当作全流程或物理设备验收。

## 当前：视图/键盘6项四通过两失败，中文2项聚焦诊断中

VM六项真实终态四通过、两失败：中英文横屏键盘、英文边缘跟随及视图导航通过；中文边缘跟随收到非零按键mask，中文视图导航未观察到平移标题。失败录像显示中文视图菜单仍在，标题定位并非已确认原因，不改松断言。原始完整失败证据独立哈希9b5f3f743c6ce661ebe4ed222369abe14bdb27ef9350a50ce569b3068d455651；immediate-tap-viewport-keyboard-six-failed-verified.json，不接受整个六项门禁，不增加当前8/43计数。

仅测试增加失败前完整事件（含连接编号）、截图及菜单关闭状态检查，生产未修改。中文失败2项聚焦诊断handle22892，viewport-follow-pan-diagnostic-two-driver.log，来源快照viewport-follow-pan-diagnostic-two-launch-source-manifest.json；等待同一worker实际终态，无盲重启。新独立Mac SSH服务已自建，public metadata sheet-ssh-fixture-metadata.json，待GUI空闲后跑修正Sheet定位的Mac6；旧自建pin非交互读取拒绝，未能核对故未删除。真实两手机点击和本机Apple双屏待用户反馈，尚未修复验收/全功能通过，不发布。

## 当前：横屏键盘、边缘跟随和视图导航双语6项在 VM 运行

最新生产候选未修改，已有iOS8/43通过及两手机安装证据；当前6项来自剩余用例，包含LandscapeKeyboard、RelativePointerViewportFollow、ViewportNavigation中英文。host81650、immediate-tap-viewport-keyboard-six-driver.log，同一GUIworker串行运行，不重复启动；真实终态通过和独立归档后才增加计数。macOS27 SSH确认框定位按实际Sheet修正，MacSSH残留自建pin独立读取-25293失败，未能核对公钥故未删除，Mac6验收仍未通过。真实iOS27手机点击和本机双屏仍待反馈，完整目标继续。

当前补充：第二次自建pin清理非交互读取返回-25293，未能核对公钥指纹，因此没有删除；先继续独立iOS回归，Mac SSH2/6仍待通过，不能当作已完成。

## 当前：Mac SSH 测试按 macOS 27 原生 Sheet 修正定位

立即单击生产候选未再修改：VM iOS 双语8项通过、两台手机新版已安装，iOS27真实点击与本机Apple双屏仍待反馈，不宣称真机问题解决。Mac6首轮4通过2失败，主要为测试滚动/可视区域问题；按表单实际可视区域修正后，SSH流程已完成密码输入、信任以及真实RFB画面。最新SSH2测试定位失败：确认框实际是原生Sheet（包含ssh-confirm-forget-trust按钮），脚本却查找Alert；英文用例因前一失败留下的自建fixture pin被保护检查拒绝。已修正为按明确按钮定位Sheet，并仅在已知fixture公钥指纹匹配后清理其自建pin，未触碰用户凭据或其他信任。

失败原始证据mac-visible-ssh-clean-two-qa全部保留，闭合归档独立核验SHA256 72434ef82ec12f6115e08873fe3cea32c4907a94bd6dcabf8e2fd0e4376f502a，VM仅清理这轮自建闭合构建/结果。接下来重测取消保留Keychain身份及明确忘记后删除，并再跑Mac6全套。全部功能通过及用户审阅前不发布、不推送、不tag、不同步官网。

## 当前：立即单击候选 VM8通过，已安装两台手机，实际效果待回复

候选8项双语终态全部通过：显示器1/2切换及真实收到坐标、放大前后触控和触控板点击、单击1次/双击2次、拖动、四边手势和双指全屏。无跳过、失败、运行告警、动画超时或GUI竞争。独立完整归档哈希093e8c3ac44102eee66bcdb23250d07892a326d0ad7a90a127696236e23ada81，immediate-tap-click-eight-verified.json。截图已检查，顶部显示器图标现在可见且布局无覆盖。

最新 Release 严格签名验证并安装到12Pro与16ProMax（两个安装命令均终态0，immediate-tap-click-ios-release-verified.json），尚未宣称解决真实iOS27的点击问题。已请用户重开、连接本机复测未放大/放大的单击双击，并反馈顶部菜单是否出现实际显示器1/2；菜单只有服务提供布局时才能真实列出两屏，实际Apple多屏仍未验收。

当前独立Mac QA App构建及严格签名通过，Mac6全套VM原生UI门禁启动，handle69847，日志immediate-tap-mac-six-driver.log。当前生产的iOS已接受8/43，其他门禁继续；全部功能验收及用户审阅前不发布、不推送、不tag、不同步官网。关闭并独立保存3组终态VM输出后清理69176746字节，保留活动结果和DerivedData；自建mini/iPad模拟器已关闭以节省资源，16ProMax仍保留。

## 当前：立即单击候选8项重测，上一版双击三次已被门禁拒绝

移除窗口边缘手势的单击失败依赖后，第一候选 VM6 结果为4通过/2失败，双语双击都收到3次点击、预期2次。失败证据归档 fa941b9a2ff543d3f184caf46753bfc420c3b6309be1e14c3648c6aa76b2c177，未安装该候选。

改为每次单指轻点由单击 recognizer 立即发送一次点击，删除额外补发点击的单指双击 recognizer；双指全屏识别保留。新候选8项守卫VM验证中，包含双语单屏选择/坐标、放大后触控板单击及原生手势、四边手势、双指全屏。handle76916，真实 worker 和结果路径见 current-full-controlled-active.json；Release 构建handle44087运行。完成并严格验证后再更新两台手机，不把模拟器26.5替代iOS27.0/27.0.1真机复验。

## 当前：两台 iOS 27 手机触控板点击问题待真机复验

用户补充：iPhone 12 Pro 也有触控板点击无反应，放大/缩小均存在；两台连接本机。devicectl 实测系统分别为 iOS27.0(24A437) 和27.0.1(24A446)。macos27 VM 当前 iOS 模拟器运行26.5，不能把其通过当成27真机无问题。

旧输入代码在 VM iPhone16ProMax 双语“选择显示器1/2、全屏和布局改变”和“放大后触控/触控板点击、拖动”4项全部通过，未复现真机问题。完整归档独立哈希 eff365266e408caf00eceafaf59989790bfcf3ebc02c47e8bb4e0e7d289d6767。

候选输入修改：单击不再等待四个窗口边缘 pan recognizer 全部失败，只保留普通 pan 与边缘 pan 的失败仲裁。该改动移除不必要的单击依赖，尚未证实解决用户真机问题。顶部显示器图标改白色，修复截图中不可见的问题。最新 Release 构建及严格签名检查通过，尚未安装。

当前守卫 VM UI6 为此候选验证双语显示器选择、放大后单击和完整原生手势、四边手势。真实活跃 handle46110，以 current-full-controlled-active.json 和同一 worker 终态为准。不发布、不推送、不打tag；通过此子门禁后仍需实际两台手机与本机Apple双屏验证。

## 当前：16 Pro Max 单击无反应与本机双屏选择

用户确认：16 Pro Max 箭头可移动，但点击无反应，且仅观察、平移视图都关闭。尚未复现、尚未宣称修复。已准备 192.168.50.26:6200 的受控双屏测试服务，等待用户手机单击，再检查实际收到的按下/松开事件；主机真机 XCTest 授权仍未回复。

本机 system_profiler 确认内建屏和 LG 4K 两块在线显示器。顶部机器信息现在直接打开显示器菜单，复用原菜单的真实布局选择与选中状态；本机 Apple 服务是否提供布局仍待验收，不按宽高比猜测两屏。

旧候选会话8项终态全部通过、归档独立哈希核验：451c1f20118b7885c992d2e1dc8470a4987e7f02fc95ca74e45ccfaa5c999965。新顶部入口已改变生产候选，旧 UI 结果只作历史证据。新候选 VM 守卫 UI6 运行中：中英文单屏选择、原生点击/拖动、横屏键盘。worker ih8c1wen，host handle26168，完整门禁仍未完成。Tailscale HTTP5 在 VM 聚焦通过，不能代替真实 API 账户导入。

# First release acceptance

Latest full-candidate progress: critical controlled6 and new tablet2 pass with
zero failures/skips/runtime warnings/animation timeouts/collisions. Tablet
settings screenshots are visually reviewed in both languages and independently
archived (SHA256 6b46455e8ceb01a3c94462dd172a84d5f651bd218885d3f923e8c03ba3f2839d).
The current guarded session8 batch is active: recovery, dictation preview,
disconnect actions and display selection in both languages; host handle56204,
guest worker `aetherscreens-gui-command.hbr87ksc`. Exact live command/state are
in `current-full-controlled-active.json`. Current VM UI coverage is 8/43;
complete Mac6, physical phones/IME/perceived smoothness and Screens parity
remain unaccepted. The explicit physical host UI question remains unanswered.
Current real Mac account password retry and Apple clipboard monitoring/manual
fetch/frame compatibility each pass as separate opt-in actual-target tests.
Latest signed iOS Release installs on both phones; this is preparation only.
About 39 MB of owned closed guest results/archive copies were removed after
independent host preservation. Active outputs, worker evidence and reusable
DerivedData were kept. No public release, push, tag or website sync occurred.

Latest current-candidate UI: controlled critical6/6 passes, zero skips/failures/
runtime warnings/animation timeouts/collisions. All screenshots and received
input attachments verify in `account-deadline-critical-six-verified.json` with
independent SHA256 399846615706ce7c8c17649f2cd921a48fdf37cf888fedc12692cae0d3f0c886.
Both languages' full-device landscape keyboard and pointer-edge captures were
visually reviewed. Remaining controlled20, clipboard4, library8, account2, URL1
and Mac6 are still required for this production candidate.
The current signed iOS Release app installs on both requested phones (strict
signature and install logs independently recorded in
`account-deadline-current-ios-signed-installations-verified.json`). Current real
Mac wrong-password/corrected-session acceptance passes without credential env
or temporary credential saving; see
`account-deadline-current-real-password-retry-verified.json`.
Two new actual iPad Pencil settings UI methods cover both languages, selection,
reopening and restoration; no hardware gesture simulation is claimed. They are
currently executing under host handle89955, with the live worker recorded in
`current-full-controlled-active.json`. No overlapping UI job may start.
The complete inventory now includes 46 declared methods: 43 VM plus three
physical. The driver now exports attachments before reporting an accepted gate,
including failed-run evidence. These changes are test-only; production is unchanged.

Current UI batch: bilingual landscape keyboard, relative-pointer viewport follow
and boundary gestures (six selected controlled cases), host handle66835, guest
worker `aetherscreens-gui-command.hfium7nr`. Exclusive UI guard enabled;
`current-full-controlled-active.json` identifies the live job. Not yet accepted.

## Latest candidate: authentication deadline fix (2026-10-02)

The previous layout candidate completed library8/8, bilingual account2/2 and
actual system URL1/1, all independently archived with terminal receipts. Those
results predate the latest RFB authentication change and remain historical.
The real TCP reproduction held account input for 21 seconds and exposed the
original 20-second timeout. The fix suspends that deadline during human input,
starts a fresh deadline after submission, and rejects stale prompt callbacks.
Silent/stalled peers still time out. Eleven host authentication tests pass;
`account-deadline-host-proof.json` records log hashes and matching VM sources.
The initial current full VM unit run completed 310 named cases: 303 passed,
six skipped and one failed. Exact terminal failure and independent hashes are
`account-deadline-vm-full-unit-failure-verified.json`. A focused synchronous
reproduction also failed at the same completion wait. Migrating that suspended
biometric/target-change scenario to native asynchronous Swift Testing preserves
all assertions and an additional 200 ms no-packet observation window; it passes
in 2.612 seconds without production changes. The complete rerun now passes:
308 XCTest + two Swift Testing cases = 310 named cases, 304 non-skipped passes,
six explicit environment skips, zero failures. Exact case identities, terminal
receipt and VM/host file hashes are in
`account-deadline-vm-full-unit-native-verified.json`. Final migrated assertions
use native #expect/#require and pass the focused VM test in 2.419 seconds; no
production change occurred after the full rerun. A new Mac QA Release app builds
and verifies its strict ad-hoc signature; Mac UI acceptance remains required.
Read `current-full-controlled-active.json` before starting another job.
All current candidate VM UI41, native Mac6, refreshed signed builds, physical
input/smoothness and complete Screens parity remain required. ApexTerm's actual
VM UI job ended and runtime inspection found no UI runner before this run.
No publication, push, tag or website synchronization is authorized by these
partial results. Physical host UI permission remains unanswered.

Candidate: 1.0.0 (build 1), Apple silicon macOS 14+.

## Current candidate acceptance (2026-10-02)

The earlier notarized package and 73-test record below predate current changes.
They do not accept the current installed candidate or authorize publication.
Current authoritative coverage is maintained in `screens-alignment-audit.md` and
`build/ssh-coordinator-macos-vm-acceptance/gui-session-regression/`:

- Isolated VM unit suite: 305 named cases, 299 non-skipped passes, six explicit
  live-environment skips, zero failures. Five skipped gates now have separate
  live evidence (Bonjour, Apple rich clipboard, temporary password retry and
  two actual Tailscale paths); controlled actual-desktop pointer remains open.
- Previous candidate controlled26/26 and clipboard4/4 pass independently.
  Library8 completed six passes and two top-toolbar overlap failures. The current
  layout fix passes both affected bilingual cases and complete library8/8.
  Prior results do not accept the changed candidate. Additional account/URL3 and native Mac6 remain open.
  All 44 declared iOS methods are tracked in `ios-ui-complete-inventory.json`.
- Current signed Release app is installed on both requested iPhones. Real-phone
  input, Chinese composition and smooth interaction acceptance remain open.
  Host command-line physical XCTest permission has not been granted.
- Screens parity remains incomplete, including actual file drag/drop, curtain
  privacy, cross-device storage, adaptive quality and iPad external-display
  routing. Synthetic transport assertions do not accept hardware behavior.
- Final signed/notarized package, CI/public downloads and website verification
  must run after complete functionality and user review. No release occurred.

## Historical verification on 2026-10-01

- Swift unit suite: 73 tests, zero failures; live tests skip without an explicit target.
- Real macOS Screen Sharing server: RFB 3.889 banner, VNC authentication, 3840 × 2160 framebuffer, 60 seconds connected, clean intentional disconnect.
- iOS signed device build: iPhone 12 Pro.
- iPhone simulator primary UI: add computer, Tailscale settings, diagnostic logs, edit computer. Screenshots reviewed.
- macOS Developer ID signature, Apple notarization, stapled ticket, DMG volume name and contents (app plus Applications link), arm64 executable and version metadata.
- Website source build, tests and internal link verification.

## Required before publication

- Recheck the final installed candidate after signing changes. Earlier installed GUI account sessions, native clicking, typing, dragging, zoom and wheel delivery passed; protocol tests do not replace the final installed-app check.
- Physical iPhone session UI acceptance requires an unlocked paired device. Device build success and simulator UI are recorded separately.
- Recheck final candidate signature, notarization, mounted DMG and checksums after code changes.
- Push scoped code, wait for CI, publish matching release assets, sync website, verify public download and version page.

## Distribution scope

The public download is macOS only. iOS is available as source for a signed Xcode installation; there is no App Store / TestFlight release in this version. VNC password and Mac account (Apple ARD type 30) authentication are implemented. Username selects Mac account authentication; an empty username selects VNC. Lock Remote Mac sends the system shortcut and is not a curtain privacy feature.

Keep private addresses, passwords and real desktop screenshots out of published evidence. Do not mark blocked checks as passed.

## Additional functional gate (2026-10-01)

See `functional-qa.md` for the controlled remote event fixture. Account authentication plus real click and wheel event delivery passed after fixing Apple cursor-position handling. GUI Chinese text drawer delivery passed. GUI Paste Text insertion passed with Chinese clipboard text. Lock/password input/desktop restoration passed in the installed GUI. Direct physical IME and physical iPhone acceptance are still being verified; the draft release must not be published based only on handshake success.

### Native Quick Connect Widgets (QA31 source, runtime acceptance pending)

The iOS app and the internal native macOS QA host now embed a real WidgetKit
extension. The extension uses AppIntentConfiguration to select one saved
computer for a small, medium or large widget. A separate lightweight package
reads only an explicitly enabled UUID and display alias, with exact schema,
duplicate-key, count and byte validation. No device library, credentials,
network session or clipboard is initialized in the extension.

The editor has a separate Show in Widgets opt-in. The containing app writes an
atomic App Group projection and reloads the widget timeline after a successful
change. Missing files and unavailable containers/failed reads are distinct for
foreground edits. Failed withdrawal retains the previous opt-in and reports
the failure. Unchanged widget settings are not republished by unrelated edits.
The internal Mac QA host uses the private widgetqa App Group; unsigned build
artifacts do not establish the entitlement or container's runtime availability.

Tapping the widget sends only a reserved UUID URL to the foreground app.
Cold URLs remain in memory until the app is active. A separate widget queue
rechecks current widget opt-in and one verified saved-record snapshot when
claiming, defers during modal editing or an unavailable saved library, drops
deleted records, and checks retained sessions before looking up a password.
Stale timeline configuration never supplies a cached alias or a fallback computer.

Still required: valid signed App Group/profile rights, true host-to-extension
container reads and withdrawals, widget gallery discovery, actual system
configuration/refresh, language and appearance/size rendering, cold/warm tap
routing with modal and retained sessions, and physical-device acceptance. The
manual macOS release packager is a separate pending packaging gate; no public
release, signing, installation or system-widget pass follows from compilation.
The full Screens parity and physical/cloud/offLAN/iPad requirements remain open.

Apple reference: https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget
