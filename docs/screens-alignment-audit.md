## 当前：新候选 C 的 41/43 项 VM UI 已通过；最后两项被 VM 重启中断，待登录后续测

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

# Screens alignment and full acceptance audit

Tailscale client coverage addition: five new native Swift Testing cases pass
on the host against the production URLSession client with controlled responses.
They inspect the official authenticated GET request and decoded device data,
401/403 recovery, HTTP503 and malformed JSON recovery, network interruption
propagation/recovery, and a valid empty list. All credentials are synthetic.
Production code is unchanged. The same test source is hash-matched in the VM,
but execution is queued until the active eight-case UI batch ends.
`tailscale-http-host-five-verified.json` records scope and hashes; this does not
accept an actual Tailnet API import with a real access token. API reference:
[Tailscale API](https://tailscale.com/docs/reference/tailscale-api).

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

Audit date: 2026-10-02. Existing notarized candidate: `2eea898`. Reference: [Screens 5 official feature index](https://help.edovia.com/en/screens-5/features/).
This is a completion checklist, not a claim of parity. Unit tests, simulator
screenshots and signed builds do not replace physical input/gesture acceptance.
The release remains a draft until the user has reviewed the completed acceptance.

Current fixed-candidate library suite passes completely: 8/8, no skips,
failures, runtime warnings, animation timeouts or UI collision. Exact command,
test tree, terminal receipt and every attachment verify in
`top-toolbar-layout-library-eight-verified.json`; the independently matched
VM/host archive hash is
`b20bb435a7cb413bb5090bc879e49f6bf3f9836b016ecfce04a15690c458529f`.
The additional account and system-URL suites are now explicit driver inventories,
bringing VM coverage scope to 41 methods plus three physical methods (all 44).
Six headless driver checks verify one-time URL delivery, missing trigger,
failed delivery/test-process and argument rejection; these do not accept app UI.
The loopback-only ARD-offer fixture refuses authentication and records milestones,
never payloads. Its handshake/cancellation/refusal and listener constraints pass.
The real Mac independently offers both ARD and VNC, so an empty account naturally
selects VNC; no real sharing configuration was changed to force another branch.
The controlled account-prompt pair is running under handle99201, worker
`aetherscreens-gui-command.x5gphj1_`, output `top-toolbar-account-two-qa`.
Only test infrastructure and account-test port selection changed after library
acceptance; production remains the same repaired top-toolbar candidate.
Current-source controlled26/clipboard4/URL1/Mac6, new signed app installations,
physical devices and Screens gaps remain open. Host phone UI permission remains
unanswered. No release occurred.

Earlier candidate changed after a verified library failure. The guarded library
suite completed 6 passed / 2 failed, zero skips/runtime warnings/animation
timeouts, no UI collision. `guarded-library-eight-failure-verified.json` preserves
its complete terminal result and independently matched archive SHA256
`d52f1dba08bd1844b05e9383d3c27ab33e6b0e1fe2e9056973530ed7093b57ce`.
Rendered screenshots prove the top keyboard toolbar covered the session header:
its menu could not reopen keyboard customization in either language. The top
safe-area content now uses an explicit VStack, with UI regression assertions
that toolbar and session-menu hit regions do not overlap. Both affected cases now pass completely (2/2, zero skips/failures/warnings/
animation timeouts, no collision). The independent archive hash is
`fb4a4699f79ff6bd10c8fcdc8719caee8fa166bc204b253e2ed0a9dc62b1b022`;
`top-toolbar-layout-two-verified.json` accepts these selected cases only.
Rendered screenshots confirm the header is visible above the top keyboard row.
The complete fixed-candidate library8 suite is now running under handle2275,
worker `aetherscreens-gui-command.pd2fd2vd`, output
`top-toolbar-layout-library-eight-qa`. Its immutable launch source manifest is
`top-toolbar-layout-library-launch-source-manifest.json`. Host/VM layout and test hashes match
(`top-toolbar-layout-source-verified.json`); the prior source manifest is retained.
The earlier controlled26/26 and clipboard4/4 below predate this production change;
they remain historical evidence and cannot accept this new candidate. New signed
Mac/iOS builds and final whole-candidate regression remain required.
A complete declaration audit also finds 44 iOS UI test methods: controlled26,
clipboard4, library8, plus three additional VM account-prompt/URL gates and three
physical gates. `ios-ui-complete-inventory.json` retains all 44; none is omitted.
Physical host UI permission remains unanswered. No release occurred.

Earlier complete controlled-session gate: 26/26 unique cases pass across three
isolated guarded batches (6 + 8 + 12). `scripts/qa/verify_controlled_vm_batches.py`
checks archived command inventories, authoritative test trees, zero warnings/
skips/failures/animation timeouts, terminal worker receipts, absence of collision
and every exported attachment. `controlled-26-verified.json` records the complete
inventory and archive hashes. Negative checks reject missing, duplicate and
interrupted historical evidence (`controlled-coverage-negative-verified.json`).
The final twelve archive is independently SHA256 verified against the VM:
`f5645e2bd65c027a34d74abbd52cdda5a5650fc2f341a92465d7fd27f45b1979`.
Current production/test source hashes match the accepted manifest on host and VM
(`guarded-controlled-current-source-verified.json`). The Chinese restored-session
screenshot was rendered and reviewed. This accepts controlled session flows only.
The bilingual clipboard suite now passes 4/4, with zero warnings/skips/failures/
animation timeouts and no collision. `clipboard-four-verified.json` accepts the
exact inventory; independent remote/local SHA256 is
`547598c817ec81e4bf1b516afecbb59e9a5757fb1b1a610eef0f85b5f5cfc1cd`.
Chinese Observe menu and English too-large alert screenshots were rendered and
reviewed. These cover controlled Apple/shared clipboard UI, not physical paste
permissions, rich-content rendering or multi-item file transfer.
Library8 is running under handle26089, worker `aetherscreens-gui-command.02ank9gl`,
output `guarded-library-eight-qa`. Mac6, physical devices and the Screens matrix remain open;
physical host UI authorization is unanswered. No release occurred.

Earlier guarded VM status: 14 of the unchanged 26 controlled cases are independently
accepted: critical-six 6/6 plus bilingual recovery/dictation-preview/disconnect/
display-selection 8/8. The latter result has zero skips, failures, runtime warnings
or animation timeouts, worker exit0 and no UI collision; all 36 attachments and
terminal records are preserved in `guarded-session-flows-eight-verified.json`.
Archive SHA256: `37bc02177ef967996bf7945dbaf9e155c43eb3c567c7e1aa7646cf9c93d1ad52`.
Rendered Chinese dictation preview and English selected-display screenshots were
reviewed. This does not accept microphone recognition or actual multi-monitor hardware.
The remaining 12 cases are now running with `--exclusive-ui`, host handle66973,
worker `aetherscreens-gui-command.fsb3zw5g`, output `guarded-remaining-twelve-qa`.
The prior VM runner is terminal and no foreign UI runner is present at launch.
Exact coverage remains recorded in `guarded-controlled-matrix.json`; clipboard4,
library8, Mac6, both physical devices and Screens gaps remain open. Host physical
XCTest authorization is still pending; no physical UI execution occurred.
No release, tag, push or website synchronization has occurred.

Current reference requirements rechecked against the official Screens feature
index on 2026-10-02. [Curtain Mode](https://help.edovia.com/en-GB/screens-5/features/curtain-mode)
requires Remote Management; normal Screen Sharing does not provide it. Acceptance
must prove a hidden physical display while remote desktop control remains available.
[Adaptive Quality and Compression](https://help.edovia.com/en/screens-5/features/images-quality)
requires progressive detail plus separately configurable server-side half-size
frames; FPS counters or generic RFB compression do not prove either behavior.
[Data and credentials synchronization](https://help.edovia.com/en/screens-5/features/sync)
includes selectable iCloud/local connection storage and encrypted Keychain sync.
[iPhone file transfer](https://help.edovia.com/en/screens-5/features/file-transfers-iphone)
requires multi-file drop upload, remote drag download target, verified downloaded
files and transfer recovery; ordinary clipboard or SFTP alone is insufficient.
[External display support](https://help.edovia.com/en/screens-5/features/airplay-and-external-displays-support)
documents system mirroring for iPhone and optional remote-desktop mirroring
for iPad when its window is on the built-in display. Actual system AirPlay and
iPad routing still need acceptance. The current official product page lists
iOS/iPadOS17.6, macOS14.6 and visionOS26.0 as client minimums; these are separate
from the two physical test phones running iOS27.
[Official product requirements](https://edovia.com/en/screens/).

The [official Screens5.7 release article](https://blog.edovia.com/en/screens-57-now-available)
also specifies iOS/iPadOS26 background-task file transfer with Live Activity
progress, a one-second hover lock for the download drop target, move-away
cancellation and tap dismissal. Mac drag-and-drop includes clipboard text,
images and URLs. These remain unimplemented and unaccepted in this candidate.
The existing RFB clipboard codecs and SSH tunnel do not prove the file-transfer
workflow or background recovery; retain these in the complete parity gate.
These requirements remain in the original completion scope.

Historical stage observations (later records supersede earlier observations):
the isolated current-source full VM unit run exits zero. It includes 304
XCTest cases and one Swift Testing case: 299 non-skipped passes, six explicit
live-environment skips, zero failures. Guest stdout/stderr, command, exit result
and terminal LaunchAgent state were independently SHA256 verified in
`gui-session-regression/native-async-isolated-verified.json`. The skipped gates
require an actual LAN Bonjour target, Apple clipboard compatibility, failed
live password/retry, controlled live pointer coordinates, and two live
Tailscale checks; none counts as accepted. The earlier concurrent full run
failed two bounded waits and remains retained.

The asynchronous clipboard test now uses native Swift Testing rather than
XCTest's crashing async invocation bridge. It retains all four real TCP
scenarios (paste, observe, hidden session, changed clipboard), continuation
readiness and exact Unicode packet checks. The complete isolated regression
passes without the previous SIGSEGV; this does not establish an upstream
compiler defect. The isolated focused VM run also passes ten consecutive repetitions, exercising
all four real TCP scenarios each time (40 scenario executions). Its command,
logs, zero exit and terminal state are independently hashed in
`gui-session-regression/native-async-repeat10-verified.json`.

The two actual bilingual iOS landscape/keyboard cases pass their keyboard
focus, viewport bounds and exact received Unicode assertions. Another project's
UI runner started during execution, and the exported app screenshots show a
rotation/cropping anomaly with a large black area. Rendered landscape and
smooth interaction remain unaccepted. Additional full-device screenshots are
prepared to distinguish app cropping from the actual screen on the next
exclusive run. Evidence is retained in `vm-ios-landscape-keyboard-verified.json`
and `vm-ios-landscape-keyboard-screenshots/`. The current signed iOS build is
installed on both requested phones; actual two-phone interaction remains open.

The user requested waiting for ApexTerm to finish. Gaps between that project's
test runners do not establish exclusive GUI availability: wait for its task to
finish or explicitly report no further VM UI work before starting this project's
UI suite. Do not notify or stop that task. Pending Mac six-case, rendered iOS,
live environment, physical-device and Screens feature gates prevent release.

Two additional bilingual relative-pointer viewport cases are prepared and
iOS SDK typechecked (controlled inventory now 26). They use actual received
RFB coordinates at a fixed touch point before and after trackpad movement to
both desktop edges, proving automatic viewport movement rather than manual Pan
View alone. They require zero click/held-button packets during pointer motion
and retain edge screenshots. They have not executed; source hashes match the
queued VM copies in `pointer-follow-ui-prepared.json`.

Current-source real 192.168.50.226 gates also pass separately: rich Apple
clipboard with server-driven framebuffer updates (one executed case, no skip)
and application Bonjour resolution (one executed case, no skip). Rich transfer
checks PNG/URL/RTF/HTML/UTF-8, native restoration and removal of the owned remote
helper; credentials remain in noninteractive saved Keychain storage. Bonjour
resolves the advertised service to `chenxus-Mac-mini.local.:5900`, independently
matching dns-sd. Evidence: `current-viewport-rich-clipboard-live.verification.json`
and `current-live-bonjour-app.verified.json`. These satisfy two separately
opted-in live gates omitted by the default full suite; they do not imply
physical iPhone permissions, actual Tailscale routing or other skipped gates.

Exclusive four-case iOS VM gate: both languages pass landscape keyboard and
relative pointer edge following (4/4, zero skips, warnings or animation timeouts,
exact inventory). Sampled process observations contain only AetherScreens UI
runners. Independently hashed archive: `viewport-exclusive-four-verified.json`.
Full-device screenshots show complete landscape UI and software keyboard; the
black/truncated app.screenshot capture is independently reproduced alongside a
correct full-device capture, so that capture cannot validate landscape rendering.
Full-device captures were visually reviewed in both languages, including the
small arrow cursor and exposed text-field close control. Native Chinese IME
composition and physical responsiveness still require phone acceptance. The
review also finds white root safe-area borders, so a narrow dark-background
fix is prepared; this subsequent production change needs fresh rendered UI
verification before the current candidate is accepted.

The safe-area background repair and device-wide screenshot helper are now in
the current source, independently matched to VM copies. The complete 26-case
controlled gate is running under owned GUI worker `aetherscreens-gui-command.x6y3xhta`
with result directory `build/viewport-background-full-controlled-qa`. Its
completion remains unproven; never restart solely after an observation timeout.
Host headless Mac build is also running. Driver handles and next-read locations
are retained in `current-full-controlled-active.json`. Do not run another GUI
suite concurrently. After this gate closes, preserve/hash the exact results,
review full-device safe-area screenshots, then continue clipboard/library and
Mac UI gates; new production build/device installation remains necessary.

Current real Mac temporary-password retry passes separately (one case,
zero failures/skips). The live test can now read a matching saved account
credential noninteractively; the verified run explicitly removes the password
environment variable. It proves rejection of one deliberately incorrect password,
successful correction with actual framebuffer reception, and no credential save
for the temporary computer. Evidence: `current-live-temporary-password-retry-verified.json`.
This test-source-only change is on the host; the active VM UI source remains
frozen. Three default live skips now have separate current live evidence
(clipboard, Bonjour, retry); actual Tailscale and controlled real-pointer
acceptance remain distinct open gates. Current headless Mac build and strict
QA-bundle signature verification also pass (`current-background-mac-qa-binary.json`),
but the queued native Mac UI suite has not executed.

Actual Tailscale path gates now pass on `100.64.0.3`: the RFB/security
handshake and a saved-credential full session both execute without skips.
The full session receives the real 3840×2160 framebuffer, remains connected
for 60 seconds and intentionally disconnects without failure. The target is
independently verified as the online Mac mini peer by CLI status; system route
uses `utun4`. Credentials remain in saved Keychain storage with the password
environment variable explicitly removed. Evidence:
`current-real-tailnet-handshake-verified.json`,
`current-real-tailnet-full-session-verified.json`, and
`current-tailnet-readiness.json`. CLI reference: https://tailscale.com/docs/reference/tailscale-cli?tab=macos.
Five of the default six environment skips now have separate current live
evidence; the remaining controlled real-pointer gate and all physical
interaction/Screens gaps remain open. Seven of 26 active UI cases have passed
so far, including the repaired Chinese landscape; the full gate is still running.

The remaining live controlled-pointer gate cannot safely execute yet:
a fresh read of the target fixture page-state reports focused=false,
visible=false and a stale heartbeat. No pointer input was sent into an
unconfirmed desktop target. Evidence: `current-controlled-real-pointer-readiness.json`.
The real Tailscale full-session gate passed in 63.758 seconds; this proves
connection/frame stability, not current foreground pointer/IME interaction.

Latest full controlled gate is terminal and NOT accepted: another ApexTerm
StoreSandbox runner (PID21384) began actual UI execution during the 26-case
run. Only the owned AetherScreens xcodebuild PID19626 was interrupted (SIGINT);
other-project processes were untouched. Authoritative result: nine passes, one
case canceled, 16 unexecuted, processExit73; owned GUI worker exits1. Complete
xcresult, logs, terminal worker state and screenshots are independently hashed
in `full-controlled-interrupted-verified.json`. Closed guest result/archive
copies were removed only after preservation (`full-controlled-interrupted-closed-cleanup.json`);
reusable DerivedData, source and screenshots remain. Chinese full-device
landscape screenshots from before the overlap confirm the safe-area white
border fix; this narrow visual proof does not accept the interrupted suite.

ApexTerm started a new release-validation turn after its prior submission
report. From now on, wait for its current task/turn to be terminal and recheck
actual GUI processes before retrying; a progress statement promising later UI
work or a brief runner gap is insufficient. Do not message or stop that task.
Current gate handle record is terminal (`current-full-controlled-active.json`),
so retry only after availability, with a fresh output path. Clipboard4, library8,
Mac6, full controlled26 and the physical/Screens matrix remain pending.

The current safe-area-fixed iOS Release QA candidate builds successfully,
passes strict deep signature verification, and installs successfully on both
iPhone12Pro and iPhone16ProMax. Independent binary/source/install-log hashes
are recorded in `ios-safe-area-current-signed-verification.json`. This
supersedes the earlier installed build for these fixes; installation remains
separate from real-phone input/IME/responsiveness acceptance. No public release,
tag, push or website synchronization occurred.

Physical test preparation: the current device build-for-testing succeeds and
strict signatures of both the test app and XCTest runner verify. Plan/binary
hashes are recorded in `current-signed-physical-qa-ready.json`. Two owned LAN
fixtures are live on host 192.168.50.26, one per requested phone, with distinct
RFB/display/clipboard/HTTP ports and separately verified empty event streams
(`physical-fixture-jobs.json`). No physical UI execution has started.

The current iPhone12Pro lock check reports no passcode required, while
iPhone16ProMax requires unlocking. Fresh guest CoreDevice inventory still
contains no physical devices (`current-two-phone-readiness.json`). Because the
user requires VM UI automation, an asynchronous clarification asks whether
headless host XCTest may control only the two physical phones. This is PENDING,
not authorization. Do not run physical host XCTest without an explicit user
answer; elapsed time is not permission. Mac/simulator UI remains VM-only.
ApexTerm is still executing its release CI follow-up, so no VM GUI test was
restarted during this preparation. The full product acceptance remains open.

Current guarded VM execution supersedes the earlier whole-thread-idle
waiting rule: the prior ApexTerm VM UI process is terminal and actual guest
process checks are clear. Its current remote Apple/CI polling is not a VM UI
job. The user requested waiting for that UI test to finish, not indefinitely
waiting for external Apple review. The GUI helper now refuses any preexisting
UI runner and monitors for foreign runners throughout the owned command. It
interrupts only descendant xcodebuild processes, keeps the driver alive to
export results, and forces gate failure on collision even if assertions pass.
Native Mac preflight now also recognizes simulator runners. VM safety probes
verify preexisting refusal, late collision, preservation of the foreign stub
and preservation of driver exports (`ui-guard-verified.json`); these are helper
safety checks, not product UI acceptance.

The unchanged full controlled inventory remains exactly 26 cases. The guarded
critical six-case batch is running at `viewport-guarded-critical-six-qa`, worker
`aetherscreens-gui-command.29n2qcev`, host handle62649. It covers both languages
of landscape typing, relative pointer following and screen boundary gestures.
The remaining 20 cases are explicitly retained in `guarded-controlled-matrix.json`,
followed by clipboard4/library8/Mac6 and physical/Screens gates. An incomplete
batch or a collided result cannot accept the whole inventory. Five critical
cases have passed so far; completion remains unproven. Physical host UI
permission remains pending and no phone UI command has executed.

Guarded critical-six gate now passes completely (6/6, zero skips/failures,
runtime warnings or animation timeouts); worker exit0, terminal state, absence
of collision and archive hashes independently verify in
`guarded-critical-six-verified.json`. This accepts both languages of the
latest landscape typing, pointer edge following and screen boundary assertions,
not all 26 controlled cases or physical hardware. The next eight unchanged
cases (recovery/dictation preview/disconnect/display selection, both languages)
are running under handle28624; `guarded-controlled-matrix.json` and
`current-full-controlled-active.json` track the live worker and complete
inventory. Continue that actual handle rather than launching another suite.
The remaining 12 controlled cases, clipboard4/library8/Mac6 and physical/Screens
requirements stay open. The pending host-phone UI question is unanswered.

Historical observations follow; earlier locked-Keychain, zero-UI execution and
clipboard-crash statements are superseded where the current evidence above and
the GUI-session correction below explicitly resolve them.

Security audit-session correction (2026-10-02): after the user unlocked
the VM login Keychain, an SSH process still reported flags2 and synthetic
SecItemAdd returned -25308. The identical probe launched in `gui/501` reports
flags7 and successful actual add/read/match/delete. The Keychain was unlocked;
the SSH Security audit session was the incorrect readiness context. Earlier
claims that the user had not unlocked the Keychain are superseded. The UI
runner now launches Keychain preflight, build, discovery and XCTest through
an owned temporary LaunchAgent in the logged-in GUI session. It preserves
command evidence and unregisters only after the worker is terminal, without
changing storage policy, entering a password or skipping real-storage tests.
Same-source actual VM focused regression executed 64 cases: all passed, no
failures or skips. Guest stdout, stderr, process result and terminal launchd
state were independently SHA256 checked. The earlier 58/64 failed gate is
superseded for these focused cases, not for full acceptance.
Native UI discovery still failed with automation-mode timeout, zero actual UI
cases executed. Its independently hashed evidence was preserved and closed
guest DerivedData/app/archive copies removed (205,369,344 allocated bytes).
A GUI-session automation-mode preflight now refuses before creating a test
workspace; the actual disabled-mode smoke exits2. It does not bypass system
authentication or turn discovery success into UI acceptance.
Full VM regression exposed a SIGSEGV in the asynchronous clipboard XCTest.
The invocation-wrapper experiments did not hold up under full regression and
were removed. The retained test change publishes read readiness only after its
actual continuation is installed; all original async steps and assertions stay.
The latest completed Core target executed 259 cases with zero failures and six
explicit environment skips. The full gate still failed: the SSH target found a
real unresolved NIO promise when cancellation closed the probe channel before
handler installation. The production fix now creates the promise on the event
loop only after checking an active channel and resolves setup failures. Five
host probe cases pass, including 20 repeated early socket cancellations. A
second analogous authentication promise leak was found in VM full regression
and fixed, including closed-channel forwarding setup. Actual current-source
VM focused regression passes all 41 SSH cases plus five viewport cases with
zero failures/skips, including repeated early authentication cancellations.
The clipboard XCTest still SIGSEGVs in swift_task_localValuePopImpl during
full regression; that failed gate and exact guest crash reports are retained.
Automation mode now reports ENABLED. Actual UI runner process inspection finds
another project's active UI suite in the shared VM, so AetherScreens refuses to
start competing UI tests. No discovery-only result is counted as acceptance.

New physical-user feedback (2026-10-02), release-blocking until rendered and
physical acceptance: the large disc hides click targets, zoomed pointer motion
does not reveal desktop edges, landscape controls waste/overlap desktop space,
and keyboard entry is inconvenient. The first fix changes the cursor to a
constant-size arrow with its tip at the exact pointer coordinate, follows a
relative trackpad pointer inside a 28-point viewport margin with desktop bounds,
reserves control/keyboard space through native safe-area insets, respects the
software keyboard safe area in fullscreen, and focuses the text field when the
Type action opens it. Absolute mouse/Pencil/touch mapping stays anchored. Five
host and actual VM viewport cases pass (fit, both edges, stable margin,
landscape/keyboard, cropped display, invalid geometry). iOS Debug build passes.
Two bilingual landscape/software-keyboard UI cases were added to the controlled
release-gate inventory, asserting real keyboard focus, non-overlap and exact
received Unicode key events; these have not yet executed. Screenshots and both
requested physical iPhones remain open. The current shared VM has another
project's UI runner; its devices list contains only simulators, while both
requested physical iPhones remain paired on the host. The current Release build
passes strict deep signature verification and installs successfully on both the
iPhone 12 Pro and iPhone 16 Pro Max. Installation is not physical acceptance.
The full iOS UI-test source typechecks against the actual iOS SDK, but the new
landscape/keyboard cases have not executed. After the competing VM suite ended,
a fresh GUI-session native preflight reports Automation Mode disabled again.
The default runner correctly refuses; an explicit authenticated-request option
now allows XCTest's normal VM authorization dialog, with no configuration that
bypasses user authentication. This request is pending user interaction.

Evidence: `build/ssh-coordinator-macos-vm-acceptance/gui-session-regression/`.
The complete rendered UI, physical-device and Screens acceptance remain open.

Latest native GUI gate (2026-10-02): the isolated initial bilingual Mac UI
suite actually passes two of two cases with no skips or runtime warnings. Its
hash-verified closed artifacts were cleaned (268,926,976 allocated bytes),
retaining source and evidence. The subsequent all-six-case gate fails five cases
(one passed, none skipped). During this run another ApexTerm UI runner started;
process overlap, exact failed results, UI hierarchy and hash-verified xcresult
are retained. Foreground contention is a possible contributor, not a confirmed
explanation or an exemption. Both failed and passed results remain in the audit.
The user explicitly requested waiting for ApexTerm to finish; no message or
termination of that project is authorized or performed. A thread follow-up
(vm-aetherscreens-ui) checks every five minutes and resumes only when the
current ApexTerm UI gate has finished and macos27 is idle; unchanged state is
quiet. This does not count pending GUI or physical-device cases as passed. iOS VM build-for-testing
of the prepared two-case keyboard suite passes; execution waits for exclusive
UI availability. The subsequent compact landscape keyboard layout temporarily
hides the header and shortcut rows while typing to preserve usable desktop
height, restoring them when text entry closes. Its current signed iOS Release
build passes; it still needs the queued rendered/native-input acceptance.

Graphical VM recovery check (2026-10-02): the previous experimental VNC
process terminated while opening its connection. After confirming Tart reported
`stopped`, macos27 was started with its native graphical window and confirmed
`running`. Fresh guest probes find no active xcodebuild, UI-test runner or
coreautha process; CGSessionCopyCurrentDictionary returns nil (no logged-in
console), and default Keychain status remains flags2. The earlier live process
observations below are historical, not current. Native acceptance still requires
manual VM login and login-Keychain unlock; no tests were counted as passed.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/graphical-start-readiness.json`.

Environment recovery gate (2026-10-02): native SSH/all UI suites now query the
actual default file-based Keychain status before creating a workspace or copying
and building an app. The real locked-VM smoke test exits2 with flags2 and creates
no test workspace. This is a failed readiness gate, never a passed acceptance or
an exemption from actual saved-credential assertions. Python syntax and diff checks
pass. Evidence: `ssh-keychain-preflight.log` and
`ssh-keychain-preflight-verification.json`.
Both requested iPhones are now paired/available on the host; however macos27's
CoreDevice inventory still has no physical devices and direct DNS-identifier
lookups for both return CoreDeviceError1000 (device not found). Do not reuse the
older statement that iPhone16 is unavailable on the host. Current native VM
system authentication remains blocked, its default Keychain remains locked and
the existing user recovery request has not been answered. Authentication windows
and another project's active VM lease were preserved. Native real-storage and
UI validation must wait for environment recovery. The full objective is not
complete; further protocol-only passing tests cannot accept the native, two-phone
or Screens parity gates. Remaining file-transfer, synchronization, external-display,
privacy/adaptive-quality gaps and the full hardware/UI matrix remain explicitly
open; restoration of the environment alone is not release approval.
Blocker audit: `build/ssh-coordinator-macos-vm-acceptance/current-blocker-audit.json`.

Bounded asynchronous key-file import and actual VM regression (2026-10-02):
key-file reading now runs off the UI thread with balanced security-scoped access
and a stream limit of 65,537 bytes (the extra byte detects an oversized file).
It rejects nonregular/empty/missing files, independent of mutable size metadata.
The SSH section shows native progress and prevents repeated edits while loading;
dismissal invalidates the result before it can update the draft. Replacement
validation retains the previous selection on failure. Actual file tests cover
65,536-byte acceptance, a 2 MiB oversized file, empty/missing files and directories.
Current host focused regression: 39 SSH + 25 Core storage/form tests passed, no
failures/skips. Current Mac app build, iOS Release build and strict iOS signature
verification pass. Native import UI remains pending.
The same frozen sources were independently SHA256 checked and tested inside
macos27. Actual VM gate is FAILED: 64 cases executed, 58 passed, 6 failed. Every
failed case needs real Keychain writing or legacy-credential migration; SSH writes
return errSecInteractionNotAllowed (-25308). Read-only SecKeychainGetStatus returns
success with flags=2: readable, but neither unlocked nor writable according to the
installed SDK constants. The GUI console alone being unlocked is insufficient.
Coreautha PID8701 has an on-screen authentication window. This SSH process has
neither AX nor screen-read permission; no authentication window was manipulated,
no password was transmitted and no Keychain permissions/storage policy changed.
The existing request for manual VM authentication remains pending. Do not replace
these failed actual-storage tests with skips or an in-memory backend to pass.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/current-vm-headless/` contains
source-manifest, independently hashed test log, exact failed-case inventory,
verified source snapshot and process exit1. Closed guest .build/dependency-transfer
copies were removed after evidence verification (1,173,827,584 allocated bytes);
VM sources remain. The host dependency archive was replaced by a verified small
source snapshot. Current full VM, UI, physical-phone and Screens gates remain open.

SSH private-key import validation follow-up (2026-10-02): the import form
previously accepted any bounded UTF-8 file containing the OpenSSH BEGIN marker.
It now validates the exact container header/footer, bounded fields, supported
cipher/KDF combinations and bounded bcrypt cost, single Ed25519 public key,
complete private block and absence of trailing container bytes before changing
the selection. Unencrypted keys additionally pass the actual Citadel private-key
parser without running a KDF. Encrypted private contents are checked at connection
time with the supplied passphrase; import is not proof that that passphrase is
correct. The same preflight protects saved credentials and SSH connection input.
Real system-generated plain/encrypted Ed25519 fixtures import successfully;
RSA, oversized/invalid UTF-8, truncated/header-only files and a valid-container
plaintext key with corrupted check integers are rejected. Failed replacements
preserve the previously selected private material and passphrase. No private key
or passphrase is written to test logs; the generated files are removed on exit.
Current focused regression: 39 SSH + 24 Core storage/form tests passed, zero
failures/skips. Current iOS Release build and strict signature verification pass.
Rendered file-picker/passphrase behavior and the complete native trust flow still
require VM UI acceptance after the pending system-authentication issue resolves.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/ssh-key-import-final-acceptance-tests.log`
and `ssh-key-import-signed-ios-build.log`. The full goal remains incomplete.

SSH cancellation/application-close acceptance follow-up (2026-10-02): three
additional real-server regressions exercise a suspended first-use review.
Explicit coordinator stop and cancellation both reject a later Remember response
without persisting a pin or sending any authentication request; stopping does not
wait for the user answer, and a subsequent connection gets a fresh review.
The application SessionViewModel close path dismisses its pending request, ignores
a stale submission, stays disconnected and cannot restart the ended session.
The assertions check the actual Keychain pin and the server authentication
delegate, not only presentation state. Current complete SSH regression: 39 passed,
zero failures/skips. No production change was needed for these cancellation cases.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/ssh-application-close-final-regression.log`
and `Tests/AetherScreensSSHTests/SSHSessionCoordinatorTests.swift`.
Current physical-device readback: the host can reach the paired iPhone 12 Pro over
localNetwork, with developer mode enabled and a connected tunnel. AetherScreens
1.0/build1 and its test runner are installed, but the installed source revision is
unverified. iPhone 16 Pro Max remains unavailable and neither requested physical
phone is discovered inside macos27. This is readiness evidence, not gesture,
fluidity or two-phone acceptance. Only product-relevant device fields were retained
in `physical-device-current-readiness.json`; unrelated installed-app inventory was
discarded. System authentication process 8701 remains live; the existing user
clarification is pending. UI automation stays in macos27 and the full goal remains
incomplete. No release/tag/site update has been performed.

SSH editor responsiveness and disk lifecycle follow-up (2026-10-02): the
explicit Forget action now performs Keychain read/delete off the UI thread,
shows a native progress indicator, and disables repeated Forget and Save while
it is pending. Storage failures retain the reviewed identity; deletion still
compares that identity and the saved endpoint. The existing regression now
asserts background-thread access for both loading and forgetting, including
failure propagation and preserved credentials/other endpoints. Current focused
SSH/Core storage-form regression: 36 + 23 passed, no failures/skips.
The updated iOS Release build and strict signature verification also pass;
see `ssh-async-forget-signed-ios-build.log`.
Native rendering/interaction acceptance of this change remains pending.
The VM runner now finalizes successful and failed build/discovery/execution
paths: it independently hashes exported results and build/test diagnostics before
removing its closed build/app/result copies. Active workspace processes prevent
all removal; source remains. VM smoke tests verify injected-failure preservation
and active-process refusal followed by cleanup after that owned process exits.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/runner-cleanup-smoke/`,
`runner-cleanup-live-guard/`, and `ssh-async-forget-focused-tests.log`.
System UI automation authentication remains unresolved; a user clarification is
pending. The full Screens and physical-device acceptance goal is still active.

SSH first-use UI follow-up (2026-10-02): a local-only QA executable now
provides a transient Ed25519 SSH server, accepts synthetic credentials only, and
restricts direct TCP forwarding to the owned loopback RFB fixture. It exports
public fingerprint/port metadata plus authentication/forwarding event receipts;
private keys and passwords are not logged. The saved-computer test now creates
trust through the application rather than a CLI-created Keychain pin. Current
native run still fails: Chinese password input was outside the visible scroll
region; English reached trust review but macOS exposed an empty static-text label.
The next test revision scrolls before secure entry and verifies native text value,
retaining the exact fingerprint equality assertion and native attribute evidence.
After the other project released its lease, the rerun built successfully but
native test discovery failed before executing any case: XCTest reported
"Timed out while enabling automation mode." The system coreautha process remains
active; its cause is not established, and another project's/system authentication
window was not dismissed. This is an environment failure, not a passed native
SSH flow. Current focused regression: 36 SSH and 23 Core
storage/form tests passed without failures/skips. Current iOS Release build and
strict signature verification pass. No native SSH trust acceptance is claimed.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/ssh-owned-trust-accessible/`,
`ssh-accessible-focused-tests.log`, and `ssh-accessible-signed-ios-build.log`.
The follow-up discovery evidence is retained under
`ssh-owned-trust-native-value/ui/`; both closed guest builds/apps were removed
only after independent archive SHA256 checks. Source copies remain and automation
configuration was restored. The full acceptance goal remains incomplete.

SSH trust recovery progress (2026-10-02): the editor now displays the stored
server endpoint and public SHA256 fingerprint, with explicit Forget/Cancel
confirmation explaining the shared host/port scope. Forgetting compares the
reviewed identity before deleting it, rejects a stale edited connection, retains
credentials and other endpoints, and reports storage failures. A real SSH server
regression proves the next connection reviews the fingerprint again after a
remembered pin is forgotten. Current focused regression: SSH 36 passed, Core
connection/storage 26 passed, zero failures/skips. Updated iOS Release build and
strict signature pass.
Native trust-editor acceptance is NOT passed. A first test compile failed due to
a local Process variable shadowing XCTest.add; that was corrected. Defaults-based
fixture seeding did not make the record visible in the app. The follow-up now
creates a saved synthetic SSH computer through the actual Add form. It uncovered
an ambiguous Chinese Add button query and an actual English editor main-thread
stall in `SystemSSHSecretBackend.read` → `SecItemCopyMatching_osx`, with
SecurityAgent active. The exact stack is retained at
`build/ssh-coordinator-macos-vm-acceptance/ssh-trust-editor-native-add/app-stall.sample.txt`.
The stopped run retained an independently SHA256-verified archive before cleanup.
The editor now reads trust asynchronously off the UI executor and ignores results
when its view task is cancelled. This is a responsive-read implementation change,
not proof of resolved Keychain ACL handling; its fresh native UI rerun remains
required. SDK SecItem.h notes legacy keychain items may activate UI despite
noninteraction attributes; see [Apple's Mac Keychain implementations note](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).
Closed compilation/native build copies were removed (622,690,304 allocated bytes).
The synthetic saved computer, associated credential and three remaining generated
public trust-qa pins were removed without accessing their secret values. Source,
failed logs and archives remain. No release approval or full Screens parity.

SSH connection forms (2026-10-02, current candidate): Add, Quick Connect and
Edit share a native grouped SSH section with separate server/port/account,
password versus Ed25519 authentication, bounded private-key file import,
optional passphrase and forwarding destination. Imported private material is
kept in the transient draft; the form shows only the filename. Saved edits leave
existing secrets blank and require a replacement credential when the endpoint,
account or authentication changes. Disabling SSH removes its credential before
publishing the edit. Failed credential writes/deletes retain the form and old
record; temporary requests never save SSH credentials. ConnectionRequest carries
transient credentials separately from Codable device metadata, and the saved
quick-session path now uses the same injected SSH Keychain store as DeviceStore.
Focused connection/storage regression: 26 passed; SSH regression: 33 passed,
including failed save/delete persistence boundaries. Updated iOS Release build
and strict signature verification pass (1.0.0/build1). Fresh bilingual Mac form/session regression passes all four requested cases
with exact discovery, zero skips/failures/runtime warnings/animation timeouts.
English and Chinese screenshots were reviewed. Complete Core regression: 257
tests, six explicit external-environment skips, zero failures. The closed guest
build/app/result copies were removed after independent archive SHA256 verification
(301,359,104 allocated bytes). This accepts the tested forms and direct-session
regression, not the complete SSH end-to-end UI or hardware matrix. End-to-end rendered SSH trust review,
private-key import/editor UI acceptance, explicit host-key forgetting UI,
physical iPhones and the remaining Screens features still require completion.
Evidence: `build/ssh-coordinator-macos-vm-acceptance/ssh-forms/` and adjacent
`ssh-forms-final-tests.log` / `ssh-forms-ssh-regression.log`.

Native Mac UI progress (2026-10-02): the current Mac keyboard toolbar now
reserves window space with top/bottom safe-area insets rather than sharing the
canvas overlay. The prior toolbar could appear partially clipped and native
XCTest could not hit Tab even though AX reported its bounds inside the window.
Both English and Chinese controlled native session cases now pass: actual mouse
down/up, balanced Tab down/up, Observe dismissing the keyboard and suppressing
wire input, restored control, a new reconnect socket, fresh Tab delivery, and
session close. Both report Tab hittable with the unchanged semantic click.
The accepted two-case archive, exact discovery inventory and frozen production
source hashes are in `build/ssh-coordinator-macos-vm-acceptance/keyboard-inset/`.
The fresh four-case gate also passes, with exactly four discovered/executed tests,
zero failures/skips/runtime warnings/animation completion timeouts. It includes
bilingual connection validation, a permanent hit-region assertion, and reviewed
English/Chinese toolbar screenshots showing complete button heights. Evidence:
`build/ssh-coordinator-macos-vm-acceptance/keyboard-inset-full/ui/summary.json`
and `keyboard-en.png` / `keyboard-zh-Hans.png`. Both closed inset runs were
archived, independently SHA256 checked and cleaned (537,251,840 allocated bytes).
The UI fix applies only to macOS; physical iPhone, SSH forms and the full Screens
feature matrix remain unaccepted. This is not release approval.

Disk cleanup (2026-10-02): the closed geometry diagnostic's final result was
archived and SHA256 verified before removing its guest build/app/result copies
and disposable compiler caches (473,780,224 allocated bytes including the
transient archive). Guest source copies, Xcode, simulator state and other projects
remain. VM available space after cleanup is approximately 24.2 GiB. New runs must
retain evidence and clean their own closed build outputs after acceptance.

SSH application lifecycle (2026-10-02): `SessionViewModel` now connects through
an owned `SSHSessionCoordinator` and presents a native bilingual server identity
review. One-time trust does not persist; remembered trust is insert-only. Missing
credentials never fall back to direct RFB. Reconnect/close invalidate old attempts,
cancel pending sockets and serialize cleanup. Retained sessions are reused only
for unchanged remote/SSH identities. Final disconnect actions keep the tunnel
alive until the RFB completion callback. Actual fixture tests verify application
frames, Tab and pointer down/up, initial centered cursor, and balanced lock
shortcut before teardown. Twenty rapid probe handshakes and ten complete repeated
RFB handshakes exercise initial read timing. Bootstrap sockets now start with
`autoRead=false`; reading starts only after SSH handlers are installed, preventing
early server data from being discarded between TCP connect and handler setup.
The earlier intermittent handshake timeout and the fixture's initially missing
application cursor-setup packet remain preserved in the failed logs.
Current full Debug: SSH 32 passed, Core 254 with six explicit external-environment
skips and zero failures; signed iOS Release build and strict signature pass.
Evidence: `build/macos27-current-ui-acceptance/ssh-coordinator-verification.json`.
The VM console is now READY and native Mac cases actually execute, but local
network permission dialogs still block UI acceptance. Two failed archives were
SHA256-verified before removing 435 MiB of closed guest build/app/result copies.
QA automation-mode configuration was restored after each run. SSH add/edit forms,
credential entry, rendered trust-sheet acceptance, and full hardware acceptance
remain open; this is not Screens parity or release approval.

SSH durable storage (2026-10-02): validated, Codable `SSHConfiguration` now
persists with devices without passwords/private keys/passphrases. A separate
`SSHKeychainStore` uses actual Keychain reads, atomic updates and insert-only
host approval; it has no memory fallback. Read/write/delete failures propagate,
credentials bind to the device and complete SSH configuration, and changed
host keys require explicit forgetting before new approval. Tests prove real
Keychain durability across instances, failed replacement preservation,
account/endpoint binding, legacy device decoding, and device deletion that
preserves the record when secure deletion fails. Bilingual deletion errors are
wired to the existing device-list error surface. SSH-configured sessions currently
fail closed until the application tunnel lifecycle/trust UI is connected.
Full Debug before the final deletion integration: SSH 23/23, Core 254 with six
external-environment skips and no failures. Final focused SSH/storage/session
regression and signed iOS Release build pass. Source/log proof is recorded in
`build/macos27-current-ui-acceptance/ssh-storage-verification.json`.
The current Keychain policy is local only; iCloud credential synchronization,
SSH forms/trust review and complete device UI acceptance remain outstanding.

Current SSH first-use inspection (2026-10-02): the project now provides
`SSHServerKeyProbe.inspect`, which returns public host-key identity for explicit
review and intentionally rejects key validation before user authentication.
The owned socket closes before success returns; cancellation of a silent server
closes promptly. The complete SSH suite passes **17 cases, zero failures/skips**,
including an actual NIOSSH server that receives zero authentication requests
while returning the expected identity. Invalid endpoints are rejected before
networking. Evidence: `build/macos27-current-ui-acceptance/ssh-server-key-probe-full.log`.
This does not yet provide application trust dialogs, persistent approved pins,
SSH credential storage or session UI integration. Those requirements remain open.

Current verification (2026-10-02): the latest frozen-source macos27 run has
completed **34/34 cases: controlled input/session 22, clipboard 4, and
library/narrow layouts 8**, with no skips, failures, runtime warnings or animation
completion timeouts. This accepts the enumerated simulator suite.
Closed archives were independently SHA-256 verified on the host before deleting
the guest duplicates. The final installed Mac and two physical iPhone gates
remain open. The first two Mac-native discovery attempts executed zero app
cases: XCTest timed out enabling automation while the VM console was locked.
The QA runner now reads the console state before creating a test workspace;
its locked-console rejection was verified. Temporary Apple automation-mode
configuration was restored; manual VM unlock is pending.

An isolated SSH prototype now passes nine tests: password-authenticated direct
TCP forwarding of 131072 exact binary bytes, encrypted OpenSSH Ed25519 key import
and authenticated forwarding (including wrong-passphrase rejection), changed
server-key rejection during an actual handshake, two pin-validation cases, system OpenSSH interoperability with 262144 exact
bytes, local loopback stop/reconnection rejection, and delayed-consumer transfer
of 4 MiB, and SSH closure while a loopback channel is opening. Its current sources also compile against the iOS 17 device target.
Large writes are split into 16384-byte chunks while preserving their error
promises. This is not application SSH support: further lifetime/cancellation and
backpressure verification, credentials/fingerprint UI and actual
session integration remain required. Evidence:
`build/macos27-current-ui-acceptance/ssh-prototype-loopback-verification.json`.

The SSH work has now moved from the disposable prototype into the project target
`AetherScreensSSH`. The project-owned, pinned NIOSSH client establishes its
pipeline on the event loop and closes TCP immediately on cancellation; the
upstream `connect(on:)` path triggered a pipeline-thread assertion during the
first owned-session test and is not used by this connection factory.
Current SSH tests: **14 passed, zero skipped/failed**. They additionally verify
actual RFB handshake/frame/Tab/pointer delivery and the balanced final lock
transaction through the encrypted tunnel, rejection of a changed server key,
encrypted Ed25519 interoperability with system OpenSSH, SHA256 fingerprints
against `ssh-keygen`, prompt cancellation of a silent handshake, and rejecting
excessive key KDF costs before hashing/network. The complete Core Debug suite
passed 254 cases with six explicit external-environment skips and no failures
before the owned-session helper additions; Core/RFB code is unchanged since it.
The latest signed iOS 1.0.0/build1 compilation and strict signature check pass.

Evidence: `build/macos27-current-ui-acceptance/ssh-production-verification.json`
and `ssh-owned-signed-device-verification.json`. The 34-case accepted VM run and
existing Mac QA app predate the new SSH target: they do not accept the new
candidate. SSH forms, Keychain key/password/passphrase storage, first-use trust
review and SessionViewModel ownership remain required. Modern RSA-SHA2 also
remains open: the pinned Citadel RSA implementation uses SHA1; no enabling of
legacy algorithms on a server has been used as acceptance. Physical devices
and the other original Screens requirements remain in scope.

| Requirement | Current implementation and evidence | Remaining work |
| --- | --- | --- |
| Mac account / VNC connections | ARD type 30 and VNC implemented; real Mac authentication, frame and 60-second session passed. iPhone 12 Pro received the requested target Mac's desktop; user confirmed connection. | iPhone 16 Pro Max target session; sustained physical-device interaction |
| Interactive shortcut toolbar | Sticky modifiers, common shortcuts, F1-F12; Mac F8 observed remotely | Physical iPhone modifier/shortcut delivery and narrow layouts |
| Touch / trackpad gestures | Native iOS recognizers now wire immediate clicks, secondary/middle clicks, held-button dragging, two-axis scrolling and pinch zoom. Cursor movement uses remote-pixel scaling, smooth acceleration and an immediate UIKit layer. Core tests cover click release, scaling and engine drag state. English/Chinese iOS simulator flows additionally inspect packets received for single/double/right/middle click, held-button drag, direct touch, pinch coordinate changes and Observe suppression; both flows pass without runtime warnings. Three-finger desktop shortcuts, local two-finger fullscreen and held-button colors are now implemented; their acceptance details appear below. Actual loopback TCP tests additionally verify scrolling preserves held buttons, delayed wheels use the latest released-button state/coordinates, and Observe cancels old work without delaying resumed control behind the cancelled backlog. | Physical tap, secondary click, drag, pinch, scroll and mode changes; Apple server combined scroll/drag acceptance; perceived responsiveness; native two-axis scroll and secondary/middle drag indicators; physical three-finger shortcuts and fullscreen; edge/hot-corner gestures |
| Hardware pointing devices | Mac native mouse, drag, context menu and wheel passed. UIKit now has absolute mouse/Pencil contacts, hover and hardware-only two-axis scroll; independent device button ownership and actual TCP receipts pass targeted core tests | Actual iPhone/iPad mouse/trackpad/Pencil delivery and hardware keyboard acceptance |
| International keyboards / dictation | UTF-8 text drawer and Chinese keysyms passed; NSTextInputClient composition tests. Real Apple 3.889 server now receives exact Chinese, emoji and supplementary Han committed text after the UTF-16 compatibility fix; standard RFB scalar encoding is retained and TCP-tested | Physical iPhone/iPad supplementary input; native application and real IME acceptance; dictation workflow |
| Dictation | Native customizable toolbar action, English/Chinese language selection, device-side recognition request, editable preview and explicit send. Confirmed text transport and cancellation/denied-permission boundaries are tested. | Actual microphone authorization, speech accuracy, stop/restart and bilingual VM/physical-device flows |
| Clipboard transfers | Traditional Latin-1 and negotiated UTF-8 loopback text passed. Modern Apple text archive sends and fetches exact Chinese, emoji and supplementary Han on the real Mac; normal sendCutText integration and independent remote-copy automatic status/fetch flow passed. Immediate app paste transaction passed on the real Mac; typed Apple archive codec and fragmented TCP receive/upload preserve image, URL, rich-text bytes and aliases. UIKit/AppKit integration, explicit typed paste, native isolated pasteboard and session foreground/Observe guards are implemented and targeted-tested; real Mac PNG/URL/RTF/HTML download, native upload and roundtrip now pass with independent clipboard restoration | Physical iPhone rich-content transfer and rendering remain pending; Shared Clipboard automation, persisted default-on settings and manual Send/Get are implemented with loopback/session regression; actual iOS permission/foreground delivery and native bilingual UI execution; multiple local clipboard items; physical iPhone clipboard acceptance; prior bilingual UI passes do not accept the current source; the latest synchronous-read clipboard run stalled and was rejected, and the new asynchronous implementation requires complete fresh bilingual VM execution |
| Type User Password | Native toolbar/menu command with local identity authentication; click types and presses Return, held click types without Return. Current Mac-account credential priority, temporary sessions, cancellation and target checks pass synthetic TCP regression | Actual identity prompt, held-button and remote password-field UI acceptance; privacy settings and hardware shortcut routing |
| Curtain privacy mode | System lock shortcut and password restoration passed | Actual remote display blackout while remaining unlocked; lock is not parity |
| Display selection | ExtendedDesktopSize server layout decoding, stable screen IDs, selected-monitor crop and bounded input coordinates; no monitor-count inference from framebuffer aspect ratio. Actual TCP tests cover layout-only updates, rejected resize payloads and subsequent raw frames, plus framebuffer resizing. | Apple server layout negotiation and physical per-display acceptance on the user local Mac192.168.50.26 with built-in plus LG display; original target192.168.50.226 has one LG display. Remembered server-ID selection is newly implemented and core-tested; current-candidate VM/physical restoration acceptance remains pending |
| Adaptive image quality | Raw, Zlib, ZRLE and CopyRect decoding; Metal rendering; native presented-frame FPS and measured TCP RTT diagnostics | Network-dependent quality/compression selection and measured responsiveness. Initial-frame progress is now suppressed during streaming; regression tests prove fewer UI publications, not physical responsiveness |
| Observe / control modes | Explicit Observe Only mode; real Mac frames continue while text, clicks, wheel and clipboard writes are blocked; held modifiers released and control restored. iOS retains local zoom/pan while Observe suppresses received pointer input; English/Chinese controlled viewport flows pass. Pan separately blocks pointer input, cancels queued wheels and preserves keys; actual TCP tests cover nested Observe transitions and responsive scrolling afterward | Physical iPhone toggle and input suppression acceptance |
| Reconnect / session recovery | In-session reconnect clears input and restores remote typing. English/Chinese simulator socket-interruption tests pass with a new TCP connection, fresh frame, retained zoom/touch mode and received fresh modifier/key events. Core tests reject ended-session callbacks and old VNC/ARD password replies | Physical iPhone and Apple server recovery; real phone network interruption |
| Quick connect / session selection | Temporary account/VNC requests and optional saving; installed Mac account connection and received typing passed; iPhone simulator validation, save toggle and error/disconnect flow passed. In-app retained session selection now preserves sockets/viewports, gates hidden input and rejects hidden clipboard callbacks; English/Chinese received-packet UI flows pass | Physical iPhone quick connection and session switching; OS background execution remains unverified |
| Secure connections / SSH keys | External Tailscale transport/import, integrated SSH password/Ed25519 tunnel coordinator, explicit host-key review, durable credentials and trust recovery; real SSH/RFB/cancellation tests pass | Rendered SSH trust/import/editor acceptance; current real SSH server and Tailnet route/import compatibility; physical phone and modern RSA SHA2 compatibility |
| File transfers | No transfer implementation | Apple drag-and-drop transfer on Mac/iPhone/iPad, progress and received-file verification; mobile download requires remote macOS 14+, upload macOS 10.10+ |
| Data / credential synchronization | Local persistence and Keychain migration | Cross-device synchronization and conflict handling |
| Toolbar customization / keyboard options | Per-computer button size, top/bottom position, visibility, ordering and multiple spacers implemented. Installed Mac position/size/menu switching, hiding, moving, adding spacers, relaunch persistence and remote arrow/delete delivery passed. iPhone 17 simulator settings flow passed; final English/Chinese flows on a 375-point iPhone 13 mini simulator passed and screenshots were inspected. English/Chinese customization flows on both physical iPhones also passed (2/2 each, no runtime warnings), using an invalid temporary destination. Temporary settings remain in memory; hiding a held modifier releases it. | Physical iPhone live toolbar/key delivery; keyboard mapping preferences and cross-device synchronization |
| On-disconnect actions | Per-computer native action picker persists disconnect-only, lock, logout and four corners. Actual TCP tests verify released held input, balanced shortcuts, selected-display coordinates, one final write, replacement-connection safety, latest saved preferences and explicit closing of retained control sessions. Observe, interrupted sessions and changed/deleted targets skip actions. Latest bilingual disconnect cases passed, including editing a retained session. | Final sixteen-case controlled VM regression completed 15 passed/1 failed (fixture HTTP deadline) and is not accepted; configured corners, actual OS lock/logout and physical-device behavior require isolated-desktop acceptance |
| URL schemes / automation | Mac/iOS bundles register aetherscreens and alternate vnc handlers. Saved identifier/name/address and temporary account/VNC links support explicit Observe selection. Core validation and iOS system URL delivery preserve a Quick Connect draft, open the queued Observe session after dismissal, disable keyboard control and avoid saving the temporary computer. | Installed Mac and physical iPhone routing/copy-link acceptance; SSH/SSH-key and guest semantics with real server/tunnel handling; applicable shortcuts/widgets |
| AirPlay / external display / Pencil | Native Pencil contact/drag/hover and configurable double-tap/squeeze implemented; core mapping/ownership, persisted preferences and actual TCP shortcut tests pass. Display routing is not implemented | Real Pencil acceptance; bilingual iPad gesture-settings UI acceptance and floating/carousel toolbar; AirPlay and external-display routing/acceptance |
| Mac multi-window sessions | Independent native windows; real Mac concurrent account sessions, minimizing/restoring, saved-session reuse, Observe isolation and closing one window while continuing remote input in the other passed. Numbered window/menu titles distinguish the same computer. | iOS in-app session selection passes controlled UI; physical switching and OS background behavior remain in their separate requirement |
| Wake-on-LAN | Packet construction tests and send-success notice | Real wake verification on an appropriately configured sleeping Mac |
| Discovery / device library / diagnostics | Bonjour discovery visible; add/edit and diagnostics UI covered | Saved devices now use a neutral Saved badge; Tailnet status is distinguished from screen-sharing reachability. Remote API error/recovery acceptance remains. |
| UI consistency / branding | App icon assets on Mac/iOS/site, grouped account forms and readable input bar | Full narrow / empty / loading / error / modal audit on physical devices |
| English / Simplified Chinese | Implemented; core/catalog tests, Mac switch, simulator persistence/narrow layouts and both physical iPhones' language switch/persistence passed. Account prompt passed both simulator languages. | Remaining whole-flow physical-device layout audit |
| Release readiness | Latest core Release suite: 254 tests, 6 explicit external-environment skips, no failures; Dictation audio/UI acceptance is pending; real Apple remote-copy automatic status/fetch acceptance passed. Current Mac Release builds pass; the updated signed iOS device Release build and strict signature verification pass; prior iOS simulator test builds pass; iOS system URL flow passes with no runtime warnings. URL integration cbfe9db, pointer transport 3178a3a and native gesture/UI integration 7b93500, session recovery d286a69 and streaming progress 951e0c3 and viewport navigation d30c4f8 and Pan pointer gate 4b6629e passed CI, as did prior input/resize commits; the earlier 73-test candidate passed notarization, mounted DMG and installed input | Display-layout integration 3be37e8, incremental GPU rendering 913eb8c and display-switch input eb78dcb passed CI; clipboard lifecycle/text encoding a411187 passed CI; extended-clipboard validation 5485f1b passed CI; native navigation gestures 698249b passed CI and controlled UI; physical acceptance remains required. Complete functional gates and user review; no public release yet |

Vision Pro, Windows/Linux server support and Screens Connect infrastructure are
listed by the reference product but were not in the requested iPhone/iPad and
Apple-silicon Mac platform scope. Their absence must not be described as supported.

The iOS live test now accepts the Mac username and selects the account password
field. Previously it could only exercise the VNC-password path. The updated account form
simulator test passed. Connection attempts no longer stamp successful-connection
history; a regression test verifies this boundary. Physical iPhone
initially required unlocking both devices. Parallel USB runs subsequently
completed the six UI scenarios on iPhone 12 Pro and iPhone 16 Pro Max. The 12 Pro
passed 6/6; the 16 Pro Max passed 5/6 before an interrupted menu tap was retried.
The English and Chinese toolbar scenarios then passed 2/2 on each device.
These scenarios check UI and intentionally failed destinations, not live input.

Physical connection diagnosis found that Bonjour instance display names had
been incorrectly converted to DNS host names. The fix resolves the actual SRV
host and port and repairs only old generated addresses, preserving device IDs,
accounts, Keychain associations and manually configured IP addresses. A live
LAN discovery regression verifies a display name differing from its DNS host.
The 12 Pro received a real framebuffer from its saved MacBook Pro after repair;
that machine is 192.168.50.26, not the requested 192.168.50.226 target. The
16 Pro Max's saved configuration lacked a username, so its Mac-only server
rejected VNC authentication. Interactive Mac username/password prompting is now
implemented with handshake and saved-versus-temporary persistence regressions.
The 12 Pro subsequently passed the account-session test against 192.168.50.226;
its screenshot shows the controlled QA desktop. The user confirmed connection
but reported poorer responsiveness than Screens. The 16 Pro Max target test
was interrupted before reaching Quick Connect and remains pending; its subsequent
normal launch was denied while locked. CoreDevice refused pasteboard
transfer because the current clipboard is marked transient/remote-synchronized;
no password was copied into it or written to test arguments/results.

The responsiveness repair removes single-click waiting for double-tap zoom and
the 50 ms click-release timer, connects the previously unwired iOS gestures,
scales finger points to remote pixels, moves the cursor directly in a UIKit
layer, and avoids publishing unchanged first-frame/display state for every
frame. Metal invalidation is coalesced and removes the extra main-thread hop.
The latest core suite passed 102 tests with four environment skips. Mac and iOS
Release builds passed. The optimized iOS candidate was installed on both phones;
normal launch passed on the 12 Pro and awaits unlocking on the 16 Pro Max.
Actual improved hand feel and physical gesture delivery remain unaccepted.
This is an internal test candidate, not a public release.

Reference detail checked on 2026-10-01: [Toolbar customization](https://help.edovia.com/en/screens-5/features/toolbar-customization),
[on-disconnect actions](https://help.edovia.com/en/screens-5/features/on-disconnect-actions),
and [URL schemes](https://help.edovia.com/en/screens-5/features/url-schemes).
The remaining-work cells retain these concrete behaviors; existence of a
settings sheet or parser alone is not completion of the corresponding feature.

Live toolbar/menu acceptance exposed a metrics deadlock: the network thread
published an observable bandwidth value while holding the metrics lock and
waited for SwiftUI's main thread; Metal drawing on the main thread waited for
that lock. The repair publishes on the main thread after releasing accumulator
locks. Regression tests cover observable notification reentering frame recording
and main-thread publication from a network thread. The previously stuck native
position menu and continued remote key delivery passed in the installed repair.

The iPhone keyboard-settings acceptance uses an invalid temporary destination;
it verifies UI configuration, sheet stability, visible controls and disconnect,
not live network delivery. Screenshot review caught an oversized truncated English
title; the final inline title fits both languages. Sorting/removal controls have
44-point targets, and the session menu exposes configuration without requiring
horizontal toolbar scrolling. The final mini report contains two passed tests,
zero failures and zero runtime warnings.

Gesture reference checked on 2026-10-01:
[Cursor Control and Gestures](https://help.edovia.com/en/screens-5/features/cursor-control-modes-and-other-gestures).
The reference documents two-axis scrolling, secondary/middle drag, three-finger
Mission Control/App Expose/Space shortcuts, two-finger fullscreen toggling, edge
cursor positioning and hot-corner gestures. The existing click/drag/pinch tests
do not prove all those workflows. They remain in the full gesture acceptance
scope; local viewport navigation does not substitute for them.

## Server-reported display layouts

The client previously advertised encoding -308 without consuming its payload and
inferred two displays from wide framebuffer dimensions. It now decodes
[ExtendedDesktopSize](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst),
validates unique IDs and framebuffer bounds, preserves unknown flags, and consumes
failed resize responses without applying their undefined geometry. Layout-only
updates retain existing pixels; changed framebuffer dimensions invalidate them.
Server ID zero remains distinct from the full-desktop UI choice. Monitor removal
falls back to the full desktop, and selected-monitor coordinates clamp to its
actual last pixel. Session-generation guards reject stale layout/selection work.
Unchanged geometry does not republish canvas state or reset local zoom. Metal
samples only the selected monitor's normalized texture region; the CPU fallback
crops the same bounds, and canvas sizing/input share that region. The desktop view
observes monitor-list publications directly so same-size, layout-only changes
refresh its menu even when no new pixel frame arrives. Changing region
resets local navigation and cancels active input recognizers. Layout-only replies
do not mark the initial desktop as visible or suppress its download progress.

`swift test` passed 125 tests with 5 external-environment skips and no failures
(`/tmp/aetherscreens-monitor-accepted-core.log`). Mac Release and signed iOS
Release builds pass. The earlier unsigned invocation failed because no development
team was specified. An incremental signed build later failed strict resource
verification after the localization files changed, so it was rejected. A fresh
build in `/tmp/aetherscreens-display-accepted-signed-derived` uses the existing
development team and passes deep, strict signature verification
(`/tmp/aetherscreens-monitor-final-signature.log`). The signed candidate has not been installed
on either phone during the hand-feel trial. A read-only SSH inventory of the
requested target reports one online LG HDR 4K display, logical 1920x1080 at 60Hz
and 4K physical pixels. This does not verify Apple RFB layout negotiation or
physical multi-display selection, and these remain open acceptance gates.

A concurrent verification run recorded one CopyRect timing-budget failure
(15.784 ms/frame against the unchanged 15 ms threshold; the preceding run was
1.603 ms/frame). The host's subsequently observed load average was over 300 while
other projects were compiling. This is an environment-load hypothesis, not proof
of the earlier failure's cause or physical-phone latency. The failed log
`/tmp/aetherscreens-monitor-final-core.log` is retained; the final acceptance
rerun follows completion of this task's Release builds. No threshold was relaxed.

The final controlled simulator run passed all eight requested cases with zero
skips, failures or runtime warnings (`build/ios-monitor-final-controlled-qa/`).
Both English and Chinese display-selection flows verify a right-monitor crop,
full-desktop restoration, then a live two-to-three-monitor layout change without
changing the framebuffer size or sending pixel data. The new third monitor
becomes selectable and receives the expected translated touch coordinate.
Selected-monitor/full-desktop screenshots were exported and inspected. The
existing native-input, viewport and reconnect flows also passed. These synthetic
loopback desktops do not replace Apple-server or physical multi-monitor proof.
The final complete core rerun passed 125 tests, with five environment skips and
no failures; CopyRect measured 2.172 ms/frame without changing its threshold.

## Incremental GPU uploads and queued-frame correctness

The renderer previously uploaded the complete framebuffer on every dirty draw.
A GPU readback regression reproduced five expected failures before the fix
(`/tmp/aetherscreens-incremental-upload-before.log`): unnecessary full uploads
for a one-pixel update and unchanged redraws, and missing initialization after
a resize when pixel uploading was disabled.

Framebuffer changes now use a bounded revision history shared by independent
readers. Overlapping regions merge; excessive damage or an expired history
falls back to a complete upload. CopyRect uses overlap-safe row ordering and
memmove instead of allocating a temporary array for every row. Invalid raw
updates leave pixels and revisions unchanged, and clipping retains the original
source row stride.

Pixels are copied into retained shared staging buffers, then blitted to a private
texture before rendering in the same ordered command buffer. This follows
Apple's [CPU texture-write synchronization requirement](https://developer.apple.com/documentation/metal/mtltexture/replace%28region%3Amipmaplevel%3Aslice%3Awithbytes%3Abytesperrow%3Abytesperimage%3A%29)
and [buffer-to-texture blit API](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy%28from%3Asourceoffset%3Asourcebytesperrow%3Asourcebytesperimage%3Asourcesize%3Ato%3Adestinationslice%3Adestinationlevel%3Adestinationorigin%3A%29).
At most three presentation commands are in flight; overload defers a redraw
until a completion without blocking input on GPU work.

Actual GPU readback tests verify a 3840x2160 initial upload of 33,177,600 pixel
bytes, a one-pixel update of four pixel bytes, unchanged redraws of zero bytes,
CopyRect correctness, initialized resized textures, independent readers, and
same-size framebuffer replacement. Byte counts describe encoded pixel payload,
not measured bus traffic: staging rows are aligned to 256 bytes. A shared-event
test delays GPU execution while 24 frames are queued and verifies each frame's
individual pixels, covering staging lifetime and command ordering.

The final complete core suite passed 132 tests with five external-environment
skips and zero failures (`/tmp/aetherscreens-incremental-core-final.log`);
1080p CopyRect measured 0.760 ms/frame against the unchanged threshold. Mac and
iOS Release builds passed (`/tmp/aetherscreens-incremental-mac-release.log`,
`/tmp/aetherscreens-incremental-ios-release.log`). The fresh signed iOS candidate
in `/tmp/aetherscreens-incremental-signed-derived` passes deep, strict signature
verification. It has not yet been installed for physical-device acceptance.
These rendering checks do not measure phone input-to-display latency or establish
Screens-equivalent hand feel. Those physical gates remain open.

The final controlled simulator rerun passed all eight requested English/Chinese
display, viewport, native-input and reconnect cases, with zero skips, failures
or runtime warnings (`build/ios-incremental-render-controlled-qa/`). Exported
selected-monitor and live-layout screenshots were inspected to confirm the new
private-texture rendering path actually presents the expected crop and pixels.
This is synthetic simulator coverage, not a two-phone acceptance result.

The incremental-render commit `913eb8c` passed CI run 36836749844 on its second
attempt. The first attempt failed the existing streaming-progress reconnect
case (five-second wait, no decoded frames), while all GPU tests passed. Its log
is retained at `/tmp/aetherscreens-incremental-ci-failed.log`. The same streaming
case passed locally, then ten consecutive repetitions without changing the
source or timeout. This does not establish the first timeout's cause.

## Display selection during held input

A real loopback TCP regression reproduced an incorrect mouse release at x=4
after switching from the right monitor, where the last transmitted held position
was x=12. It also received old wheel pulses after switching
(`/tmp/aetherscreens-display-input-before.log`). Selection now closes the
transport pointer gate before scheduling UI work: it releases the mouse at the
last transmitted global position and invalidates queued wheel work. Local held
state is cleared while the gate remains closed, then pointer input is restored
according to viewport Pan state. Observe still retains its global input gate.
Geometry changes reset navigation; switching identical geometry clears input
without resetting navigation. Duplicate unchanged layout callbacks preserve
ongoing input.

The TCP regression checks the original release coordinates, cancellation of a
300-tick backlog after a keyboard receipt barrier, fresh scroll on the next
monitor within 0.5 seconds, and a duplicate layout preserving the held drag and
input generation. The earlier six-case pointer transport suite passed, including
Pan, Observe and resumed scrolling (`/tmp/aetherscreens-display-input-after.log`).
Mac Release and signed iOS Release builds pass; the iOS candidate passes deep,
strict signature verification (`/tmp/aetherscreens-display-input-signature.log`).
The initial iOS invocation omitted the existing development team and failed;
the accepted invocation supplies it without modifying project signing settings.
This synthetic two-display regression does not replace physical Apple-server
or two-iPhone acceptance.

The final complete core rerun passed 133 tests with five environment skips and
zero failures (`/tmp/aetherscreens-display-input-core-accepted.log`), including
the added duplicate-layout assertion. CopyRect measured 0.751 ms/frame against
the unchanged threshold.

Display-switch input commit `eb78dcb` passed CI run 36837835393. Its final
controlled simulator run passed all eight requested English/Chinese cases with
zero skips, failures or runtime warnings (`build/ios-display-input-controlled-qa/`).
The selected-monitor screenshot was exported and inspected.

## Clipboard lifecycle and wire text

Two regression cases reproduced stale clipboard writes after ending or
reconnecting a session (`/tmp/aetherscreens-clipboard-lifecycle-before.log`).
Clipboard delivery now captures the session callback generation before queueing
the UI task, rejects a changed generation, and requires a currently connected
client before invoking the clipboard writer. The writer is injectable so these
tests do not read or replace the user's system clipboard. Native platform writes
remain the default.

A packet regression also reproduced UTF-8 bytes in traditional ClientCutText
and carriage returns that violate its format
(`/tmp/aetherscreens-clipboard-legacy-before.log`). The
[RFB clipboard specification](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#746-clientcuttext)
requires Latin-1 and LF for traditional messages, and UTF-8, CRLF and a trailing
null for extended text. Traditional encoding now returns nil for text that
cannot be represented without loss. `sendCutText` returns a Boolean indicating
queue acceptance (not a remote acknowledgement), rejects disconnected/Observe
input and oversize normalized data, and never sends unrepresentable Unicode as
traditional Latin-1. Negotiated extended text uses CRLF on the wire; received
extended text is normalized to local LF.

Actual loopback TCP tests receive accented Latin-1 text from the server, inspect
the client's exact accent/newline bytes, reject unsupported Chinese/emoji
uploads to the legacy-only fixture, and confirm Observe blocks uploads. They
also queue old text across end/reconnect and accept fresh server text after a
new handshake. Compressed UTF-8 parser coverage includes Chinese and CRLF text.
These controlled tests do not establish Apple Screen Sharing clipboard delivery,
physical-phone clipboard routing, rich content or file transfer. Those original
acceptance requirements remain open.

The complete core suite passed 137 tests with five environment skips and zero
failures (`/tmp/aetherscreens-clipboard-core-accepted.log`); CopyRect measured
0.708 ms/frame against the unchanged threshold. Mac Release and signed iOS
Release builds passed (`/tmp/aetherscreens-clipboard-mac-release.log`,
`/tmp/aetherscreens-clipboard-ios-release.log`), and the signed iOS candidate
passes deep, strict verification (`/tmp/aetherscreens-clipboard-signature.log`).

Clipboard lifecycle/text-encoding commit `a411187` passed CI run 36838639008.

## Negotiated UTF-8 clipboard TCP coverage

The controlled TCP fixture now exercises negative-length extended clipboard
messages after a real RFB handshake. Tests observe capability replies, the
client's notify action, a server request and its compressed provide response.
Independent decompression verifies exact Chinese, emoji, CRLF multi-line and
trailing-null bytes rather than invoking the client's own decoder to check its
encoder. A server notify/request/provide exchange then reaches the session's
clipboard writer with normalized Chinese/emoji text. Observe cancels the pending
upload and blocks an explicit new upload; a delayed server request sends no
provide response, while the incoming clipboard download still succeeds.

The expanded regression reproduced three failures before the fix
(`/tmp/aetherscreens-clipboard-extended-validation-before.log`): a capability
message missing its size entry enabled Unicode uploads, RTF-only capabilities
also enabled text uploads, and a compressed text value without a terminating
null overwrote the local clipboard. Capability payload length now matches the
number of advertised format bits, UTF-8 availability requires the text format,
and losing text capability clears pending uploads. Text provides require their
terminating null. Following valid legacy messages still decode after malformed
extended messages, proving the stream remains aligned. The rules follow the
[RFB Extended Clipboard specification](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#7729-extended-clipboard-pseudo-encoding).

The complete core suite passed 140 tests with five environment skips and zero
failures (`/tmp/aetherscreens-clipboard-extended-core.log`); CopyRect measured
0.671 ms/frame without changing its threshold. Mac Release and signed iOS
Release builds passed (`/tmp/aetherscreens-clipboard-extended-mac-release.log`,
`/tmp/aetherscreens-clipboard-extended-ios-release.log`); the iOS app passes deep,
strict signature verification (`/tmp/aetherscreens-clipboard-extended-signature.log`).
The first new test compilation hit a Swift type-inference diagnostic; explicit
closure types and UInt32 length assertions fixed the fixture before reproducing
the product failures. None of these tests read or overwrite the user's system
clipboard. Apple-server, physical-phone and rich-content acceptance remain open.


## Native navigation gestures and fullscreen recovery

Following the [Screens gesture reference](https://help.edovia.com/en/screens-5/features/cursor-control-modes-and-other-gestures),
iOS now recognizes three-finger up/down/left/right swipes and sends Control-Up,
Control-Down, Control-Right and Control-Left respectively. The shortcut menu
also exposes App Windows and previous/next Space in English and Chinese.
Session dispatch releases sticky modifiers first and blocks these remote
shortcuts in Observe mode. A real loopback TCP test verifies every key packet,
including sticky Command release and the absence of remote keys in Observe.
Actual three-finger contact recognition and customized Mac shortcut mappings
still require physical acceptance.

Two-finger double-tap toggles local fullscreen in normal and Observe modes.
Toolbar/keyboard visibility returns on exit, while a failed fullscreen session
reveals recovery and disconnect controls. Reconnect preserves its fullscreen
preference. The local cursor now gives blue/red/green feedback for held
left/right/middle buttons. Physical secondary/middle dragging, edge navigation
and hot corners remain open; these changes are not complete Screens parity.

The first full ten-case UI run retained a genuine fullscreen failure in
`build/ios-navigation-fresh-controlled-qa`; the subsequent run in
`build/ios-navigation-final-controlled-qa` still failed Chinese first entry.
Temporary DEBUG-only touch diagnostics then proved the tap recognizer reached
its ended action and the model reported `full=true state=connected`, while
native view updates retained `full=false`. The input identity was published
before the fullscreen layout value, allowing a synchronous rebuild with stale
layout. Fullscreen is now changed before input identity, inside the same
animation. Both language-specific fullscreen/recovery tests passed in
`/tmp/aetherscreens-navigation-order.xcresult`. The diagnostic instrumentation
was removed; final tests add three additional enter/exit cycles per language,
each requiring one gesture and no remote pointer packets.

The controlled runner now enumerates all ten requested cases before execution
and rejects discovery omissions. An earlier incremental build executed only
eight old cases despite reporting test success; its guarded run was rejected
and preserved in `build/ios-navigation-gestures-controlled-qa`. A fresh derived
data directory restored discovery. No skipped or missing case counts as a pass.

Current core validation passed 141 tests with five environment skips and no
failures (`/tmp/aetherscreens-navigation-state-core.log`); unchanged CopyRect
threshold measured 0.677 ms/frame. Mac and signed iOS Release builds passed
(`/tmp/aetherscreens-navigation-state-mac.log`,
`/tmp/aetherscreens-navigation-state-ios.log`), and deep/strict iOS signature
verification passed (`/tmp/aetherscreens-navigation-state-signature.log`).
Final guarded acceptance passed all ten requested cases with no skips,
failures or runtime warnings (`build/ios-navigation-state-controlled-qa`).
The six exported fullscreen/restored/connection-loss screenshots in
`/tmp/aetherscreens-navigation-state-attachments` were inspected in both
languages: fullscreen hides controls, exit restores the keyboard, and failure
reveals recovery controls. At this snapshot the English connection-loss screenshot lacked the status-bar
row seen in the Chinese screenshot. The recovery-rendering follow-up below
checks settled placement and renders both rows; full physical error-layout
consistency remains in the UI acceptance gate.
Two-phone live interaction, physical smoothness and the other open acceptance
requirements above remain required before human review and release.


## Recovery rendering and physical-test preparation

Navigation gesture commit `698249b` passed CI run 36843762056. Its initial
English failure screenshot omitted the system status row. A proposed XCTest
`app.statusBars` assertion was rejected as an acceptance signal: both the
normal and recovery layouts lacked that element in the iOS 27 test hierarchy
(`/tmp/aetherscreens-statusbar-fresh.xcresult`, four assertion failures).
A reused diagnostic test-plan path also executed the previous test body rather
than the new assertions; it is not evidence for the new checks. Fresh test-plan
paths are required.

The replacement waits for recovery's Session Options button to return to the
normal layout's vertical position, then captures the screen. Both languages
passed (`/tmp/aetherscreens-recovery-geometry.xcresult`). The exported recovery
screenshots show the system clock and connectivity row in both languages.
Pixel comparison locates the toolbar at the same rows in English and Chinese.
An experimental safe-area branch refactor passed two targeted tests but did
not improve that measured placement, so it was removed. No speculative product
layout change remains. Physical error-state layout acceptance remains required.

The controlled fixture defaults to loopback and can explicitly bind a local
LAN interface. The runner now supports either a simulator or a signed USB
physical-device destination and injects the fixture host plus independently
configurable RFB, dual-display RFB and HTTP inspection ports. Separate fixture
processes/port sets keep simultaneous phone runs from sharing event resets or
socket interruption commands. Defaults remain 5999/6000/8768. A loopback address
or missing signing team is rejected for physical runs before build/execution.

The LAN-address controlled simulator suite passed all ten requested cases with
zero skips, failures and runtime warnings
(`build/ios-lan-controlled-native-qa`). This validates network routing to the
received-event service, not Apple Screen Sharing or physical hand feel.
Two simultaneous real TCP handshakes then demonstrated event isolation:
resetting/dropping the 5999/8768 lane preserved the 6999/8868 lane's existing
key record and delivery of a subsequent key
(`/tmp/aetherscreens-fixture-isolation-smoke.log`). Alternate-port UI validation
passed exactly the Chinese display-selection and English fullscreen/recovery
cases, with no skips, failures or runtime warnings
(`/tmp/aetherscreens-isolated-ports.xcresult`). Execution logs confirm entry
of ports 7000 and 6999; the inspection service ran on 8868. Python syntax,
missing physical signing/LAN arguments and out-of-range TCP ports were also
checked. These port-plumbing checks do not replace the separate physical gate.

The iPhone 12 Pro reconnected over USB and reported unlocked; developer mode
was enabled and its development disk image reported compatible/usable.
A signed physical UI test build succeeded, but preflight discovery's runner
failed to initialize with `Timed out while enabling automation mode`
(`build/ios-12-controlled-native-qa`). The guard rejected the run even though
xcodebuild printed test success. A separate one-case direct execution repeated
the same initialization timeout (`/tmp/aetherscreens-native-12-direct.xcresult`)
without executing a functional case. The human has been asked to confirm any
phone-side UI Automation/password prompt and its developer setting. No device
password is collected by the test. The 16 Pro Max remains unavailable. Neither
physical run nor the whole original goal is accepted by these controlled results.

For parallel physical QA, start one fixture per phone on separate ports and
use different derived-data/output directories. For example, lane A uses
5999/6000/8768 and lane B uses 6999/7000/8868; pass the same local LAN address
through `--listen-host` on each fixture and `--fixture-host` on each runner.
Use `--device-id`, `--development-team`, `--rfb-port`, `--display-rfb-port` and
`--http-port` explicitly. These are test fixtures containing no real desktop
content or credentials; stop each owned process when its run ends.


## Performance measurement correction (2026-10-01)

The renderer now counts successful drawable presentation callbacks, rather than
command-buffer submissions. Zero/invalid presentation times and callbacks from
an ended session are rejected. Metal's simulator SDK does not expose these
callbacks, so the simulator does not manufacture a presentation FPS value.
See [Apple drawable presentation time](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime).
FPS describes presented updates during a sample interval; a static desktop or
this event-driven fixture is not a throughput benchmark.

The existing connection's transfer reports supply TCP RTT, collected at most
once per second while sending existing traffic. No probe traffic or idle timer
is added. The expanded EN/ZH badge names this value TCP RTT / TCP 往返 and its
help text excludes remote processing/display latency. It cannot measure
finger-to-screen latency or establish Screens-equivalent fluidity.
See [Apple transport RTT](https://developer.apple.com/documentation/network/nwconnection/datatransferreport/pathreport/transportsmoothedrtt).
Session start/end/failure clears metrics and rejects queued old-session
publications. The core suite passed 144 tests with five environment skips and
no failures (`/tmp/aetherscreens-presentation-rtt-core-final.log`). An actual
loopback TCP test obtained a positive kernel RTT and separately awaited the
peer's pointer receipt. An initial test incorrectly assumed the report callback
implied peer receipt; its failure log is retained and the wait was corrected.
Mac Release and signed iOS device Release builds passed, including strict
signature verification. The initial simulator build exposed the unavailable
Metal API and was corrected with an explicit simulator conditional.

An isolated native Mac QA bundle connected to a separate NoAuth loopback
fixture on 7999/8000/8968. Its visible Chinese badge reported positive
presentation FPS and TCP RTT, and the English badge reported TCP RTT and
throughput. Screenshots and accessibility evidence are saved as
`/tmp/aetherscreens-presentation-rtt-native-{zh,en}.png` and
`/tmp/aetherscreens-presentation-rtt-native-{zh,en}-ax.txt`.
No user account credentials, installed product, or saved computer library were
changed. This is native presentation/label evidence, not iPhone acceptance or
an Apple Screen Sharing speed comparison. Physical fluidity and the original
full functional acceptance remain open; no public release is authorized by
these measurement checks alone.

The corrected fresh simulator build then executed all ten requested English/
Chinese controlled cases successfully, with zero skips, failures and runtime
warnings (`build/ios-presentation-rtt-fixed-controlled-qa`). Both fullscreen,
display-selection, viewport-navigation, recovery and received-native-gesture
lanes passed. The failed initial build is retained separately at
`build/ios-presentation-rtt-controlled-qa`.
A current read-only check reached the target Mac over SSH, but CoreDevice did
not offer an available connected physical-iPhone testing tunnel. The user's
manual iPhone 12 Pro connection/basic-operation result stands; its reported
lack of Screens-level smoothness remains unresolved. Do not infer two-phone
acceptance from the successful simulator lanes.


## Negotiated ZRLE compressed display (2026-10-01)

The client now advertises implemented ZRLE before Zlib, retaining CopyRect and
Raw fallbacks. This adds a lossless encoding option; it does not implement
adaptive JPEG quality or establish that the target Apple server will choose it.
The decoder implements the tile modes and compact BGR pixels for the BGRA32
format the client requests, following
[RFC 6143 section 7.7.6](https://www.rfc-editor.org/rfc/rfc6143.html#section-7.7.6).
ZRLE maintains its own continuous zlib dictionary, separate from ordinary Zlib
rectangles, and resets it on reconnect. Variable inflation uses bounded chunks;
rectangle output is limited to 256 MiB and tile/compressed lengths are checked
before decoding. Invalid indices, reserved modes, overruns, missing data and
trailing tile data reject the entire failing rectangle before framebuffer writes.
New connection failures have matching English/Chinese resource entries.

Twelve decoder tests cover BGR/alpha conversion, edge tiles, packed palette
row padding, non-power-of-two palettes, long runs, dictionary continuation,
reset, malformed data and expansion limits. Five actual TCP tests inspect
SetEncodings and verify pixel equality through interleaved ZRLE/Zlib/Raw,
reconnect, compressed receives larger than 64 KiB, malformed-data rejection
and oversized-announcement rejection. The malformed fixture first decodes a
valid pixel before a later run fails, verifying that partially decoded pixels
never overwrite the last good framebuffer.
The first full suite passed 160 tests with five environment skips and no failures
(`/tmp/aetherscreens-zrle-core.log`); subsequent final-suite evidence follows
below, including the added reentrant-reconnect regression.
Mac Release and signed iOS Release builds, including strict signature checks,
passed. The small synthetic Full HD tile image compressed to 549 bytes from
8,294,400 Raw pixel bytes and decoded in about 3.5 ms in the debug run.
That ratio and timing describe this fixture only, not Apple desktop traffic or
physical-device responsiveness.

The controlled Python fixture has an optional `--encoding zrle` mode, creates
one compressor per connection, requires ZRLE advertisement, and records actual
encoding/payload lengths. Raw remains its default. An independent compiled
Mac QA bundle displayed the fixture's 640x360 compressed image: first payload
2,726 bytes versus 921,600 Raw pixel bytes, followed by continuous incremental
updates and received mouse events. The desktop below the toolbar shadow
matched the earlier Raw screenshot exactly, for region `(0,190,2160,1380)`;
the wider comparison correctly detects the different toolbar shadow rather
than labeling it a decoder difference. Evidence is retained at
`/tmp/aetherscreens-zrle-native.png`,
`/tmp/aetherscreens-zrle-native-events.json` and
`/tmp/aetherscreens-zrle-native-pixel-comparison.txt`.
The full-image protocol tests additionally verify complete framebuffer bytes;
this screenshot crop alone is not that assertion. The QA bundle used temporary
NoAuth loopback connections and did not replace the installed product.

Target Mac encoding selection, both physical iPhones' sustained input/scroll
feel, adaptive compression and the other original functional acceptance gates
remain open. No public release or website publication follows from these
controlled checks.

The receive-notification reconnect regression initially timed out after five
seconds, with no fresh frame and only one negotiated connection
(`/tmp/aetherscreens-zrle-reentrant-first.log`). A post-notification connection
identity guard prevents an old receive from reading the new handshake or
reporting errors against the new socket. The same real TCP scenario then passed
in about 0.09 seconds with complete pixel equality
(`/tmp/aetherscreens-zrle-reentrant-fixed.log`). Stream dictionaries now reset
on the serial connection queue's ready callback, not concurrently from the UI;
ZRLE completion also rejects pixels/errors belonging to an old connection.
This is reconnect-race evidence, not a measured fix for sustained iPhone lag.

The first incrementally rebuilt iOS package printed BUILD SUCCEEDED while
strict codesign verification rejected changed English/Chinese resource files
(`/tmp/aetherscreens-zrle-incremental-signature-check.log`). The candidate was
rebuilt in a fresh derived-data directory and subsequently rechecked. Do not
accept Xcode's build-success message alone as signature verification.

Final source passed 161 core tests with five environment skips and zero failures
(`/tmp/aetherscreens-zrle-core-verified.log`). Mac Release build passed
(`/tmp/aetherscreens-zrle-mac-verified.log`). The iOS Release build at
`/tmp/aetherscreens-zrle-queue-final-signed-derived` passed strict/deep signature
verification after the final code rebuild; its build log is
`/tmp/aetherscreens-zrle-ios-verified.log`.

Both initial and queue-reset controlled simulator runs passed all ten requested
ZRLE EN/ZH cases with zero skips, failures and runtime warnings
(`build/ios-zrle-controlled-qa`, `build/ios-zrle-final-controlled-qa`). The final
receive-notification guard is being verified separately below before acceptance.

A current device check found the 12 Pro wired/connected, booted, unlocked, with
developer mode enabled; the 16 Pro Max's network development tunnel was
still disconnected (`/tmp/aetherscreens-zrle-current-devices.json`). The 12 Pro
was retried in its own ZRLE LAN lane on 6999/7000/8868, independently of the
simulator lane. Its signed test build succeeded, but runner 14452 again timed
out enabling UI automation during test discovery. The enumeration guard
rejected all ten missing tests (`build/ios-zrle-12-controlled-qa`). No physical
functional case executed. The prior phone-side automation confirmation remains
required; no device password is entered or collected by the tools. This does
not invalidate the user's earlier manual basic-operation result, and does not
prove a new installed product revision or two-phone acceptance.

The final receive-notification guard's fresh simulator run passed all ten
requested controlled EN/ZH cases, with no skips, failures or runtime warnings
(`build/ios-zrle-reentrant-controlled-qa`). Final event evidence is saved at
`/tmp/aetherscreens-zrle-final-ui-events.json`.
A subsequent internal buffer-ownership correction uses explicitly aligned
UInt32 storage, transferring it to Data after successful decoding and freeing
it on failure. It preserves the tested pixel bytes and avoids relying on Data's
inline byte-buffer layout. All 161 core tests then passed again, with the same
five environment skips and zero failures
(`/tmp/aetherscreens-zrle-aligned-core.log`); the aligned implementation's Mac
Release and signed iOS Release builds also passed. Final strict/deep signature
verification succeeded (`/tmp/aetherscreens-zrle-final-signature.log`). The UI
run preceded this internal allocation correction; protocol tests afterwards
verify every received framebuffer byte and reconnect behavior with the new
allocation. No UI layout or gesture mapping changed in that correction.
The full original acceptance remains incomplete and awaits the separate
physical/Apple-server gates listed above.


### Exact Zlib rectangle acceptance — 2026-10-01

The subsequent Zlib audit reproduced an independent correctness defect:
`decompress(expectedBytes:)` accepted both an eight-byte output for a declared
twelve-byte rectangle and the first four bytes of an eight-byte output for a
four-byte rectangle. Both rejection assertions failed against the previous
implementation (`/tmp/aetherscreens-zlib-exact-before.log`). The separate
512-rectangle persistent-stream test passed before the fix; this audit does
not claim that valid continuous Zlib updates were previously broken.

The exact-size decoder now uses bounded, fully consumed inflation and requires
exactly the declared pixel count. The Zlib transport validates rectangle bounds
and compressed lengths before reading/allocating, checks connection identity
around reads and decoding, and fails instead of publishing a malformed frame.
The new failure messages have matching English and Chinese catalog entries.
This follows the [RFB Zlib extension definition](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#zlib-encoding):
one ordered stream per connection carrying Raw-format rectangle pixels.

Actual TCP tests verify short/oversized pixel payloads, oversized announced
length and out-of-bounds rectangles preserve the preceding valid framebuffer.
The mixed-encoding test now receives five rectangles including two ordinary
Zlib rectangles interleaved with persistent ZRLE and Raw, and repeats after
reconnect. The 512-rectangle test alternates four-byte and 65,540-byte payloads
and checks complete pixel equality on every update.

All 167 core tests completed with five environment skips and zero failures
(`/tmp/aetherscreens-zlib-bounded-core.log`). Mac Release and fresh signed iOS
Release builds passed (`/tmp/aetherscreens-zlib-bounded-mac.log`,
`/tmp/aetherscreens-zlib-bounded-ios.log`); explicit deep/strict iOS signature
verification passed (`/tmp/aetherscreens-zlib-bounded-signature.log`). The iOS
build emitted only its existing AppIntents metadata-extraction warning. This
transport-only change does not rerun or replace the prior ten-case controlled
UI evidence, nor prove physical-device fluidity. Current read-only device
inspection still finds the 12 Pro connected and the 16 Pro Max paired rather
than connected (`/tmp/aetherscreens-current-devices-oct1.json`). Full physical
acceptance and user review remain open; nothing has been publicly released.

## Retained iOS sessions and VM automation policy (2026-10-01)

Returning to the computer library keeps the connection and viewport alive. The
Open Sessions menu selects the existing session without another handshake.
Selection releases hidden buttons/modifiers, disables hidden input, and rejects
queued or newly received hidden clipboard callbacks. Observe survives selection;
closing one session leaves the other connected.

The final controlled English/Chinese iPhone 13 mini simulator suite executed
12 tests with zero failures, zero skips and no runtime warnings. Packet assertions
verify two connections, selected-session clicks, Observe suppression and closing
one connection while using the other. Core suite: 169 tests, 5 explicit live-environment
skips, no failures. Mac Release and signed iOS device Release builds and strict
signature verification pass. Screenshots reviewed in both languages confirm the
375-point library title remains readable after adding Open Sessions.
Evidence: `build/ios-mobile-sessions-layout-controlled-qa/result.xcresult` and
its `summary.json`. Earlier runs failed because numeric-keyboard clearing and
offscreen Esc automation were incorrect, and one pointer assertion included a
legitimate zero-button cursor event. Those failures were retained, the automation
was corrected, and the complete suite rerun; none were counted as acceptance.

The user requires future UI automation to execute inside the existing `macos27`
VM. The host simulator suite above had already started when that instruction
arrived and was allowed to finish. Future UI runs use the VM; physical iPhone
acceptance remains separate. The VM has macOS 27.0 and an isolated Xcode 27.0
copy; recognizing the tools is not itself UI acceptance. A dedicated Mac XCTest
project at `macos/UITests/AetherScreensMacUITests.xcodeproj` targets a separately
identified QA app via `AETHERSCREENS_MAC_QA_APP_PATH`. Its initial two-language
cases cover Quick Connect, valid/invalid port gating and cancellation. This is
initial VM coverage, not full Screens parity or release approval.

The initial VM `build-for-testing` completed successfully. Actual
`test-without-building` launched the runner, then showed the system
“XCTest / Enable UI Automation” authentication dialog. The runner subsequently exited 65 after
`Timed out while enabling automation mode`; no functional test ran. Human
authentication is pending; no Mac VM functional case is counted as passed yet. The existing VM
and other projects were not reset. Passwords are neither scripted nor recorded.

## 4K compact-pixel decoding and repeatable VM runner

A 3840x2160 high-entropy raw-tile ZRLE fixture verifies every decoded pixel over
three frames using the persistent zlib dictionary. Before optimization, Release
samples were 21.9/22.1/23.8 ms; after checking each compact-pixel tile in one
bounded read instead of three throwing byte reads per pixel, samples were
17.5/17.1/16.5 ms. The full-core run measured 17.7/18.0/18.0 ms and passed
171 tests with 5 live-environment skips. Truncation of any of the last three
compact-pixel bytes in a final 1x1 edge tile is explicitly rejected. These are
host CPU/fixture samples, not a claim about physical-iPhone latency, network
adaptation or Screens smoothness. Logs are under `/tmp/aetherscreens-zrle-4k-*`
and `/tmp/aetherscreens-zrle-tile-bounds-core.log`.

`scripts/qa/run_macos_vm_ui_qa.py` supplies a repeatable VM UI entry point. It
resolves an existing Tart VM, requires macOS 27 and `kern.hv_vmm_present=1`,
requires a separately identified `.vmqa` app, copies into a fresh guest directory,
builds XCTest in the guest, configures the QA app path and retrieves the actual
result bundle. The acceptance gate requires exactly two passing initial Mac UI
cases and no failures, skips or runtime warnings. It does not restart a VM,
retry a timed-out test or enter a password. Syntax/help and refusal of a
non-isolated app were verified; end-to-end VM execution awaits human automation
authentication as recorded above.

Example (use the current isolated Xcode and freshly built QA app):

```sh
python3 scripts/qa/run_macos_vm_ui_qa.py \
  --vm macos27 --user chenxu \
  --developer-dir /Users/chenxu/aetherscreens-ui-tools.ec1zbU/Xcode.app/Contents/Developer \
  --app /tmp/AetherScreens-macOS27-VM-QA.app \
  --output build/macos27-ui-qa-new-run
```

The example QA app must be regenerated from the current Release binary before
acceptance; an older bundle or an already-used output path is not current proof.

Current decoder-change verification also passed the iOS Release device build and
strict deep signature check. Mac Release compilation is included in the Release
core-test build. No new host UI automation was started; the VM auth gate and
physical-device/full Screens requirements remain open.

## Reentrant failure teardown regression

The earlier CI run `36858535958` failed in
`testReconnectFromReceiveNotificationCannotConsumeOldPayloadOnNewConnection`
with an EOF notification; its following run `36858571568` passed. The exact
interleaving of that intermittent EOF is not proven by the CI text. Inspection
found cancellation preceded invalidating the connection reference, and failure
notifications preceded all teardown. A new deterministic TCP test reconnects
synchronously from the failure notification after a malformed ZRLE rectangle.
Before repair it timed out and never negotiated the second connection (four
assertion failures); after repair all ten ZRLE transport cases pass. Both teardown
paths now invalidate the old connection before cancelling it; the failure path
finishes old teardown before publishing the failure. The new test proves the
replacement completes its handshake, publishes the expected full image and
remains connected. It does not ignore any failure or weaken the EOF assertion.
Evidence: `/tmp/aetherscreens-reentrant-failure-before.log` and
`/tmp/aetherscreens-reentrant-failure-after.log`.

After repair, all ten TCP transport cases passed 20 consecutive executions
(200 actual cases, no failures). The complete Release core suite passed
172 tests with 5 explicit live-environment skips. Mac Release compilation,
iOS Release device build and strict deep iOS signature verification passed.
The preceding pixel-decoder/VM-runner commit `5e61aa1` passed CI run
`36859071018`; the teardown repair needs its own exact-commit CI evidence.
The VM's required human UI automation authentication is still outstanding.

## Handshake state notification replacement guards

The connected-state observer can synchronously disconnect/reconnect just like a
failure observer. A new actual-TCP regression reproduced the original bug:
after the callback, the old session issued update/read work on the replacement
socket, which remained in version negotiation and never produced the expected
frame (five assertion failures). Handshake state changes now retain the publishing
connection identity and return when the observer replaces it. The initial
connecting notification similarly returns if its attempt was cancelled or a
nested connect already created the replacement.

Five regressions cover connecting, version negotiation, authentication,
initialization and connected notifications. They verify exactly one replacement
frame, complete expected pixels, the final connected state, accepted socket
counts and the replacement's encoding negotiation. The fixture counts accepted
sockets separately from SetEncodings packets: cancellation need not flush the
old socket's pending message. No unexpected connection failure is ignored.
The initial 15-case TCP suite passes. Evidence:
`/tmp/aetherscreens-state-reconnect-before.log` (reproduced failure) and
`/tmp/aetherscreens-state-reconnect-verified.log` (15 passing TCP cases).
The VM automation authentication and all physical/full Screens acceptance gaps
remain open.

The 15 TCP cases then passed 20 consecutive Debug executions (300 actual
cases). Complete current Release core regression: 177 tests, 5 explicit
live-environment skips, no failures. Mac Release compilation, iOS Release device
build and strict deep signature verification passed. No new host UI automation
was started. Previous teardown commit `506b248` passed all steps in CI run
`36859492030`; this state-notification repair requires its own current-commit CI
result. Logs: `/tmp/aetherscreens-state-reconnect-repeat.log`,
`/tmp/aetherscreens-state-reconnect-core-release.log`,
`/tmp/aetherscreens-state-reconnect-ios.log` and its signature log.

## macOS 27 VM page-flow gate and storage cleanup

Commit `5368e3c6e0231d2f46919c5a2a04e14e5c10b0ca` passed CI run
`36859988746`. UI acceptance remains a separate gate. The user requested VM
storage cleanup during the first controlled run; seven cases had passed before
the run was interrupted. Its logs and partial bundle are preserved under
`build/macos27-cleanup-evidence-20261001`. Cleanup reclaimed 7,421,284 KiB
inside the VM, retaining Xcode and the installed verified simulator runtime.

The subsequent page-flow gate executes seven actual iOS simulator cases inside
the macOS 27 VM: language persistence, Chinese error/retry, both narrow keyboard
customization flows, add/edit/settings/logs, Quick Connect validation/temporary
saving, and received-frame/landscape behavior. The first complete execution
passed six cases and failed Quick Connect with five assertions, no skips or
runtime warnings. Evidence is
`build/macos27-library-qa-before/library-result/result.xcresult` and
`build/macos27-library-qa-before/summary.json`. A short numeric value was edited
with the caret before its digit, producing `59000` instead of `5900`; the two
coordinate-based save-switch taps did not produce the expected state sequence.
The retained screenshot shows saving enabled when the test expected it disabled.

The revised test moves the caret through existing digits before deletion. A
standard switch tap still failed; subsequent keyboard-visible recordings and
hit-target checks motivated explicit keyboard dismissal and an interior switch
coordinate. The received-frame case now explicitly
requires `remote-desktop-frame`, preventing a connection error from passing as
a received desktop. These changes require their own passing VM result.

Xcode's failed-run finalization was waiting in
`collectSimulatorDiagnostics` on its child `simctl diagnose --timeout=600`.
Only that optional diagnostic child was terminated to limit storage and finish
the result; the test run exited 65 and its failures remain recorded. Future
controlled/library runs use `-collect-test-diagnostics never`, supported by
the guest Xcode, preserving assertion logs, screenshot attachments and the
result bundle without automatic full simulator sysdiagnose collection.
The current VM workspace reuses one DerivedData directory. Native Mac UI still
requires human Automation Mode authentication; physical input, Screens
responsiveness and all remaining feature rows above are not accepted by these
simulator results.

Follow-up page runs again passed six cases but failed Quick Connect. Recordings
showed the keyboard still covering the save control. Add, Quick Connect and Edit
forms now share explicitly tracked input fields and a localized keyboard Done
button; Chinese numeric input and English Add/Edit dismissal passed. The initial
keyboard-toolbar version also produced six `Invalid frame dimension` runtime
warnings, so it has not passed the strict gate. Evidence:
`build/macos27-library-qa-keyboard-failure/summary.json`.

A focused Quick Connect run subsequently verified both switch changes, but its
final fixed-host assertion found data saved by an earlier failed test. The test
now uses a unique `.invalid` host, asserts it absent before starting and after
disconnect, and explicitly asserts saving returns to zero. Compilation and
installed test-bundle hashes matched while execution logs still used the old
fixed address/line number. Removing only the owned XCTest runner from the
dedicated simulator made execution use the freshly compiled unique address.
The runner now refreshes its simulator-only test runner after building, preserving
the application data and leaving physical installations unchanged. `--case` can
select unique cases from a suite for diagnosis; the default still requires the
entire configured library/controlled suite and all existing exact-count/warning
checks (the library list was subsequently expanded to eight cases).

The fresh-runner Quick Connect case passed all assertions with no skips, but one
layout warning remained and the strict script correctly failed it. Evidence:
`build/macos27-quick-save-fresh-runner/quick-save-fresh-runner-result/summary.json`.
Removing the keyboard toolbar's flexible spacer still passed the focused case
with a layout warning; its result is retained under
`build/macos27-quick-save-compact-toolbar`. The dismissal control now uses a
shared system-styled button bar above the keyboard via the form's safe-area
inset, with a 44-point button. This adjustment is being tested again; there is
no warning suppression or complete page-flow acceptance yet.
Release regression of the first toolbar version passed 177 core cases with five
live-environment skips, iOS device Release compilation and strict signature
verification. Logs: `/tmp/aetherscreens-connection-form-core-release.log`,
`/tmp/aetherscreens-connection-form-ios-release.log` and
`/tmp/aetherscreens-connection-form-ios-signature.log`. Later toolbar adjustments
require final build/regression validation.

The shared safe-area Done bar passed the focused Quick Connect gate with exactly
one executed/passing case, zero skips/failures and no runtime warnings. Evidence:
`build/macos27-quick-save-verified/quick-save-safe-area-result/summary.json` and
its actual result bundle. The runner-refresh log is retained with this run.
Current Release regression passed all 177 core cases with five live-environment
skips, iOS device Release compilation and strict deep signature verification.
Logs: `/tmp/aetherscreens-connection-form-final-core-release.log`,
`/tmp/aetherscreens-connection-form-final-ios-release.log` and
`/tmp/aetherscreens-connection-form-final-ios-signature.log`.
The complete seven-case VM page-flow suite is now executing against this form
version; the one-case result is not complete page or release acceptance. Full
controlled input/session flows and all physical/Screens feature gaps remain.

The complete seven-case VM page-flow gate then passed: seven executed and
passing, zero failures/skips and no runtime warnings. Its actual result bundle,
summary, test inventory and runner-refresh log are preserved under
`build/macos27-library-qa-verified/library-final-result`. Chinese numeric-keyboard
and English form dismissal screenshots were inspected; the shared Done bar is
visible above the keyboard with consistent spacing and no title/control overlap.
A new Chinese Quick Connect case runs the same full validation/save-toggle/error/
temporary-session assertions as English. The complete library gate now requires
eight cases; its current VM execution must finish before claiming that expansion.

Current real Apple-server acceptance also passed two separate opt-in tests
against `192.168.50.226`: protocol/auth-challenge negotiation, and the full account
session using this application's saved credential via Keychain. The latter
received 3840x2160 frames, asserted the connection stayed active for 60 seconds,
and verified intentional disconnect did not fail. Each executed one passing test
with no skips. No credential was supplied in the command/output and no pointer,
keyboard or clipboard input was injected. Evidence:
`build/current-apple-live-readonly-qa/summary.json`, `handshake.log` and
`session.log`. This is current-source Mac-client/LAN/server reception proof,
not physical iPhone input, real Tailnet-route proof, Screens responsiveness or
completion of the remaining feature rows.

The expanded eight-case VM library suite subsequently passed all eight cases,
with exact test inventory, no failures/skips and no runtime warnings. Both
languages now execute Quick Connect validation, saving on/off, failed connection
recovery and temporary non-persistence. Evidence:
`build/macos27-library-bilingual-qa-verified/library-bilingual-final-result`.
The twelve-case controlled remote-input/session suite has been started in the
same VM against this current source and must finish before acceptance. The real
Apple input-fixture endpoint on port 8766 is currently stopped, so the read-only
server successes do not substitute for renewed received-input verification.

### Current VM full controlled gate and real Apple input verification

The current-source twelve-case controlled VM gate completed successfully:
exactly twelve requested cases executed and passed, zero failures/skips and no
runtime warnings. The actual result bundle, test inventory, summary and logs are
preserved under `build/macos27-controlled-qa-verified/controlled-final-result`.
Both languages cover received native gestures, fullscreen, viewport navigation,
display selection, reconnect and retained mobile-session selection. This is
simulator/controlled-server evidence, not physical iPhone or Apple clipboard
acceptance. After verifying every copied file's SHA-256, the completed VM output
and DerivedData were removed, the owned fixture stopped, and only the dedicated
QA simulator was shut down and erased. Xcode and the installed runtime remain.
VM free space is approximately 20 GiB; source staging is 7.7 MiB.

The current Mac core client also passed received-input verification against the
real Apple server at `192.168.50.226`: clicks, Observe-mode input suppression with
continued frames, cancelled delayed wheel work, resumed control, exact English
text and scrolling. A separate passing run verified exact Chinese committed
text and a fresh Chinese character via the X11 Unicode keysym used by production
`sendText`. Each ran one actual test with zero skips. Evidence is retained under
`build/current-apple-live-input-qa`; this is LAN Mac-client input proof, not
physical-phone gesture smoothness, physical IME or bidirectional clipboard proof.

The live test can now retrieve this application's saved Keychain credential for
an explicitly supplied target instead of requiring a password environment
variable. Target, controlled coordinates and SSH fixture access remain mandatory;
without them the normal regression run still skips input injection. Fixture
availability is checked before connecting, and the client disconnects on thrown
errors. Click receipt is polled for a bounded five seconds instead of assuming
delivery within one second. Clipboard checks now require a successful queue
operation and a fresh observed paste, preventing an old paste event from
satisfying acceptance.

Clipboard acceptance remains failed: the raw-codepoint diagnostic did not insert
a Chinese character (the production X11 encoding did), and a combined X11/Chinese
clipboard run pasted a different prior value. An ASCII clipboard run also pasted
an empty value. These failed logs are retained. The system Screen Sharing
connection was then closed to isolate its clipboard synchronization. That check
also failed to observe its initial click and a fresh paste, so it does not
establish a clipboard-only server defect: the controlled page's active input
context must be re-established before repeating isolated clipboard acceptance.
The [iShareScreen implementation's experimental Apple extension specification](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md)
describes separate Apple pasteboard control messages and archive transport. It is
a reverse-engineered implementation reference, not Apple documentation or proof
that this client's standard RFB clipboard reaches the Apple pasteboard. Protocol
integration and renewed actual receipt are still needed; no release acceptance
has been declared.

The final test-harness changes passed the complete Release regression: 177
executed cases, five explicit live-environment skips, zero failures. Log:
`/tmp/aetherscreens-current-live-qa-harness-regression.log`. The failed real-server
checks remain failed evidence and are not counted as passing functional gates.

### Apple supplementary Unicode compatibility fix

A renewed real-server test on a fresh, focused controlled page reproduced exact
text loss: `中文🙂𠮷 QA 123` arrived as `中文 QA 123`. The target advertised
`RFB 003.889`. A diagnostic sending X11-tagged UTF-16 units instead of a single
non-BMP scalar produced a complete emoji in the browser. Intermediate DOM events
contained an unpaired high surrogate, which Foundation's JSON parser rejected;
the fixture now preserves original UTF-16 units and an explicit unpaired flag,
while its JSON display strings replace only invalid isolated units. Final valid
characters are retained unchanged, and actual final-value assertions remain exact.
Original raw events and diagnostic failure logs are preserved.

Production `sendText` now sends complete UTF-16 pairs only for the exact Apple
3.889 banner. The flag resets on each connection; per-scalar recursive locking
keeps the pair together through input gating. Standard RFB still sends one full
X11 scalar. Two actual TCP cases assert both wire formats, balanced down/up
events, subsequent ASCII delivery and Observe suppression. The complete ten-case
PointerTransportTests suite passed with zero skips/failures. The renewed real
Apple test passed with exact `中文🙂𠮷 QA 123`, no unpaired surrogate in the final
value, and continued click/Observe/resumed-control/scroll assertions. This is
Mac-core-client/Chrome acceptance, not physical iPhone, arbitrary native IME or
dictation acceptance.

Evidence: `build/current-apple-live-input-qa/supplementary-unicode-fixed-pass.log`,
`supplementary-unicode-fixed-events.json`, `unicode-wire-release-pass.log` and
`unicode-fix-source-sha256.json`. The inactive-page guard was also verified on
the actual target: it rejected input before connecting and remote events remained
unchanged (`inactive-page-guard-summary.json`). Final Release regression passed
179 cases with five live-environment skips and zero failures. Signed iOS device
Release compilation and strict deep signature validation passed. Logs are retained
in the same evidence directory. The post-Unicode-fix twelve-case VM controlled suite completed: 12 passed, zero
failures/skips/runtime warnings. All 151 result files were copied and SHA256
matched before guest results, DerivedData and dedicated simulator data were
cleaned. Evidence: `build/macos27-controlled-unicode-qa-verified/controlled-unicode-result`.
This VM snapshot predates the Apple clipboard additions. Earlier twelve-case
results remain pre-Unicode-fix evidence. Publication remains pending full
functional/device acceptance and user review.


### Modern Apple text clipboard integration, October 1

Explicit real-target probes confirmed that modern typed pasteboard packets work
in the tested Apple 3.889 account session: exact `Apple 双向🙂𠮷 clipboard QA`
was pasted on the controlled browser page and fetched back through RFB. The
normal `sendCutText` path then passed exact `正常路径 双向🙂𠮷 QA`, with initial
monitoring enabled at connection setup. Logs: `build/current-apple-live-input-qa/apple-pasteboard-bidirectional-probe-pass.log`
and subsequent integration logs. This proves text transfer to and from the
actual Mac pasteboard; it does not yet prove independent remote-copy change
notifications, physical iPhone clipboard behavior, images or rich content.

The implementation uses existing zlib, bounds archives at 16 MiB and uploaded
UTF-8 text at 1,048,000 bytes. Four independent codec cases passed: exact Unicode
archive layout, alias parsing and UTF-8 preference, truncation/length rejection,
and declared-size decompression bounds. The first 22-case codec/TCP/session
regression passed without skips or failures. Additional malformed-header and app paste-action tests passed in the final full
Release regression: 189 total, five explicit environment skips, zero failures.
UTF-16 byte-order and traditional MacRoman decoding fixtures also passed.
The app's Paste Text action now queues the Apple archive and Cmd-V together;
standard server text insertion remains supported. Direct live acceptance of that immediate paste transaction passed with exact
`应用粘贴路径🙂𠮷 QA`. The post-integration signed iOS Release build and strict
deep signature verification passed.


Remote-copy notification initially failed the real acceptance gate. The first
probe did not establish replacement of the controlled textarea; that failure
was retained. The second probe explicitly waited for an empty textarea and
then exact `复制新样本🙂𠮷 QA remote copy` before issuing Cmd-A/Cmd-C; the
expected new-text callback still timed out after eight seconds. Initial fetch
and explicit round-trip success therefore do not establish automatic remote
copy synchronization. Failed logs and synthetic fixture events are preserved
in `build/current-apple-live-input-qa/apple-pasteboard-notification-verified-fixture.log`
and `apple-pasteboard-notification-events.json`. Further diagnosis must prove
the actual copy event before attributing failure solely to notification framing.
No unexpected remote clipboard contents were logged. This change has not been
accepted on physical iPhones or included in the completed VM UI source snapshot.


### Apple automatic clipboard notification repair, October 1

The controlled browser now logs its real copy event and selected test text.
With that receipt confirmed, the client still received no status notification,
while a separate diagnostic explicit fetch returned the exact newly copied text.
The source of failure was therefore separated from pasteboard archive decoding.
Failed automatic logs and successful diagnostic fetch logs remain distinct.

Registering Apple ViewerInfo's MSB-first server-command bitmap enabled the
missing status messages. The independent Swift encoder declares only handled
commands 0, 2, 3, 20 and 31, using the existing plaintext Apple-compatible
account connection; it does not add unsupported encrypted records or media
encodings. The controlled opt-in probe passed first, then the default connection
path passed independently with exact `默认自动同步🙂𠮷 QA remote copy`: a real browser
copy receipt, unsolicited flags=1/command=2, automatic fetch and exact callback,
without the diagnostic refetch environment flag. Initial download, local upload
and immediate Cmd-V paste also remain in the same real scenario.

Evidence: `build/current-apple-live-input-qa/apple-copy-event-notification-live.log`
(failed), `apple-copy-explicit-refetch-live.log` (explicit diagnostic fetch),
`apple-viewer-info-notification-live.log` (opt-in registration), and
`apple-automatic-clipboard-default-live.log` (normal production path). Metadata
logs include header sizes and numeric status only, never unexpected clipboard
contents. Routine heartbeat messages are omitted from the diagnostic buffer.

The Release core suite passed 191 total cases with five explicit live-environment
skips and zero failures. It includes independent ViewerInfo bitmap/length checks,
actual TCP initial registration, re-registration/monitoring after reconnect,
fragmented clipboard/status framing and standard-server isolation. The updated
signed iOS Release build and strict deep signature validation passed. A new
controlled clipboard fixture and English/Chinese UI pair are now running in the
macos27 VM: real UIKit pasteboard write/read through the app's Paste Text button,
remote notification update, exact received upload/paste and Observe toolbar
suppression. Their result is not yet accepted. Existing twelve-case VM Unicode
results predate this clipboard change; physical iPhone acceptance remains open.


### Apple clipboard refresh after session selection, October 1

Background sessions discard clipboard callbacks to protect the selected session.
When an existing Apple session becomes foreground again, it now explicitly
fetches the current remote pasteboard; otherwise a copy made while hidden could
remain missing until the next remote change. Repeated selection does not fetch
again, and standard servers do not receive Apple messages.

The new real-TCP regression checks discarded background callbacks, exactly one
additional fetch, unchanged ViewerInfo registration, and the exact fragmented
Unicode archive delivered after selection. All eight clipboard session tests
passed. The full Release core suite passed 192 cases, five explicit environment
skips and zero failures in 35.630 seconds. Logs and the source hash snapshot are
in `build/current-apple-live-input-qa/apple-foreground-clipboard-tests.log`,
`apple-foreground-clipboard-core-release.log` and
`apple-foreground-source-sha256.json`. This selection change is newer than the
currently running VM UI build and has not yet received physical-device acceptance.

The first bilingual VM clipboard attempt failed while querying an offscreen
button's hittability. Its complete result bundle remains preserved. The revised
test checks toolbar bounds before querying hittability; Chinese passed in
26.531 seconds. The same English run remains live and has received both exact
clipboard paste transactions, but XCTest repeatedly reports missing animation
completion notifications, adding approximately 60 seconds per idle wait.
The run must finish before accepting its inventory, and these delays still need
diagnosis; functional clipboard receipts alone do not establish smooth UI.


### Bilingual clipboard VM result and idle-wait diagnosis, October 1

The original clipboard UI pair finished: two passes, no failures, skips or
runtime warnings. Chinese took 26.531 seconds; English took 1039.678 seconds
and reported 17 missing animation-completion notifications. Both exported
packet attachments contain the exact changed Unicode clipboard sample and
balanced paste keys; Observe screenshots show the input toolbar suppressed.
This establishes those functional assertions but does not accept the UI gate.
A two-second process sample during a wait shows the app main thread in the
event run loop, with no sampled busy loop or deadlock; it does not establish
the cause of the missing animation notification or physical responsiveness.

The complete result, summaries, inventory and exported attachments are preserved
in `build/macos27-clipboard-bilingual-fixed-verified/clipboard-bilingual-fixed-result`.
All 64 files match their guest SHA-256 hashes. The separate
`acceptance-assessment.json` rejects UI acceptance because of the 17 timeouts.
The QA driver now retains failure summaries and explicitly rejects missing
animation-completion notifications, including when assertions pass.

The updated bilingual cases also return to the library, change the remote
clipboard while the session is hidden, reselect the existing socket, require a
fresh download and paste the exact updated string through UIKit. A fresh
English-only run of that new source is underway in the same macos27 workspace
and reusable DerivedData. It isolates cross-test ordering from the earlier
Chinese-then-English pair; no animation waiting or product animations have been
disabled to obtain a pass.


### Updated clipboard selection VM acceptance, October 1

The fresh English-only updated scenario passed in 41.206 seconds with no
missing animation-completion notifications. The subsequent complete bilingual
pair also passed: Chinese 40.494 seconds, English 41.298 seconds, two total
cases, zero skips/failures/runtime warnings and zero animation timeouts.
Both cases include the hidden-session remote copy, selection-triggered refresh,
existing-connection reuse, exact UIKit upload/paste and Observe suppression.
The current clipboard UI sub-gate is accepted; the earlier 17-timeout incident
remains retained and its root cause is not established by these later passes.
This does not prove physical-device responsiveness or complete Screens parity.

Evidence is in `build/macos27-foreground-clipboard-english-verified` (57 files
SHA-256 matched) and `build/macos27-foreground-clipboard-bilingual-verified`
(65 files matched). The guest's eight relevant source/test/driver files match
`build/current-apple-live-input-qa/apple-foreground-vm-source-verified.json`.
Both `gate.json` reports require exact requested test inventories and no missing
animation-completion notifications. The updated signed iOS Release build and
strict deep signature verification also passed; their logs are
`apple-foreground-clipboard-ios-release.log` and
`apple-foreground-clipboard-ios-signature.log`. Physical-device, rich clipboard
and the other requirements in the table remain open.


### Full controlled regression and rejected paste handling, October 1

The foreground-refresh source completed all twelve controlled VM interaction
cases: exact inventory, zero skips/failures/runtime warnings and zero animation
completion timeouts, in 504.589 seconds. The full result, exported attachments
and source snapshot are retained in
`build/macos27-foreground-controlled-full-verified/foreground-controlled-full-result`;
205 files match the guest SHA-256 hashes. This snapshot precedes the following
new paste rejection handling.

Apple paste submission now distinguishes unsupported protocol from a rejected
upload. Only unsupported standard-server clipboard paste falls back to text
insertion; a rejected Apple upload cannot flood the connection with key events.
The session bounds UTF-8 clipboard text before any modifier release or input,
shows a localized native alert, preserves the connection and clears stale
alerts on session lifecycle/selection/Observe transitions. The real-TCP test
uses over-limit Chinese text, verifies no upload or keys and then successfully
pastes exact supported Unicode with balanced shortcut keys. Full Release core:
193 tests, five explicit environment skips, zero failures in 36.601 seconds.
The updated iOS Release build and strict deep signature verification passed.
Evidence: `build/current-apple-live-input-qa/apple-paste-rejection-core-release.log`,
`apple-paste-rejection-ios-release.log`, `apple-paste-rejection-ios-signature.log`
and the eleven-file source hash snapshot.

The new bilingual VM UI scenario additionally downloads controlled over-limit
text, checks the localized alert and absence of key/upload/paste events, dismisses
the alert, receives a new supported clipboard and pastes it successfully.
The oversized fixture logs byte counts only; unknown clipboard strings are
never copied into its event logs. This new VM UI result remains pending.

Both physical devices regained connected development tunnels and available DDI
services on a fresh details query. Separate LAN fixture ports and independent
build directories were used for simultaneous clipboard lanes; both signed test
builds passed. iPhone 12 Pro discovery is still waiting for unlock. iPhone 16 Pro
Max discovery failed before any test executed: XCTest runner exit 74, DTX channel
disconnected before configuration receipt. Its incomplete inventory is rejected
and recorded in `build/physical-clipboard-16-current/discovery-failure.json`.
A request to USB-connect and unlock both devices is pending. None of these
discovery/build results constitute physical app or target-Mac acceptance.


The rejected-paste bilingual VM UI pair completed with exact inventory: Chinese
42.251 seconds, English 44.657 seconds, zero skips/failures/runtime warnings
and zero animation-completion timeouts. Both native alert screenshots were
visually reviewed: readable complete localized text, no clipped controls, and
normal supported paste after dismissal. The complete results and source snapshot
are in `build/macos27-paste-rejection-bilingual-verified`; all 73 files match
the guest SHA-256 hashes. This clipboard UI sub-gate is accepted. The subsequent
eight-case library/quick-connect/toolbar suite is running on the same updated
source. Physical acceptance and all other remaining table requirements persist.

The iPhone 12 Pro discovery job has now terminated too: the device remained
locked during preflight and the pending XCTest runner connection was lost
before launch. No physical clipboard cases executed on either device. Both
discovery failures remain rejected; the USB/unlock request is still pending.


### Latest library gate and cleanup, October 1

The eight-case library/quick-connect/toolbar regression finished on the rejected-paste
source: exact requested inventory, eight passes, zero skips/failures/runtime warnings
and zero animation-completion timeouts. It is retained in
`build/macos27-cleanup-20261001-final/paste-rejection-library-result`; all 142 files,
including exported screenshots, match the guest SHA-256 hashes. This result precedes
the following hot-corner implementation.

At the user's explicit cleanup request, ended build caches and verified guest report
duplicates were removed, and the dedicated QA simulator's test data was reset while
keeping its device definition and runtime. Settled free space increased by 1.86 GiB
to 20.12 GiB. The source and Xcode remain. One fixed DerivedData directory is reused
for subsequent automation; test artifacts are retained locally before guest cleanup.

### Manual remote hot corners, October 1

A shared native submenu in session options and the keyboard Actions menu now exposes
four corners in English and Simplified Chinese. It releases held buttons/modifiers,
cancels stale wheel work and moves through the selected monitor's center before
entering its exact last pixel. The trackpad cursor is updated too, so subsequent
gestures continue from the same position; zoom and touch mode are retained.
Only a foreground, connected Mac control session can trigger the action; Observe
and local Pan remain gated. The real-TCP regression verifies every selected-display
corner, repeated activation, released input and blocked modes. It passed.

The remote Mac must already have a hot-corner action configured; pointer delivery
does not establish that macOS performed that action. Actual configured-Mac acceptance,
modifier-required corners and on-disconnect execution remain open. The new bilingual
VM submenu/packet checks and signed iOS build are underway. No full parity or release
readiness is claimed. Source hashes: `build/current-apple-live-input-qa/hot-corner-source-sha256.json`.

The updated full core Release suite passed 194 cases with five explicit environment
skips and zero failures in 47.919 seconds. The signed iOS Release build and strict
deep signature verification passed. Logs: `hot-corner-core-release.log`,
`hot-corner-ios-release.log` and `hot-corner-ios-signature.log` under
`build/current-apple-live-input-qa`. The VM bilingual UI gate is still live.


The first hot-corner VM pair failed the unavailable-row assertion in both languages:
a nested SwiftUI Menu container remained exposed as enabled. The failed bundle and
source snapshot are retained in `build/macos27-hot-corner-failed-verified/result.tgz`,
whose SHA-256 matches the guest archive. The product now shows an unavailable
hot-corner operation as a native disabled button row, preserving the independent
transport gate. The identical bilingual assertions passed (two cases, zero skips,
failures, runtime warnings or animation timeouts). The four-corner submenus and
Observe row screenshots were visually inspected for readable, complete labels.
Accepted pair: `build/macos27-hot-corner-fixed-verified/result.tgz`, also SHA-256
verified, with summaries and exported attachments alongside. This snapshot precedes
the following hardware-key release refinement.

Corner activation now releases all transport-held keys, including hardware-keyboard
modifiers not represented by toolbar sticky states. The strengthened actual TCP
regression holds both toolbar Command and hardware Option and verifies both releases
before corner motion. Full core Release passed 194 cases, five explicit environment
skips and zero failures in 47.253 seconds. Signed iOS Release and strict signature
verification passed (`hot-corner-hardware-release-*` logs).

All fourteen controlled VM interaction scenarios are now running on this final
source, including the two new corner cases. Their source snapshot is in the live
`hot-corner-full-controlled-result`; fourteen relevant source hashes match the VM.
This whole controlled gate has not yet been accepted. Verified duplicate guest
reports/archives were removed; the one reusable build cache and live result remain.
The configured remote-Mac, modifier-required corners, on-disconnect actions and
physical-device requirements in the audit remain open.


## Current disconnect-action gate and preserved evidence

The prior fourteen-case controlled VM gate completed successfully: exact expected
cases, zero skips/failures/runtime warnings and zero animation completion timeouts,
662.450 seconds. Its guest archive matched the local SHA-256; source snapshot and
attachments remain in `build/macos27-hot-corner-full-verified/result.tgz`. This
snapshot predates disconnect actions and is not acceptance of that later feature.

Disconnect settings persist per saved Mac connection and default to disconnect
only. The transport releases held keys/buttons and submits the configured action
in a final TCP write before closing, with a bounded completion fallback. A
processed write confirms transport handling, not that the remote OS locked or
logged out. An explicit close of a retained control session runs its action;
returning to the library does not close it. Ordinary hidden input remains blocked.
Observe, interrupted sessions and deleted or changed host/port/account settings
skip actions. Current saved preferences are read when closing, so editing a
retained connection affects its next close without reconnecting.

The initial bilingual disconnect UI pair passed two cases with zero skips,
failures, runtime warnings or animation completion timeouts (253.767 seconds).
The archive and source snapshot are SHA-256 verified in
`build/macos27-disconnect-bilingual-verified/result.tgz`. Those cases cover
relaunch persistence, received lock/logout shortcuts, bottom-right coordinates
on the selected display, Observe suppression and disconnect-only restoration.
That snapshot precedes the final retained-session edit assertion and Chinese
terminology refinement; it is not their acceptance.

The final production core Release suite passed 199 tests, five explicit environment
skips and zero failures in 66.473 seconds (`disconnect-retained-close-core-release.log`).
After the final additional changed-account assertion, the retained-preference
TCP test also passed separately in 1.727 seconds
(`disconnect-current-account-targeted.log`). Signed iOS Release, strict deep
signature verification, both localization catalogs and `git diff --check` passed.

The latest sixteen-case controlled VM job is still running in
`disconnect-final-full-controlled-result`; 22 changed/new source files match
the local source hashes recorded in
`build/current-apple-live-input-qa/disconnect-final-source-sha256.json`. A frozen
source snapshot is preserved in the active result. Its result has not yet been
accepted. No new macos27 UI run will be started while the coordinated ApexTerm
desktop gate holds the VM. Physical-phone and actual configured remote-OS action
acceptance remain open, as do the other feature gaps in the table.


## Dictation implementation and current acceptance boundary

The keyboard toolbar now includes a customizable Dictation action on Mac/iPhone/iPad.
A native sheet selects English or Simplified Chinese, explicitly starts microphone
capture, previews recognized text, stops recognition and sends only after confirmation.
The recognizer requires device-side recognition and checks support before capture;
it never falls back to network speech recognition. Request cancellation invalidates
late permission/recognition replies, stops the microphone and removes the audio tap.
Backgrounding, leaving the foreground session or entering Observe cancels the sheet.
A final result or bounded finish timeout makes the preview editable before sending.
Session-level submission independently rejects Observe, hidden, disconnected or
closing sessions and empty text.

The implementation adds localized microphone/speech purpose strings to iOS and Mac
bundles, and the microphone entitlement required by the hardened Mac package.
The packaging script was syntax-checked but not executed: no package notarization
or publication is implied. Existing toolbar configurations normalize the new action
without losing prior ordering or visibility.

Reference: [Screens Dictation](https://help.edovia.com/en/screens-5/features/dictation),
[Apple on-device recognition support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition),
[Apple device-side recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).
Mac compilation initially passed; current core regression and iOS build are running.
Actual microphone permission, speech recognition accuracy, stop/restart, denied
permissions and confirmed received remote text are still unaccepted. The running
sixteen-case VM result is a frozen pre-dictation snapshot, not evidence for this new UI.

Dictation-era core Release passed 200 cases with five environment skips and zero
failures in 68.767 seconds (`dictation-core-release.log`). The confirmed-text
transport test verifies exact paired keysyms for English/Chinese and no writes
in Observe, hidden, disconnected or closing sessions. The latest simulator
build-for-testing passed, including both new Dictation preview/cancel UI cases
(`dictation-ios-uitest-build.log`); compilation does not count as executing them.
They are queued for the next coordinated VM window, bringing the controlled
suite to eighteen cases. Actual audio recognition acceptance remains separate.

The pre-dictation sixteen-case run has already reported a failed Chinese recovery
case: `gestureFixtureData` exceeded its three-second HTTP response expectation
before connecting, at guest UI source line 723. The job continues and its gate
must fail regardless of later successes. A later direct guest HTTP observation
returned 200 in 0.001133 seconds; this does not explain the earlier timeout.
The next test source retains the timeout and adds endpoint/elapsed-time attachments
for slow responses; no timeout relaxation or passing rerun is claimed.

Final signed iOS Dictation Release passed and strict deep signature verification
passed (`dictation-final-ios-release.log`). Actual audio recognition and next
coordinated bilingual UI execution remain required.


Reference constraints rechecked against Screens 5 documentation: native
[Curtain Mode](https://help.edovia.com/en-GB/screens-5/features/curtain-mode)
requires Remote Management, not Screen Sharing, and keeps the remote session
controllable while concealing the physical display. No target sharing-service
configuration was changed. [File transfers](https://help.edovia.com/en/screens-5/features/file-transfers)
require Apple drag-and-drop semantics and a macOS 14+ target for mobile downloads;
an unrelated SSH transfer alone would not establish this behavior.
[Clipboard parity](https://help.edovia.com/en/screens-5/features/clipboard) includes
shared synchronization plus explicit send/get for text, rich text, images and URLs
when connected to a Mac; the existing text-only path remains incomplete.

The four new injected-permission race tests passed without prompting for microphone
or recording audio (`dictation-permission-races.log`). They prove denied-speech
short-circuiting, denied-microphone retry, stale speech replies after cancellation
and stale microphone replies while a new attempt exists. Full updated core
regression remains running; final signed iOS compilation has completed successfully.

Updated permission-era core Release completed 204 cases, five environment skips
and zero failures in 67.992 seconds (`dictation-permission-final-core-release.log`).
The latest signed iOS Release and strict signature verification passed
(`dictation-permission-final-ios-release.log`). The isolated Mac QA bundle
`build/current-apple-live-input-qa/AetherScreensDictationQA.vmqa.app` was packaged
with localized privacy strings/resources and ad-hoc hardened-runtime signing;
strict verification confirms its audio-input entitlement. It has not been
launched, granted microphone access, notarized or published.

A fresh CoreDevice lock-state query succeeded for both physical iPhones, but both
report `passcodeRequired: true` (despite having been unlocked since boot). No
physical test was started against these locked devices. The existing request to
USB-connect and keep them unlocked remains pending; connectivity alone is not
readiness. Sanitized observation: `physical-dictation-readiness.json`.

Next UI source also stops a case at its first assertion failure. A missing
fixture response/frame must not be followed by remote-input steps that could
produce misleading later receipts. The active sixteen-case source is unchanged.

Current Dictation UI test build (including permission-era production code,
bilingual preview cases, slow-fixture attachments and first-failure stopping)
passed (`dictation-permission-final-uitest-build.log`). No UI case was executed
on the host. Package metadata verification confirms microphone/speech purpose
keys on both platforms, Mac localization/core resources, and a QA executable
UUID matching the compiled Mac source artifact (`dictation-package-verification.json`).


The frozen pre-dictation sixteen-case controlled VM run is terminal: all sixteen
expected cases executed, fifteen passed, one failed, zero skips/runtime warnings
or animation completion timeouts; process exit 65. The failure is the Chinese
recovery fixture-response deadline. Both latest disconnect cases passed, including
editing the retained connection on the existing socket. Updated Chinese and
English logout settings screenshots were visually inspected: native grouped
forms, readable action labels, complete save-work notices. These remain received
shortcut/coordinate assertions, not actual remote OS logout/corner acceptance.

Result archive, source snapshot and exported attachments are preserved in
`build/macos27-disconnect-final-full-verified/result.tgz`; guest and host SHA-256
match `87c563329e46d4e8dacbe3ec188a943806406575a7b79b59ff111822d94baaa1`.
Summaries and attachments are extracted alongside for review. Own driver and
xcodebuild process exit was verified, and `/tmp/apexterm-vm-coordination-aetherscreens.txt`
now confirms desktop release. No replacement AetherScreens VM UI job was started.
After backup verification, the duplicate guest result/archive were removed and
the owned fixture server stopped; sources and one reusable build cache remain.
The full UI gate stays failed until the deadline issue is resolved and the
coordinated current eighteen-case source is actually executed successfully.


## Native mouse and Apple Pencil input implementation

UIKit indirect-pointer contacts now deliver immediate absolute coordinates and
left/right/middle button masks; Pencil contacts deliver direct left-button
press/drag/release independently of finger mode. Finger recognizers accept only
direct touches to avoid reinterpreting device input as delayed long presses.
Separate mouse/Pencil hover recognizers move the bounded remote cursor without
changing held buttons. A hardware-only pan recognizer accepts continuous/discrete
scroll events with no touch types, retaining sub-step horizontal/vertical motion.
Observe/Pan use local navigation; entering those modes or dismantling the view
releases owned inputs. Navigation positions are tracked per input source and
are not reset on every SwiftUI viewport update.

TrackpadEngine aggregates finger, mouse and Pencil button ownership, so releasing
one source preserves a matching button still held by another. Absolute mapping
works in both finger modes, clamps to real last-pixel bounds, rejects non-finite/
empty geometry and strips wheel bits from held device masks. Core coverage also
checks full-source release and scrolling with a held Pencil button. An actual
TCP receiver verifies right+left combined input, independent source release,
Observe suppression and resumed middle-button delivery. The twelve-case targeted
gate passed (`native-pointer-targeted.log`), including three new geometry/state
cases and one received-packet case. The first iOS compilation caught an incorrect
UIKit argument label; it was corrected to the SDK's `button(3)` and the fixed
build passed. Latest lifecycle refinements are in the running full core/iOS gates.

References: [Screens Apple Pencil behavior](https://help.edovia.com/en/screens-5/features/pencil-support),
[Apple indirect input behavior](https://developer.apple.com/documentation/bundleresources/information-property-list/uiapplicationsupportsindirectinputevents),
[Apple hardware scroll recognition](https://developer.apple.com/documentation/uikit/uipangesturerecognizer/allowedscrolltypesmask).
Physical mouse/trackpad/Pencil, hover, secondary/middle drag, wheel direction and
native UIKit delivery remain unaccepted; core packet tests do not replace them.
Pencil double-tap/squeeze customization was subsequently implemented (see below). No VM UI run was started
during ApexTerm's reservation.

The actual [Screens adaptive quality/compression behavior](https://help.edovia.com/en/screens-5/features/images-quality)
was rechecked: Mac adaptive quality requires progressive detail; compression
requests half-size server images, with per-connection always/remote-only/never
policies. Merely selecting a different lossless encoding or resizing the display
would not establish parity. Those Apple-server capabilities remain open.

Final native-pointer iOS Release and strict deep signature verification passed
(`native-pointer-final-ios-release.log`, `native-pointer-final-signature.log`).
Source hashes are recorded in `native-pointer-source-sha256.json`. This signed
build was not installed or used as proof of physical peripheral behavior.

The native-pointer full core Release gate completed 208 cases with five explicit
environment skips and zero failures (`native-pointer-full-core-release.log`).
No full VM UI or physical mouse/Pencil acceptance is implied by this core pass.


## Pencil double-tap and squeeze preferences

Per-computer keyboard toolbar settings now include iPad-only native pickers for
Pencil double-tap and, on iOS 17.5+, squeeze. Each gesture can do nothing, toggle
the toolbar, send a secondary click or send a middle click. Old JSON remains
readable; unknown future actions decode to no action. Reset Toolbar preserves
these gesture preferences. English and Simplified Chinese catalogs pass plutil.

UIKit dispatch honors system gesture preferences, processes squeeze only at its
ended phase and uses the modern tap callback without duplicate legacy dispatch.
The model rejects ending, hidden and disconnected sessions. Observe/Pan allow
local toolbar toggles but reject remote click actions. Clicking first releases
Pencil-held input, preserving other sources, and uses the selected display's
current cursor. Six targeted cases passed, including actual TCP button receipts,
per-computer persistence and old/future configuration decoding
(`pencil-actions-targeted.log`). The signed iOS Release build passed
(`pencil-actions-ios-release.log`) and strict deep signature verification passed.
Source fingerprints are in `pencil-actions-source-sha256.json`.

Physical compatible-Pencil double-tap/squeeze, precise gesture/hover positioning,
iPad settings presentation and floating/carousel toolbar remain acceptance or
implementation gaps. No VM UI run was restarted after disk cleanup; another
project's live VM UI run is preserved. These core/build checks do not establish
full Screens parity or release readiness.

The Pencil-actions full core Release gate completed 211 cases, five explicit
environment skips and zero failures (`pencil-actions-full-core-release.log`).
The skip count remains an unmet environment gate, and neither actual Pencil
input nor current eighteen-case VM UI acceptance is covered by this result.


## Pencil gesture hover-pose targeting

Modern UIKit tap/squeeze callbacks now carry the reported hover location,
converted from input-view coordinates into desktop-canvas coordinates, into
the session model. Remote click actions validate finite geometry and canvas
bounds, release Pencil-held input and map the gesture location into the currently
selected monitor before clicking. Missing hover poses retain legacy current-cursor
behavior. No-action and local toolbar actions do not move the remote cursor;
Observe/Pan/hidden/disconnected gates reject remote input before repositioning.
A pose outside the desktop cannot accidentally click the previous cursor, while
a local toolbar action remains available.

The targeted TCP test passed (`pencil-pose-targeted.log`): after an earlier click
at remote (12,8), squeeze at canvas (75,25) reaches selected-monitor (14,4);
negative, right-boundary and NaN positions emit no packets. Mode gates also
receive changed poses and still emit no remote input. iOS Release and strict
deep signature gates passed (`pencil-pose-ios-release.log`,
`pencil-pose-signature.log`); source hashes are in
`pencil-pose-source-sha256.json`. The full current core Release gate passed 211 cases with five environment skips
and zero failures (`pencil-pose-full-core-release.log`, 75.466 seconds).

API coordinate semantics were checked against the installed SDK and
[Apple UIPencilHoverPose documentation](https://developer.apple.com/documentation/uikit/uipencilhoverpose).
This implementation/transport evidence does not prove physical Pencil hardware
delivery, hover precision or floating-toolbar parity.


## iOS hardware keyboard event path

The remote canvas now becomes first responder when explicitly touched in a
connected control session. UIKit began/ended/cancelled presses feed a common
HID-key state tracker. Special keys, F1–F24, left/right modifiers, navigation,
backspace/forward delete and keypad Enter use HID mappings; printable keys use
UIKit layout characters, with unmodified characters for Cmd/Ctrl/Option shortcuts.
Unsupported or composition/dead-key events continue through the responder chain.
Repeated down events retain the initial keysym, and key-up does not depend on
changed modifier text. Multiple HID usages owning the same keysym release only
after the last owner; cancellation releases ordinary keys before modifiers.

Resigning first responder or dismantling the canvas releases physical keys.
Text drawer, log and customization presentation disable remote keyboard capture.
UIApplication will-resign-active also releases owned keyboard/pointer input,
while inactive application state rejects new raw keyboard events. Session model
forwarding rejects Observe, hidden, ending and disconnected sessions; existing
transport input-disable releases transport-held keys on session transitions.
Focus is acquired through a canvas touch, avoiding recurring SwiftUI updates
stealing native text-field focus.

Four targeted cases passed (`hardware-keyboard-receiver-targeted.log`). They
cover layout/HID mappings, repeated downs, changed release characters, duplicate
owners, unsupported events and actual TCP Cmd+C ordering. Receiver checks also
confirm modifier release on Observe, ordinary-key release on hiding, and no
subsequent forbidden key events. Source hashes are in
`hardware-keyboard-source-sha256.json`. Final signed iOS Release and strict signature gates passed
(`hardware-keyboard-final-ios-release.log`,
`hardware-keyboard-final-signature.log`); the full current core Release gate passed 215 cases with five environment skips
and zero failures (`hardware-keyboard-full-core-release.log`).

[Apple physical-keyboard event documentation](https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard)
was checked for began/ended and responder-chain semantics. Real accessory event
delivery, system-reserved shortcuts, UIKit repeat behavior, key mapping settings,
IME composition and supplementary Apple-server hardware text remain unaccepted.
The explicit text drawer remains the existing committed-text path; raw hardware
key support does not establish complete international-keyboard parity.


## Physical and toolbar key ownership

The transport now tracks app and physical-keyboard ownership independently for
each held keysym. Releasing physical Cmd while toolbar Cmd is locked does not
send a remote key-up; releasing toolbar Cmd while the physical Cmd remains
pressed also preserves the hold. Repeated downs retain existing repeat behavior.
Observe/input-disable, normal disconnect and final disconnect clear owners as
well as aggregate held keys. Existing application events use the default app
source; the iOS hardware bridge explicitly uses the physical-keyboard source.

Two actual TCP cases passed (`shared-modifiers-targeted.log`), verifying both
release orders, one aggregate release on Observe, owner reset on resumed control,
Cmd+C repeat/release ordering and hidden/Observe input suppression. iOS Release
and strict deep signature passed (`shared-modifiers-ios-release.log`,
`shared-modifiers-signature.log`). Source hashes are in
`shared-modifiers-source-sha256.json`; the full current core Release gate passed
216 cases with five environment skips and zero failures
(`shared-modifiers-full-core-release.log`).

Both physical iPhones were queried successfully again and still require
passcode unlock (`physical-keyboard-readiness.json`); no test was launched on
locked devices. The prior VM xcodebuild PID is terminal, but the other project's
thread is still repairing/retesting its Finder fixture; no AetherScreens VM UI
job was started without desktop release. Real accessory and combined-toolbar
behavior remain unaccepted.


## Hardware keyboard repeat settings and engine

Per-computer control settings now expose native bilingual hardware-keyboard
repeat enablement, initial delay and repeat interval. Missing legacy settings
use standard enabled repeat (0.5 second delay / 0.05 second interval). Stored
settings survive Reset Toolbar; delay/interval values are bounded and non-finite
values use defaults. The raw-key state uses monotonic timestamps and repeats
only the most recently pressed non-modifier, non-Caps-Lock key. It emits at most
one repeated down per tick, preventing bursts after a stalled UI thread.
Native repeated downs disable automatic repeats for that hold to avoid doubling.

The canvas runs its timer only while a repeat candidate exists and it remains
the active first responder. Key-up, cancellation, configuration changes,
resigning responder, view teardown, inactive app and input-disable stop repeats.
Actual TCP checks confirm three Backspace down events followed by one up, no
repeat after release, and Observe's final release with subsequent repeats
blocked. Deterministic clock tests cover initial delay, interval, late-tick
no-burst behavior, native-repeat deduplication, modifiers, disable/cancel and
configuration bounds. Twelve targeted cases passed
(`hardware-repeat-targeted-fixed.log`). The first targeted build caught a test
closure missing its ignored second argument; it was fixed before execution.
iOS Release, strict deep signature and both localization catalogs passed
(`hardware-repeat-ios-release.log`, `hardware-repeat-signature.log`). Source
hashes are in `hardware-repeat-source-sha256.json`; the full current core
Release gate passed 220 cases with five environment skips and zero failures
(`hardware-repeat-full-core-release.log`).

[Official Screens release notes](https://help.edovia.com/en/screens-5/faq/release-notes)
confirm configurable hardware repeat and toolbar/software-keyboard repetition.
This change covers hardware repeat only: toolbar/software-keyboard repeat and
real accessory/UI acceptance remain open.
[Advanced keyboard input modes](https://help.edovia.com/en-GB/screens-5/features/advanced-keyboard-settings)
require raw macOS virtual keycodes plus modifiers for Keystrokes and separate
Unicode/Legacy modes. Current keysym character mapping is not that Apple-server
keystroke protocol; those modes remain explicit implementation/acceptance gaps.


## iOS toolbar key hold/repeat

The iOS toolbar now uses native UIButton tracking for arrows, Tab, Return and
Delete, sharing the per-computer repeat delay/interval. A short tap retains the
existing down/up path. Holding starts remote down only after the configured
delay, then repeats down until release; releasing a repeating button emits one
up without adding another tap. Drag-exit and ScrollView cancellation before
the threshold emit nothing. VoiceOver activation retains a normal single tap.
Toolbar repeat uses its own transport key source so it cannot release a
physical key still held at the same keysym. Existing Mac toolbar behavior remains
on its native single-action buttons.

Hiding the toolbar, changing repeat configuration or button visibility, changing
Observe/foreground state, disconnecting/reconnecting and view disappearance
cancel hold tasks. Presenting customization, dictation or local text input also
cancels; iOS will-resign-active stops repetition immediately. The local text
drawer now mirrors its visibility into the model so hardware capture is disabled
while it is open.

Four targeted cases passed (`toolbar-repeat-targeted.log`): actual TCP checks
cover short tap, cancelled short hold, multiple repeated downs, one final up,
no extra tap on release, and Observe stopping a running repeat. Existing sticky
modifier transitions also pass. The first iOS build rejected a direct reference
to the localization function with its default second parameter; explicit map
closures fixed it. Latest iOS Release and strict deep signature passed
(`toolbar-repeat-final-ios-release.log`, `toolbar-repeat-final-signature.log`).
Source hashes are in `toolbar-repeat-source-sha256.json`; the full current core
Release gate passed 221 cases with five environment skips and zero failures
(`toolbar-repeat-full-core-release.log`). Actual native button tracking, horizontal scroll
cancellation, VoiceOver, bilingual screenshots and physical long-hold acceptance
remain pending. Software-keyboard repeat and Apple raw-keycode modes remain
implementation gaps.


## Individually configurable function and navigation keys

F1–F12, Page Up/Down and Home/End are now separate configurable toolbar actions.
Fresh/default and migrated configurations include all sixteen with visibility
off, preserving the existing compact default toolbar. Normalization preserves
old action IDs, ordering and hidden states, adds missing optional actions hidden,
and still removes duplicates. Individual visibility/order persists per computer;
Reset Toolbar restores these optional controls to hidden. The existing Fn group
remains available. Page Up/Down use the iOS repeat-capable native button; individual
function/Home/End buttons use normal taps. UIKit repeat-button width is measured
from localized text at its actual font, covering English and Chinese labels.

Eight targeted cases passed (`optional-toolbar-keys-targeted.log`). Migration/
persistence checks verify all sixteen appear hidden without unhiding an old Cmd,
and retain a visible/moved F12 after store reload. An actual TCP receiver checks
all sixteen against independent numeric RFB keysyms with paired down/up events.
iOS Release, strict deep signature and both catalogs passed
(`optional-toolbar-keys-ios-release.log`, `optional-toolbar-keys-signature.log`).
Source hashes are in `optional-toolbar-keys-source-sha256.json`; the full current
core Release gate passed 223 cases with five environment skips and zero failures
(`optional-toolbar-keys-full-core-release.log`). Native customization UI, physical remote
application behavior and Page Up/Down long-hold acceptance remain unaccepted.

The current controlled VM suite now selects twenty cases. Two new bilingual
cases long-press the native Tab control and inspect repeated received downs,
final up and cessation after release; they then enable a previously hidden F12
in customization, inspect both settings/toolbar screenshots, and verify exact
F12 down/up receipts. Runner syntax and all twenty method references passed
static validation. Current UI build-for-testing passed
(`optional-toolbar-keys-ui-build.log`); no test was executed by that compile-only
gate. UI source hashes are in `optional-toolbar-ui-source-sha256.json`. The prior
failed sixteen-case VM report predates these changes; current full VM acceptance
is still required after coordinated desktop release.


## Per-computer and live cursor speed

Saved computer controls now provide a native 0.25×–2× slider; the session menu
provides live speed choices across the same range. Missing old device fields
default to 1×. Non-finite settings use 1×, and finite values clamp to the range.
The multiplier applies after the existing relative-motion acceleration and
remote-pixel scaling, preserving the acceleration curve. Direct touch, absolute
mouse/Pencil coordinates and programmatic cursor movement do not scale.
Relative motion also rejects non-finite deltas/scales before emitting input.

Changing live speed updates the engine immediately. Saved sessions merge only
the speed field into the current matching device record, preserving newer
name, disconnect action and other edits. Changed host/port/account or a deleted
record prevents persistence; temporary sessions keep speed only in memory.
Default 1× is stored as an omitted optional field. Three targeted cases passed
(`cursor-speed-targeted-fixed.log`): numerical relative/absolute behavior and
invalid values; legacy decode and saved merge/deleted-target boundaries; actual
TCP motion at 1×/2× with unchanged absolute Pencil coordinates. The first test
build caught the wrong deletion API name; corrected to existing deleteDevice
before execution.

iOS Release, strict deep signature and localization lint passed
(`cursor-speed-ios-release.log`, `cursor-speed-signature.log`). Source hashes are
in `cursor-speed-source-sha256.json`; the current UI build-for-testing passed
(`cursor-speed-final-ui-build.log`); the full current core Release gate passed
226 cases with five environment skips and zero failures
(`cursor-speed-full-core-release.log`). Official [Screens release notes](https://help.edovia.com/en-GB/screens-5/faq/release-notes)
confirm live cursor-speed adjustment and a 2× maximum. Physical perceived
responsiveness, bilingual saved/live settings UI and Apple momentum/continuous
scroll behavior remain unaccepted; changing cursor gain is not evidence that
latency or scrolling parity has been achieved.

The controlled fixture wait now uses XCTWaiter to obtain its result before
recording an assertion. With continueAfterFailure disabled, the previous
XCTestCase.wait could abort before the slow-response attachment was saved.
Diagnostics now include path, monotonic elapsed time, response presence and wait
outcome, followed by the failure assertion; unfinished requests are cancelled.
The three-second deadline remains unchanged. Latest UI source compiles
(`cursor-speed-final-ui-build.log`) and its hash is in
`cursor-speed-ui-source-sha256.json`. Actual timeout diagnostics and the current
twenty-case VM gate remain unexecuted; the historical timeout is not resolved
by this instrumentation alone.


## Screen edge and corner gestures

Four direct-touch screen-edge recognizers attach to the active remote input
window, covering device edges and the bottom shortcuts toolbar. Recognition
is gated by the active connected Mac control session, Observe/Pan, local text/
settings/log sheets, presented native controllers and application activity.
Window teardown removes the owned recognizers; dynamic failure relationships
avoid retaining detached recognizers and prevent ordinary canvas pans/taps
from running alongside an edge swipe. System gestures are deferred only while
a Mac control session can trigger boundary actions.

A platform-neutral classifier requires a sufficiently long inward swipe from
an actual edge. Straight strokes target the corresponding edge; sufficiently
diagonal inward strokes near two edges target the corresponding hot corner.
Interior, outward, short, excessive sideways and non-finite gestures are rejected.
Adjacent edge recognizers sharing a corner are briefly deduplicated. Accepted
input releases owned pointer/keyboard state, clears transport-held input, moves
through the selected display's center and then to its boundary with no button
held. Corners reuse the existing guarded hot-corner action.

Three targeted cases passed (`screen-boundary-targeted.log`): eight directions
and rejected geometry; actual TCP last-pixel/center coordinates for all four
edges on the second of two displays, released drag state, corner dispatch and
Observe/Pan/hidden suppression. Final signed iOS Release and strict signature
passed (`screen-boundary-final-ios-release.log`,
`screen-boundary-final-signature.log`). Source hashes are in
`screen-boundary-source-sha256.json`; the full current core Release gate passed
229 cases with five environment skips and zero failures
(`screen-boundary-full-core-release.log`).

The controlled VM suite now selects twenty-two cases. Two new bilingual cases
exercise device edges with the shortcuts toolbar visible, inspect actual
received boundary coordinates and stopped input in Observe, and preserve a
bottom-toolbar screenshot/packet attachment. Runner syntax and twenty-two method
references are validated. These cases are not executed yet. Actual system-gesture
arbitration, ordinary input latency, corner recognition, configured Dock/menu
bar/hot-corner effects, orientation, keyboard overlays and physical iPhone/iPad
acceptance remain required.

Reference: [Screens edge/corner gestures](https://help.edovia.com/en-GB/screens-5/features/cursor-control-modes-and-other-gestures),
[Apple screen-edge recognizer](https://developer.apple.com/documentation/uikit/uiscreenedgepangesturerecognizer).

Final direction gating rejects outward/sideways motion before edge recognition,
allowing ordinary canvas pan recognition to proceed, while final dispatch still
checks actual swipe length. Latest iOS Release and signature gates passed
(`screen-boundary-direction-ios-release.log`,
`screen-boundary-direction-signature.log`). The first twenty-two-case UI
build-for-testing also passed; final direction-gated UI compilation passed
(`screen-boundary-direction-ui-build.log`). No UI cases were executed by these
compile-only gates.


## Typed Apple clipboard transport foundation — 2026-10-02

The Apple clipboard codec now preserves an ordered list of UTI flavors, binary
payloads and name/data aliases instead of discarding everything except plain
text. Text delivery keeps its existing UTF-8 preference and fallback behavior;
image-only archives never overwrite the text callback. The RFB client exposes
typed receive and guarded upload APIs. Observe, disconnected, closing and
non-Apple sessions reject typed uploads before a transport write.

Nine targeted Release tests passed (2.182 seconds): an independently constructed
mixed PNG/URL/RTF archive has byte-identical encoding and decoding, binary data
and aliases survive TCP fragmentation and upload, the next text/key message
remains aligned, Observe prevents upload, and malformed or oversized metadata
is rejected. Evidence: `build/current-apple-live-input-qa/typed-clipboard-targeted-fixed.log`.
The first test build had a test-expression bracket error; it was corrected before
this passing run. No production behavior was accepted from the failed build.

This is a transport foundation. UIKit/AppKit pasteboard conversion, manual and
automatic transfer settings, real remote rich-content copy/paste and physical
acceptance are still missing; the clipboard parity gate remains open.

Protocol research reference: [iShareScreen author's reverse-engineered Apple
VNC specification](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md).
It explicitly is not an Apple-endorsed specification. Its keyboard input-source
metadata and generic key events do not establish raw macOS virtual-keycode
support. The [Screens advanced keyboard requirements](https://help.edovia.com/en-GB/screens-5/features/advanced-keyboard-settings)
remain a separate implementation and real-server acceptance gate.

Current environment: `macos27` has an active ApexTerm build (observed xcodebuild
PID 39189), so no AetherScreens VM UI run was started. Both physical iPhones
again report `passcodeRequired = true`; earlier unlock confirmations do not
prove current test readiness. No release, tag, push or website publication.

The updated signed iOS Release build and strict deep signature verification pass:
`typed-clipboard-ios-release.log`, `typed-clipboard-ios-signature.log`.
The current simulator UI test package compiles (`typed-clipboard-ui-build.log`),
but none of the 22 VM UI cases were executed in this stage.

Full core Release regression passed: 232 tests, five explicit environment skips,
zero failures in 125.033 seconds (`typed-clipboard-full-core-release.log`).
Those skipped live environments and the pending physical/VM gates remain open.


## Native clipboard integration — 2026-10-02

`SystemClipboard` reads and writes the supported plain/rich text, PNG/JPEG/TIFF,
URL and HTML representations through UIKit/AppKit. AppKit verification uses an
isolated, uniquely named pasteboard, never the host user's general clipboard.
Known representations preserve their bytes; synthesized AppKit text formats are
allowed. Unsupported-only incoming content preserves the local clipboard; a
valid empty remote archive clears it. Multiple local items are currently rejected
rather than collapsed into a single flavor list; this remains a parity gap.

The default session consumes typed Apple delivery once, avoiding a second text
write that would erase image/rich representations. Injected text-only writers
retain the earlier callback path. The typed callback checks session and foreground
generations, active connection and teardown, so queued hidden-session content
cannot overwrite the newly selected clipboard. Explicit paste uploads all local
supported flavors before sending Cmd-V in one client input transaction. Observe
and hidden sessions suppress it; standard servers retain available text fallback.
The toolbar label is now Paste Clipboard / 粘贴剪贴板, while the persisted action
raw value remains `Paste Text` to preserve existing toolbar configurations.
Both localized UI tests have been updated to the displayed labels.

Twenty-one targeted tests passed in 8.565 seconds, followed by a three-test native
empty-archive/session regression in 1.265 seconds. The initial native test expected
an exact format set, but AppKit synthesizes extra UTF-16 text; the repaired check
verifies every original representation's exact bytes and permits the platform's
additional formats. The first iOS build exposed `UIPasteboard.pasteboardTypes`
renamed to `types` in Swift; the source was corrected and the final build is
recorded separately. A newly introduced Sendable closure warning was eliminated
by assigning the contextually typed closure directly.

This stage does not prove actual iPhone/iPad native clipboard delivery or remote
application paste acceptance. Shared Clipboard defaults/settings, bidirectional
local-change monitoring and standalone Send/Get actions remain required by
[Screens Clipboard Transfers](https://help.edovia.com/en/screens-5/features/clipboard).
The current 22-case VM regression remains unexecuted while ApexTerm owns the VM.

Final iOS Release build, strict deep signature verification and the current
simulator UI test-package compilation passed (`system-clipboard-final-ios-release.log`,
`system-clipboard-final-ios-signature.log`, `system-clipboard-ui-build.log`).
No VM UI cases or physical clipboard flows were executed in this stage.
The reserved VM test processes 39289/39293 were revalidated live; no VM build
cache was regenerated by AetherScreens after the requested cleanup.

Final full core Release regression passed: 235 tests, five explicit environment
skips, zero failures in 125.933 seconds (`system-clipboard-full-core-release.log`).
Native bridge and typed session tests are included in that final source run.
The full Screens parity goal remains open; no release review readiness is claimed.


## Shared clipboard and manual actions — 2026-10-02

Saved connections now have a backward-compatible optional shared-clipboard
preference, enabled by default. Live changes merge only that preference into the
matching saved target/account, preserving newer edits and refusing changed or
deleted targets. The edit form and both session/interactive-toolbar menus expose
native localized Shared Clipboard, Send Clipboard and Get Clipboard controls.
Send transfers content without issuing Cmd-V; the separate Paste Clipboard action
still queues its archive before the paste shortcut. Observe permits Get but blocks
Send and Paste. Shared-off connections discard unsolicited clipboard updates
while an explicit Get admits one reply; toggles invalidate queued old callbacks.

The local monitor checks change metadata every 500 ms and reads data only after
a local clipboard change. Remote writes update the observed baseline so they are
not echoed to the server. Control/foreground/connection/app-lifecycle gates stop
monitoring, uploading, receiving or reading when inappropriate. App activation
preserves the last synchronized count: content copied in another app is queued
before the remote fetch. Foreground state is published so native controls refresh.
The existing paste paths also check application activity before reading bytes or
sending keys. All local clipboard effects in the new session test are injected;
the native pasteboard test uses a unique private pasteboard.

Twelve targeted core tests passed in 8.797 seconds. The resumed external-copy
TCP regression passed in 2.486 seconds before the final background/read guards;
final-source full regression and builds are recorded below. Existing oversized
text paste rejection remains enforced for typed paste before modifiers/keys are
sent, preserving the earlier clipboard UI acceptance contract.

The QA fixture previously accepted only one UTF-8 flavor and would disconnect
when native clipboard conversion adds UTF-16 or other representations. It now
parses bounded typed archives and aliases, preserves all uploaded flavors in
its reply, and rejects truncated/trailing archives. A real loopback fixture TCP
upload/fetch smoke passed with PNG, UTF-8 and UTF-16 flavors plus metadata; evidence
`shared-clipboard-fixture-tcp-smoke.json` records byte sizes and archive SHA256.
It contains controlled fixture data, not real user clipboard content.

Two new bilingual Shared Clipboard UI cases cover disabled sharing, retained
local content, manual Send/Get without paste keys and Observe controls. The
clipboard suite now has four cases, separate from the 22 controlled gesture
cases. Method declarations, runner lists and Python syntax were verified.
They have not been executed in the VM and must not be counted as passing UI cases.

Native iOS clipboard permission behavior, background wake/foreground notifications,
actual rich-content Mac/iPhone transfer, multi-item local clipboard preservation,
large-content responsiveness and both physical phones' acceptance remain open.
At that stage, the Apple subscription remained registered while sharing was off;
incoming content was gated locally. The later transport-policy stage below
implements subscription shutdown; real Apple-server behavior remains unaccepted. Both phones still report passcode required.
The reserved ApexTerm VM processes 39289/39293 were revalidated live (24 minutes
elapsed, VM free approximately 20 GiB); no AetherScreens VM cache was regenerated.

Final background-guard iOS Release build and strict deep signature verification
passed (`shared-clipboard-background-final-ios-release.log`,
`shared-clipboard-background-final-ios-signature.log`). The final UI test package
also compiled (`shared-clipboard-background-ui-build.log`), with 22 controlled
cases and four clipboard cases pending VM execution. Earlier full runs passed
237 tests before the last read/activity guards; the final source is recorded by
the later full-run log, not inferred from those older binaries.

Final background/read-guard source: full core Release passed 237 tests, five
explicit environment skips, zero failures in 128.037 seconds
(`shared-clipboard-background-full-core-release.log`). The source manifest was
revalidated after the passing run. Signed iOS and final UI package gates above
match this source. This remains an internal candidate, with VM/phone and full
Screens parity acceptance still pending and no public release.


## Core test clipboard isolation and current VM payload — 2026-10-02

The shared-clipboard monitor added a native clipboard dependency to session
construction. All 49 core-test session constructors now use `TestSession.make`,
which instantiates the real model/transport with inert clipboard read/count/write
closures unless a test explicitly supplies its own controlled clipboard. Native
production defaults remain unchanged. The synchronization test still uses the
real timed monitor, socket transport and injected change counts/writes. This
prevents a new host-user copy from being sent to a fixture or included in an
assertion failure during unrelated pointer/input tests. The native pasteboard
case continues using its unique isolated pasteboard.

Full Release regression passed: 237 tests, five environment skips, zero failures
in 128.484 seconds (`isolated-clipboard-full-core-release.log`). No production or
UI code changed in this isolation stage; prior signed-device/UI-package build
results still apply to the same production sources. Static verification leaves
only the factory's one direct model constructor and confirms all 49 test call
sites use the isolated factory. The generated local fixture Python bytecode was
removed after its smoke check.

A bounded current-source snapshot is prepared at
`/Users/chenxu/aetherscreens-ui-current.nIqaau` in macos27. The host archive and
guest copy matched SHA256 `e6aa3fdfb8193676d9ea97d89538fd190e5f7211b52ec71bf5c7bd7079cfa29b`;
all 140 guest source files matched the host manifest. The redundant guest archive
was removed after verification. This adds only 6744 KiB of source; no simulator
was booted and no DerivedData was created. The own Xcode/Python tools and the
shutdown dedicated QA simulator E91A866B-D567-42FE-AB54-5E2AD5F03828 were verified.
The 22 controlled and four clipboard cases are prepared, not executed.

ApexTerm xcodebuild 39289 and its new runner 40136 were confirmed live at the last
check, so AetherScreens has not started a conflicting VM run. The latest thread
status reports its own failed gates and continuing diagnostics; a stopped prior
runner alone was not treated as desktop release. VM free space is approximately
20 GiB. No current UI/phone/full-parity or public release completion is claimed.


## Clipboard transport monitoring policy — 2026-10-02

Shared Clipboard now controls the transport subscription, including hidden and
inactive sessions. Apple startup with sharing disabled neither subscribes nor
fetches; selector 2 stops an existing subscription, repeated disable is
idempotent, and a manual Get while disabled does not restart monitoring. Desired
policy survives reconnect. Late Apple status and extended-clipboard notifications
do not initiate automatic fetches while disabled. Observe can still receive
remote content while local upload remains blocked. The selector is documented
in [iShareScreen's reverse-engineered protocol reference](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md), not an Apple-endorsed specification.

A loopback TCP regression verifies startup-off, explicit enable/disable, late
status, manual fetch and reconnect. The controlled Python fixture separately
verifies stop suppresses notification, off-state changes update the source,
manual fetch gets the latest content, and mixed-flavor/alias archive roundtrip.
The bilingual UI cases now wait for source changes independently of subscription
notifications. Hidden-session assertions count fetches rather than unrelated
stop packets. Explicit Pencil picker binding types also remove optional-value
ambiguity in the No Action selection.

Full core Release: 238 tests, five explicit environment skips, zero failures in
135.581 seconds (`clipboard-monitor-full-core-release.log`). Signed iOS Release,
strict deep signature verification and simulator UI package compilation passed
(`clipboard-monitor-ios-release.log`, `clipboard-monitor-ios-signature.log`,
`clipboard-monitor-ui-build.log`). Runner declarations match 22 controlled, four
clipboard and eight library cases; compilation does not count as UI execution.

Real Apple subscription-stop behavior, native rich clipboard transfer, physical
phone permissions and responsiveness, and the current bilingual UI execution
remain pending. The VM is still running another project's test: xcodebuild
41516 and runner 41520 were confirmed live. No conflicting AetherScreens VM
execution or new DerivedData directory was started. This is not full Screens
parity acceptance and no public release is authorized by these results.


## Real Apple clipboard subscription acceptance — 2026-10-02

The explicit target 192.168.50.226 passed saved-account authentication, real
frame reception, subscription start/stop compatibility, manual archive fetch
while disabled, and continued full framebuffer updates. Credentials were read
from the application's saved Keychain with authentication UI forbidden. No
password was passed through command arguments, environment variables or logs.

The opt-in remote-copy extension of the same live test uses an SSH-controlled
AppKit helper. It snapshots every original pasteboard item/type in memory,
refuses an incomplete or over-16-MiB snapshot, and refuses to overwrite a newer
user copy. The helper emits status tokens only. After enabled-state synthetic
copy, both the expected clipboard archive and a positive server change status
were observed. After stop, a full-frame request and a received-frame synchronization step, a confirmed fresh
remote copy produced no change status or automatic archive in the three-second
observation window. Manual Get then returned that exact synthetic off-state
copy. The helper restored the original item/type bytes and verified them before
reporting restoration. Its dedicated remote source directory was removed.

The final live case passed in 7.765 seconds with zero failures
(`clipboard-monitor-real-mac-status-final.log`); the machine-readable result
records source/log hashes (`clipboard-monitor-real-mac-verification.json`).
This accepts the bounded real Apple subscription behavior, not physical iPhone
paste permissions, rich-content interoperability, sustained responsiveness or
full Screens parity. Both phones still require unlocking; VM xcodebuild 42165
and runner 42170 were confirmed live, so no conflicting AetherScreens GUI test
was launched. The dedicated QA helper does not read or write the host clipboard.


The final unchanged-production regression passed 239 core Release tests, six
default environment skips and zero failures in 136.359 seconds
(`clipboard-monitor-live-final-full-core.log`). The newly added live test is
intentionally skipped in the default run and passed separately with its explicit
target and remote-copy fixture opt-ins; the other environment skips remain open.
All 83 production/iOS/asset files in the prior signed-device/UI-package manifest
remain byte-identical. No repeat production build was inferred necessary from
the test/helper-only changes. Current phone/UI/full-parity acceptance remains
incomplete and no release, tag, push or website publication occurred.


## Real Mac rich-content clipboard gate — 2026-10-02

[The current Screens clipboard reference](https://help.edovia.com/en/screens-5/features/clipboard)
requires rich text, plain text, images and URLs for Mac connections, including
manual Send/Get when Shared Clipboard is disabled. The controlled live gate now
checks PNG, URL, RTF, HTML and UTF-8 flavors on the real 192.168.50.226 Mac. It
fetches an image-first native pasteboard, checks every original flavor byte and
native PNG decoding, uploads a different synthetic sample, verifies each flavor
on the remote native pasteboard, then fetches the upload back intact. All fetches
remain manual with automatic monitoring stopped; no Cmd-V shortcut or other
keyboard/pointer input is emitted.

Initial attempts failed because the AppKit helper blocked its main thread on
stdin. Its cached pasteboard values looked valid inside the producer but the
remote Agent could not obtain rich representations. Eager writes and text-first
ordering alone did not fix the failures. Moving stdin reads to a thread-safe
mailbox and servicing the main run loop resolved the same assertions without
a production transport change. Image-first ordering was restored and passed.
The earlier failed logs remain evidence of the fixture fault, not accepted runs.

The helper restores the original clipboard only while it still owns the latest
change count. A separate process checks every original item/type byte before
restoration is acknowledged; original clipboard data stays on the target Mac in
memory and anonymous pipes, never in files, SSH output, arguments or environment
variables. The independent reader also materializes promised representations
before the helper exits. Only known synthetic type/length and equality metadata
are logged; unknown incoming types are redacted.

Final rich live case: one test, zero failures, no skips, 13.991 seconds
(`rich-clipboard-real-mac-restoration-final.log`). The reusable gate
`scripts/qa/run_live_clipboard_qa.py` verifies the remote helper source hash, uses
exclusive log creation, marks skipped live cases as failed gates, writes outcome
/source/log hashes, and removes its dedicated remote helper after a failed or
passed test. Credentials still come from the application's noninteractive saved
Keychain. Syntax, standalone helper typechecking and whitespace checks passed.

This accepts the real Mac typed transport path. Physical iPhone paste permissions,
actual image/URL/rich-text rendering in destination apps, large clipboard latency,
multiple local items, and the full UI/Screens parity goal remain incomplete. Both
phones report passcode required. VM xcodebuild 43389 and runner 43394 are live;
AetherScreens has not started a conflicting GUI run or regenerated VM caches.


Final source regression: 239 core Release tests, six default environment skips,
zero failures in 135.802 seconds (`rich-clipboard-final-full-core-release.log`).
The rich live opt-in passed separately and is not inferred from the skipped
default live case. The 83 production/iOS/asset files still match the prior signed
iOS/UI-package build manifest, so those build results remain applicable.
The live gate's log and result files both use exclusive creation.
Both phones were rechecked after regression and still require unlocking; the
ApexTerm VM processes 43389/43394 remain live. No public release was performed.


## Apple server-driven framebuffer updates — 2026-10-02

App sessions now opt into the Apple 0x09 automatic framebuffer update request
for exact RFB 003.889 peers. After the initial full request, the client receives
continuous frames without sending an incremental 0x03 request after every frame.
Standard VNC peers retain the request-driven path. Accepted DesktopSize and
ExtendedDesktopSize changes reconfigure the update region and request a full
frame. Reconnect clears the active mode and configures the fresh dimensions;
failed or closing sessions cannot report automatic updates as active.

The packet layout follows the experimental reverse-engineered
[Apple VNC protocol reference](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md),
section 8.11; this is not an Apple-endorsed specification. The implementation
does not advertise or decode Apple DisplayLayout 0x0451, HEVC, adaptive quality
or native momentum scrolling. Those remain separate parity requirements.

The TCP regression checks unsolicited consecutive frames, absence of per-frame
polling, standard-server and opt-out fallback, resize region bytes, failed-state
reporting and reconnect initialization. The controlled Python fixture also
produces pointer-triggered frames without a pending update request.

Final core Release regression: 240 tests, six environment skips, zero failures,
146.623 seconds (`apple-push-final-full-core-release.log`). The updated signed
iOS Release build and strict deep signature verification passed
(`apple-push-final-ios-release.log`, `apple-push-final-ios-signature.log`).
The real target Mac opt-in gate passed separately: one test, no skips or failures,
10.010 seconds (`apple-push-real-mac-final.log` and its verification JSON),
including PNG/URL/RTF/HTML/text clipboard download, typed upload, roundtrip and
independent restoration. This proves transport compatibility, not measured
input-to-display latency or physical Screens-equivalent smoothness.

Current physical iPhone gesture, clipboard UI, background recovery and subjective
smoothness acceptance remain outstanding. Shared macos27 GUI execution remains
gated on release of the currently running ApexTerm test process. No public
release, push, tag or website update has occurred.

The final iOS simulator UI package build also passed (`apple-push-final-ui-build.log`).
This is compilation evidence; the controlled GUI cases have not run on macos27.
Both physical phones were queried again and still require their passcodes.


## Bounded native scroll conversion — 2026-10-02

The iOS finger and hardware-scroll paths now share the Mac wheel accumulator.
Both axes preserve sub-tick motion and direction reversals. Non-finite samples
are ignored without disturbing prior fractional motion; conversion is clamped
before integer conversion, so exceptionally large finite values cannot crash or
produce an unbounded main-thread loop. Each sample emits at most 64 ticks per
axis and discards overflow rather than deferring a wheel flood into later input.
Normal finger/hardware motion retains the existing eight-point step; Mac precise
and discrete motion retain ten-point and one-step conversion respectively.
Entering local navigation or releasing input clears both iOS accumulators.
The engine also rejects non-finite direct scroll input without releasing a held
mouse button. This is discrete RFB scrolling and does not establish Apple-native
continuous/momentum scrolling parity.

Targeted regression passed 19 trackpad/native-input cases, zero failures
(`scroll-bounds-targeted.log`), including invalid samples, fractional motion,
diagonal directions, extreme finite deltas, no deferred overflow and held-button
preservation. Updated signed iOS Release build and strict signature verification
passed (`scroll-bounds-ios-release.log`, `scroll-bounds-ios-signature.log`).
The updated iOS simulator UI-package build also passed (`scroll-bounds-ui-build.log`).
Full source regression passed 243 cases with six environment skips and zero
failures in 146.308 seconds (`scroll-bounds-full-core-release.log`).
Compilation is not GUI acceptance.
Physical scrolling smoothness remains unaccepted. Shared macos27 xcodebuild
43389 and replacement runner 43990 are live; no conflicting GUI run was started.


## Physical keyboard remapping and alternate app switching — 2026-10-02

[The Screens keyboard reference](https://help.edovia.com/en/screens-5/features/permute-cmd-ctrl-alt-tab)
describes Command/Control permutation and a Command-backslash substitute for
remote Command-Tab. [The release notes](https://help.edovia.com/en-GB/screens-5/faq/release-notes)
clarify that permutation applies only to physical keyboards, not toolbar buttons.
Both options are now persisted per computer in the existing hardware keyboard
configuration and exposed with English/Chinese native toggles on Mac and iOS.
Old saved repeat configurations decode with both options disabled.

Mac native and UIKit physical keyboard paths use a shared session mapper. Left
and right Command/Control retain their side when swapped. Backslash maps to Tab
only while an effective remote Command is held and the alternate-switch option
is enabled. Each physical key retains its original mapped key for repeats and
release even if preferences change mid-hold. Multiple physical keys mapping to
one remote key remain held until the final owner releases. Observe/background
and input release clear mappings and balance ordinary keys before modifiers.
Toolbar modifiers and predefined shortcuts retain their existing meaning.

Targeted core/TCP regression passed 17 cases with zero failures in 12.104 seconds
(`keyboard-mapping-targeted.log`): saved configuration compatibility, mapping
retention, duplicate ownership, alternate switching, toolbar isolation and
Observe/background release. The final full regression additionally checks all
four left/right modifier mappings. Bilingual narrow customization UI cases now
check toggles remain enabled after closing/reopening and explicitly scroll
controls into view; those assertions still require macos27 GUI execution.

Actual physical keyboard delivery and remote native app switching remain
unaccepted. Apple raw virtual-keycode Keystrokes, Unicode/Legacy modes and
other keyboard parity requirements remain open. This stage does not claim
complete keyboard or Screens parity.

Final regression: 246 core Release tests, six environment skips, zero failures,
147.221 seconds (`keyboard-mapping-full-core-release.log`). Updated signed iOS
Release, strict signature verification and simulator UI-package compilation
passed (`keyboard-mapping-ios-release.log`, `keyboard-mapping-ios-signature.log`,
`keyboard-mapping-ui-build.log`). Compilation does not prove native physical
keyboard or bilingual GUI acceptance.

The same verified source completed a headless Debug UI-package build in macos27
(`keyboard-mapping-vm-build.log`), with all 142 source hashes independently
verified. The single workspace DerivedData directory is 509.1 MiB and VM free
space is 16.8 GiB. The dedicated simulator remains Shutdown; GUI cases have
not executed. ApexTerm's prior xcodebuild/runner finished,
but its thread remains active and prepares a retry; desktop ownership is not
inferred from the old process exit. No public release has occurred.


## User password command — 2026-10-02

[The Screens password-command reference](https://help.edovia.com/en-GB/screens-5/features/type-mac-password)
requires local identity authentication, default Return submission and held-button
typing without Return. The command is now available in the customizable native
toolbar and session/action menus with English/Chinese labels. Native UIKit and
AppKit tracking distinguish click/release from a hold of at least 0.5 seconds,
and retain scroll/off-button cancellation and accessibility activation. Menu
entries separately expose both submission choices.

Before credential access, LocalAuthentication evaluates device-owner identity
using the platform's biometric/passcode/password facilities. Cancellation
invalidates its context. Actual app background, Observe, hidden-session and
input release cancel pending commands. Temporary biometric resign-active events
do not cancel the identity dialog; after authentication the command waits for
activity and rechecks the current target before reading or sending anything.
Saved records must retain the same address, port, account and Mac/account auth
identity. Temporary Mac account connections use their current session identity.
The current connection credential takes precedence over saved credentials;
temporary sessions do not persist it. Password bytes never enter clipboard paths
or logs. Empty, control-character and over-4096-byte inputs are rejected. Held
keyboard modifiers are released before one serialized typing/optional-Return
transaction. Missing credentials produce fixed localized errors.

The first test attempt failed because the None-auth wire fixture was given an
ARD account during connection. Production correctly refused that downgrade.
The fixture now explicitly establishes its None-auth TCP socket before supplying
a synthetic post-auth account identity. This tests command transport rather than
ARD authentication; it does not constitute real Mac login-window acceptance.
Final targeted regression: 11 cases, zero failures, 12.076 seconds
(`user-password-final-targeted.log`). Four command TCP cases cover authentication
refusal before credential access, late authentication after hidden/changed
accounts, Unicode/key release, clipboard exclusion, with/without Return, temporary
credential priority, and unsupported password inputs. All credentials in these
cases are synthetic. TestSession defaults to no authentication/no credential
reader so ordinary core tests do not access the host Keychain or identity UI.

Updated signed iOS Release and strict signature verification passed
(`user-password-final-ios-release.log`, `user-password-final-ios-signature.log`).
Final regression passed 250 core Release cases, six environment skips and zero
failures in 159.130 seconds (`user-password-full-core-release.log`). The updated
simulator UI-package compilation passed (`user-password-final-ui-build.log`).
The signed app contains the Face ID usage description and both localized
English/Chinese InfoPlist descriptions; metadata verification passed.
Actual Face ID/Touch ID/passcode UX, held-button behavior and remote password-field
submission remain unaccepted; the command has not automatically typed the real
Mac account password. Privacy-option customization and hardware shortcut routing
remain open. No full keyboard/Screens parity or public release is claimed.

The updated macos27 headless test-package build also passed
(`user-password-vm-build.log`). All 144 source hashes were independently
verified, the dedicated simulator remains Shutdown, and the single DerivedData
directory is 517.9 MiB. Actual UI execution remains pending shared-desktop
ownership and physical-device readiness.

## Current macos27 full controlled UI gate (2026-10-02)

The current 22-case controlled gate executed every requested English/Chinese
case with 9 passes, 13 failures, no skips, no runtime warnings and no animation
completion timeouts. This gate is rejected. The original result bundle, summary,
case inventory and failure attachments are retained under
`build/macos27-current-ui-acceptance/original/`; its exported archive SHA-256 is
`2a53a425d50b4ffb81c8b6267e5b0a0079ff9e2677eb2c9aec32d33108c46a5e`.
The owned fixture stopped and shared desktop lock released on failure. The
clipboard and library suites did not execute after this failed controlled gate.
Verified host copies allowed removal of the guest's duplicate report/archive.

Local repairs now permit edge input in the foreground full-screen session while
blocking sheets above it, replace oscillating toolbar swipes with short measured
drags, keep Reconnect near the start of the menu, and group View/Displays controls
into native bilingual submenus. The grouped-menu UI package builds successfully;
five localization tests pass. These results do not prove the repairs in the VM.
Both received-gesture cases failed at the double-click assertion after accepting
single clicks. Failure packet attachments have been added for the next diagnostic
run; double-click behavior remains unresolved. Full controlled, clipboard, library,
physical-phone and Screens parity acceptance remain open.

The follow-up bilingual native-gesture diagnostic reproduced double clicks
sending only one press/release pair. A simultaneous one-finger two-tap recognizer
now complements the immediate single-tap recognizer. Both complete native-gesture
cases subsequently passed with zero skips, failures, runtime warnings or animation
timeouts. Exported packet attachments independently show exactly `[1,0,1,0]`
button masks at the same coordinate for each language, and the same cases also
verify secondary/middle click, held drag, touch/zoom mapping and Observe suppression.
Evidence: `build/macos27-current-ui-acceptance/gesture-double-click-fix/`;
archive SHA-256 `6927fa679a7d8457662d21cd09f6f22efd9f8a56df5e416aea7fefc254ce189f`.
This accepts only the two controlled native-gesture cases. The diagnostic wrapper's
inherited line saying all three suites passed is inaccurate; its authoritative
case inventory and summary contain exactly two tests. Complete UI, physical-device
and Screens parity acceptance remain open.

The corrected full 22-case controlled run completed with **16 passes / 6 failures**,
zero skips, runtime warnings, animation timeouts or inventory omissions. Both
languages now pass reconnect, disconnect actions, monitor selection, fullscreen,
hot corners, retained-session selection, viewport navigation and received native
gestures. It remains rejected: both dictation cases queried a removed toolbar
action after Observe hid the keyboard, both edge cases still received no expected
edge coordinate, and both F12 cases did not enable visibility. The actual F12
settings screenshot shows its switch still off after the generic tap.
Evidence: `build/macos27-current-ui-acceptance/corrected-full/`; export SHA-256
`f539594a9ca6bc2d9ff95adb14aada14b35cf10e7a12f97e926972971d34ff41`.
The copied archive was hash-verified before guest report duplicates were removed.
The same production repair passed 250 Core Release tests with 6 explicit external
environment skips and no failures (`corrected-full-core-release.log`), before
adding QA-only DEBUG boundary diagnostics. Follow-up work checks Observe's hidden
toolbar, targets the actual F12 switch and asserts its new value, and records
native edge recognition stage/coordinates only under an explicit QA launch flag.
No full-suite or physical-device release acceptance is claimed.

The six-case follow-up completed with four passes and two failures: both languages
now pass Dictation preview/Observe and held-key/F12 visibility plus received key
packets. Only the two boundary cases failed. The complete four-case clipboard
suite executed but failed before download: its runner used ordinary RFB port
5999 instead of Apple fixture port 6001. This is rejected test setup, not accepted
clipboard behavior. The runner now chooses its suite's default fixture port,
while preserving explicit port overrides. QA-only boundary JSON was overwritten
by `updateCursor`; it is now retained across cursor refreshes. These changes are
prepared and await a fresh VM execution. No edge repair is claimed from the empty
attachments. Complete library testing is still running on the prior snapshot.
Evidence: `build/macos27-current-ui-acceptance/follow-up/`;
completed controlled/clipboard archive SHA-256
`0a76874c6025eeb93c1bc4dd53ac9e4cab8700c2134cb3701f0fdad8a83c5c12`.
All 34 final UI cases, real phones and remaining Screens parity gates remain open.

The complete follow-up library suite completed with six passes and two failures,
zero skips/runtime warnings: both narrow keyboard cases missed the physical
Command/Control switch. Export SHA-256
`c00816fd7ffca38bc81aab6df18508ef9cb848caf80d6b018d8e11b433cad608`.
All host report archives were independently hash-verified before guest duplicates
were removed. The next eight-case diagnostic completed: boundary 0/2, clipboard
1/4, narrow keyboard 1/2. Chinese narrow settings now pass configuration and
persistence; English missed the Cmd visibility switch's outer tap point.
Its tap now targets the same thumb fraction as the verified F12 switch.

Both retained boundary JSON attachments prove `should-begin`, active/enabled,
frontmost=true, and **translation=(0,0)**. The zero-translation guard rejected the
native start callback. The prepared repair uses velocity for initial direction
when translation resets and retains final traveled-distance classification.
Boundary export SHA-256
`d3d7d401691768de895be34307b97c91ad94ed8c47c3521b9c925d8249a55998`.
The correctly configured Apple clipboard suite has one complete English pass;
three cases still fail at paste/upload. Their recorded UI has no permission or
error alert. No clipboard repair is inferred yet. Packet failure attachments and
explicit QA-only DEBUG callback eligibility/flavor-count logs are prepared for
fresh diagnosis, without logging clipboard content. Clipboard export SHA-256
`f3c1e05909f0e9d7261fc6270d39e036662f4a1a01e211cf8e8ee01eea190d8d`.
These diagnostics are not final full34, physical-device or Screens acceptance.

The retained clipboard DEBUG metadata proves an initial response was discarded:
callback/foreground/selection/eligibility were true, clipboard generation false.
A regression reproduces older queued handshake UI work invalidating a newer
clipboard callback and reverting connected UI to connecting. It failed before
repair and passes after invalidating at wire-notification time and ignoring
obsolete queued UI state. The entire Core suite then passed **251 tests / 6
explicit external-environment skips / zero failures**, before async-read changes.
Evidence: `clipboard-startup-regression-before.log`,
`clipboard-startup-regression-after.log`, `clipboard-startup-core-release.log`.

The VM's first Chinese paste then stalled. A process sample proves its main
thread waiting in `SystemClipboard.read` -> `UIPasteboard.dataForPasteboardType`
-> semaphore. The owned AUT was terminated once; another case reproduced it,
so the owned clipboard xcodebuild was interrupted with recorded SIGINT. The gate
is rejected: exit75, two animation timeouts, only 2 of 4 cases recorded, both
failed. It must be rerun in full; interruption is not acceptance or an automatic
retry. Hash-verified clipboard archive SHA-256
`37995a9b5ce2a5368c2d6f5328702d65c305b2896255abd3028c08c085d911e3`
contains the sample, termination and interruption reasons. Narrow settings
remained 1/2: the English Cmd switch was at the bottom safe area. A new measured
scroll requires its thumb inside the safe viewport before clicking and preserves
visibility/persistence assertions. Library archive SHA-256
`6ba458b46c41ffae31242307a56c1637a3110091a05e6295562bc76c85de33e3`.

UIKit now loads single-item supported clipboard flavors asynchronously from item
providers, with a total deadline, cancellation, size limits and revalidation of
session, selection, Observe and clipboard change count before sending. Manual
read errors are bilingual. Async automatic upload acknowledges change count only
after a successful read/upload, preserving a copy interrupted by backgrounding;
resume upload precedes remote fetch. Two promised-provider tests and a real-TCP
async session test verify responsiveness, timeout/cancellation, exact payload and
rejection after Observe/selection/content changes. The current targeted Core /
localization gate passes **22 tests, zero skips/failures**. iOS compile-only Debug
UI package succeeds; further changes to viewport targeting still require fresh
VM execution. Edge actions now retain the native canvas after releasing held
input, avoiding replacement of window recognizers between consecutive swipes.
No final UI, phone or Screens parity acceptance is claimed. Full34 is next.


## Current asynchronous clipboard acceptance snapshot — 2026-10-02

The complete current Core Release suite records **254 tests, six explicit
external-environment skips and zero failures**. Its log SHA-256 is
`6673cd1b0941db50282b31cf511451b4276fbd1199f99aed06ca8128be074cf6`.
The latest real 192.168.50.226 rich-clipboard protocol/native roundtrip also
passes (one case, no skip/failure; PNG, URL, RTF, HTML and UTF-8), with the
original clipboard restored and the temporary remote helper removed. Its log
SHA-256 is `8f9cebd064e3b3d281df726e897c755d900c01cbd1112035b361c199fb6ba3b7`.
These gates do not validate iOS promised-provider UI or phone gesture delivery.

The full bilingual VM gate is executing the independently verified 144-file
snapshot, with controlled22, clipboard4 and library8 suites collected even if
an earlier suite fails. Its initial Chinese boundary case still fails. The
fullscreen case additionally encounters a QA accessibility-value override;
the prepared test change enables boundary diagnostics only for boundary cases,
preserving normal fullscreen value assertions. Neither prepared change nor a
partial live run is accepted. The VM snapshot remains frozen during execution.

The signed arm64 device Release candidate now reports version **1.0.0**, build
**1**, and passes strict signature verification. Both Info.plist and the XcodeGen
source use MARKETING_VERSION/CURRENT_PROJECT_VERSION, avoiding regeneration
resetting the visible version to 1.0. The executable SHA-256 is
`9e589f3f4f79f604551a7e865e411b31c70f7354424d5257737a9351e59c73b2`.
This candidate has not yet passed installation/live acceptance on both phones.
The latest CoreDevice reads find both phones reachable but locked. Full Screens
feature alignment, physical acceptance, perceived responsiveness and user review
remain required before publishing the first formal release or updating the site.


The closed asynchronous full-run controlled suite records **18/22 passed,
four failures, no missing cases, no skips and no animation completion timeout**.
Both native pointer/drag/pinch/Observe cases pass. Both boundary failures occur
at the top swipe, after correct left/right delivery. Their diagnostic attachment
still contains the preceding right-edge ended callback, proving the top gesture
never reaches this recognizer. Its archive SHA-256 is
`eea3e0ecff5779514227a1e97ea219fbdd0372fabdc63a7aac82031820f848f1`.
The connected remote session currently shows the system status bar unless in
fullscreen, and the top test starts at the camera cutout. The prepared repair
hides the status bar for the connected session (including Observe, retaining
stable layout) and starts the physical top-edge swipe beside the cutout. The
asserted remote edge coordinates, all four edges, toolbar coverage and sheet /
Observe suppression remain required. Fresh VM execution must validate this
hypothesis; the current snapshot continues its clipboard and library suites.


The full asynchronous clipboard VM gate now passes **4/4 bilingual UI cases**,
with no skips, failures, missing cases, runtime warnings or animation completion
timeouts. Archived report SHA-256:
`e938b2043225e368541559b027b6f877b5e67db78fcef730774208978b0c8a2d`.
The English/Chinese Shared Clipboard submenus and oversized-paste alerts were
visually inspected: native menu/alert style, legible localized text and complete
buttons. This validates the frozen asynchronous-read snapshot, before the
prepared top-edge/fullscreen/version metadata changes; it is not physical-phone
or full Screens alignment acceptance. The remaining library8 suite is running.


The asynchronous full-run library suite passes **8/8 cases**, zero skips,
failures, runtime warnings or animation completion timeouts. Both narrow keyboard
customization cases now pass, including Cmd visibility and relaunch persistence.
Archive SHA-256: `a70b94ef6d5f3b996a6e4860eea4666583b03132d00ea650458dc1171a0ab194`.
All34 executed: controlled18/22, clipboard4/4, library8/8. The run is rejected
because of the four controlled failures. Its fixture/test processes exited and
the shared lock was confirmed absent. The next runner uses an explicit newline;
an earlier interpretation of the rendered lock escaping was not supported by
terminal evidence and is retracted.

The prepared top-edge production change also compiles in the signed arm64
Release candidate, version1.0.0/build1, with strict signature validation. The
executable SHA-256 is `70576bfd7952bb5185e404e0c88882148c6c473f155e6a063a5aaaae08352ed7`.
This is build evidence; focused four-case diagnosis and the subsequent full34
fresh-source gate, both phones and the remaining parity scope remain required.


The first top-edge/fullscreen diagnosis records **3/4 passed**, no skips, runtime
warnings or animation completion timeouts. Both fullscreen cases and the full
English boundary flow pass. Chinese reaches the bottom edge, whose ended callback
reports locationY609 and translationY-152; reconstructing origin gives Y761,
outside the 32-point bottom band of the 812-point window. Thus the recognizer
fires, but reset translation causes final classification to reject the original
edge contact. Archive SHA-256:
`5c2f2220cd9e0b4e3cc500eef7622580a83ce1297ba4d1440e26cc6f3c0a448a`.
The prepared input repair captures the first accepted touch in the delegate,
classifies final displacement against that contact, and clears stored origins on
completion/cancellation/detachment. Direction/distance thresholds, modal/Observe
suppression, all four exact coordinates and toolbar coverage remain unchanged.
Fresh bilingual diagnosis and full34 still must pass.


The actual-touch-origin repair passes the complete focused gate: **4/4 bilingual
fullscreen/boundary cases**, zero skips, failures, missing cases, runtime warnings
or animation completion timeouts. Both boundary cases assert all four exact
remote coordinates, bottom-edge coverage with the toolbar visible, modal input
suppression and Observe suppression. Archive SHA-256:
`df381ddc1dcb2dfc7efae9bea080948b3aa0a6e17232ed45b0205c6a8e1d8591`.
The newest signed arm64 Release also passes strict signature validation,
version1.0.0/build1, executable SHA-256
`e0740ad687e198b8475cbb51bfc9f9b452081bf4f8dc31f158767610f5fcdd58`.
The full34 fresh-source VM gate is next. Neither the focused pass nor signature
verification completes physical-phone, sustained responsiveness or full Screens
feature acceptance.

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
