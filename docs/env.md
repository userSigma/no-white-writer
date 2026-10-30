# 环境与构建记录（不白写作）

> 本文件只记录「这台机器上实际验证过的环境事实」，与 [根计划](<../PLAN.md>) 的规格分开。
> 最近一次核对：2026-10-29（P1 原生交互复验见 §11；普通启动失败及修正交付验证见 §10；0.4.0+4 的历史证据见 §9，§5–§8 保留历史）。

## 1. 工具链

| 项 | 值 | 状态 |
| --- | --- | --- |
| Flutter | 3.47.7 stable，revision `abaf9c5237`（2026-10-08） | ✅ 本机 `flutter --version` |
| Engine | revision `deb287481e`（2026-10-07） | ✅ 同上 |
| Dart | 3.13.5 stable（2026-09-29）`windows_x64` | ✅ `dart --version` |
| DevTools | 2.60.0 | ✅ |
| Visual Studio | 生成工具 2026 18.10.3 + Windows 10 SDK 10.0.26100.0 | ✅ `flutter doctor -v` = No issues found |
| 系统 | Windows 11 25H2（10.0.26200.9711）x64 | ✅ |
| Inno Setup | 6.7.3（per-user，不在 PATH） | ✅ `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` |

镜像（当前 shell 已生效，构建日志里会出现 `https://mirror.sjtu.edu.cn`）：

```powershell
$env:PUB_HOSTED_URL = 'https://mirror.sjtu.edu.cn/dart-pub'
$env:FLUTTER_STORAGE_BASE_URL = 'https://mirror.sjtu.edu.cn'
```

## 2. 插件符号链接（本机未开开发者模式）

本机 `AllowDevelopmentWithoutDevLicense = 0`，`flutter build windows` 会因
`Building with plugins requires symlink support.` 直接失败。绕过方式是用 junction
预占 Flutter 期望的 `.plugin_symlinks` 目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\fix_plugin_symlinks.ps1
flutter build windows --release
```

脚本从根目录 `.flutter-plugins-dependencies` 读取 Windows 插件清单，用
`cmd /c mklink /J` 在 `windows\flutter\ephemeral\.plugin_symlinks\<name>` 建占位。
**`flutter clean` 之后必须重跑**。长期建议打开「设置 → 系统 → 开发者选项 → 开发人员模式」，
开了一次就不用再管。

## 3. 开发/验收钩子（仅环境变量，不影响正常使用）

| 变量 | 作用 |
| --- | --- |
| `NWW_DATA_ROOT` | 覆盖数据根目录（默认 `%APPDATA%\不白写作`），仅用于隔离开发数据；不能代替普通启动验收。旧构建的低完整性标签问题见 §6 |
| `NWW_DEV_PAGE` | `editor` 启动到写作工作区；`settings` 在书架自动弹出同一个设置菜单，不再进入设置页；旧 `catalog` 兼容映射到写作工作区 |
| `NWW_DEV_TYPE` | 启动后把给定文本追加到正文（验收自动保存/退出保存用），需配合 `NWW_DEV_PAGE=editor` |

示例：

```powershell
$env:NWW_DATA_ROOT = 'C:\Users\userSigma\no-white-writer\.devdata'
$env:NWW_DEV_PAGE = 'editor'
.\build\windows\x64\runner\Release\no_white_writer.exe
```

## 4. 构建与验证命令

```powershell
cd C:\Users\userSigma\no-white-writer
flutter pub get
flutter analyze          # 期望 No issues found!
flutter test             # 2026-10-28 P1：327 tests, All tests passed!
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\fix_plugin_symlinks.ps1
flutter build windows --release
# 产物：build\windows\x64\runner\Release\no_white_writer.exe

# 普通启动检查：构建成功 ≠ 能正常启动（本机构建目录产物可能带 Low 完整性
# 标签，见 §6、§10）。凡声称“构建通过 / 可交付”，必须接着跑：
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify_normal_startup.ps1
```

`verify_normal_startup.ps1` 的 PASS 判据（缺一即 FAIL，不允许用 `NWW_DATA_ROOT`
等开发变量替代默认路径）：

1. Release 全部文件打包为 ZIP 并解压到 Downloads 下普通目录，逐一 SHA-256
   与构建源一致，解压后 exe 无 `Low Mandatory Level` 标签；
2. 不设任何开发环境变量、用默认 `%APPDATA%\不白写作` 启动，出现标题为
   「不白写作」的窗口；
3. 正常关窗退出，退出码 0，stderr 无 Dart 异常；
4. 启动前后默认作品目录文件哈希不变。

证据写入 `.devdata/verify-normal-startup-<时间戳>/` 与
`.devdata/verify-normal-startup-latest.json`；单实例锁被占用时会 FAIL，
先确认没有其他实例再复跑。

## 5. M1 实测结果（2026-10-26）

- release 构建 64～137 s（冷/热不同）；当时运行测试使用隔离数据目录，未验证默认 AppData 启动。普通双击失败的根因与修正交付方式见 §6。窗口逻辑 1280×820、物理 1600×1025（125% 缩放），最小 900×600。
- 书架 / 目录 / 编辑器 / 设置四个页面渲染正常，霞鹜文楷 GB 生效，深浅两套主题均正常。
- 自动保存：停止输入 5 s 落盘；`WM_CLOSE` 触发 `app.exit.requested` → `app.exit.accepted` 并退出；未到 5 s 关窗也不会丢字。
- 崩溃恢复：新 `.tmp` 优先转正并提示「上次异常退出 · 已恢复『第一章 灯下』」，`book.json` 标题不被改写、字数刷新。
- 单实例：第二份实例显示「不白写作已经在运行了」，不碰磁盘。
- `flutter test`：28 个（单词数 / 缩进 / 存储原子写与恢复 / 导出合并 / 书架与编辑器流程 / 书卷章增删改）。

## 6. 普通启动失败与发布包复测（2026-10-26）

用户报告「应用无法打开」后，已复现旧构建：进程存活，但 8 秒内没有可见窗口；stderr 为：

```text
Unhandled Exception: PathAccessException: Creation failed, path = 'C:\Users\userSigma\AppData\Roaming\不白写作\logs' (OS Error: 拒绝访问。, errno = 5)
#2 AppPaths.ensureLayout (package:no_white_writer/core/storage/app_paths.dart:40)
#3 main (package:no_white_writer/main.dart:36)
```

**根因：构建产物继承了旧沙箱目录的 Windows 低完整性标签，不是正常用户缺少 AppData 文件权限。**

- 旧 `Release` 目录和其中的 exe 均显示 `Mandatory Label\Low Mandatory Level:(I)(NW)`。
- 四个失败进程的访问令牌完整性级别为 `S-1-16-4096`（Low）；启动它们的普通 shell 为 `S-1-16-8192`（Medium）。
- 数据目录的当前用户权限已经是 FullControl；降低数据目录权限既无必要，也不应作为修复方式。
- 同一发布包复制到普通临时目录后，不改程序、不设 `NWW_DATA_ROOT` 即可启动；进程为 Medium，默认 AppData 日志出现 `app.instance.acquired` 与 `app.instance.held {held: true}`。因此此前用 `.devdata` 绕过目录限制的验证漏掉了真实启动问题。

**本次修正的是发布交付方式，未修改 Dart 业务逻辑，也未重写文件权限。**

1. 将整个 `Release` 的内容打为 ZIP，不携带原目录的安全标签。
2. 把 ZIP 解压到工作区外的普通用户目录；不要只复制 exe，也不要解压回旧沙箱构建目录。
3. 本机解压位置为 `C:\Users\userSigma\Downloads\不白写作-0.1.0-windows-x64\`。
4. 解压后的 21 个发布文件逐一进行 SHA-256 比对，均与原发布文件字节一致。其中 `no_white_writer.exe` 已在无开发环境变量的条件下启动，准确窗口标题为「不白写作」，进程完整性为 Medium，默认 AppData 初始化成功。
5. 再次运行 `flutter test -r expanded`：28 项通过；`flutter analyze`：No issues found，exit 0。

发布包：`build/packages/no-white-writer-0.1.0-windows-x64.zip`（25,382,157 字节）。
SHA-256：`148E4281F9DD44BC9491B6B0D830F90C50A3B1BF45FC8617B96E8FD2A48625AB`。

仍有单独的稳健性缺口：启动初始化异常尚未在界面中显示，而是在 stderr 中报告、进程无窗口；本次未把它描述成已修复，也未为此扩大修改范围。

## 7. 0.2.0 UI 修订验证（2026-10-26）

本节保留 0.2.0 的历史证据；0.3.0 本轮的新证据见 §8，不能用本节 56 项替代。

- `dart format lib test`：42 文件，最终 0 项变化；`flutter analyze`：No issues found，exit 0。
- `flutter test --reporter expanded`：**56 项全部通过**，最后一轮约 19 s，exit 0。含 13 项联合保存/备注/写队列测试、6 项工作区测试、9 项 UI 测试及原有回归测试。覆盖两种宽度的卷章增改排删、删除后不复活、失败草稿/重试、表单字符簇和组合态、固定卡片、最近章与展开记忆、Ctrl+A。
- `flutter build windows --release`：72.5 s 成功；exe FileVersion/ProductVersion 均为 `0.2.0+2`。构建后仅补充键盘测试与文档，未再改生产代码。
- 完整发布包：[no-white-writer-0.2.0-windows-x64.zip](../build/packages/no-white-writer-0.2.0-windows-x64.zip)，**25,408,174 字节**。SHA-256：`4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`。保留旧 0.1.0 ZIP，未覆盖。
- 解压目录：`C:\Users\userSigma\Downloads\no-white-writer-0.2.0-windows-x64-20261026-215146`。21 个文件逐一与 Release 原文件核对 SHA-256，一致；解压 exe 未继承 Low Mandatory Level 标签。
- 验收数据根为本轮全新临时目录，以 `NWW_DATA_ROOT` 隔离；用五本无 notes 字段的旧格式作品验证兼容，未读取或改动作者真实作品。此轮不冒充已复测默认 AppData 启动；默认路径的历史普通启动证据见 §6。
- 真实桌面 125%（DPI 120）：1280×820 → 物理 1600×1025、900×600 → 1125×750。书架由 5 列变为 3 列，卡片物理宽均为 275（逻辑宽 220）；宽屏侧栏、窄屏完整目录浮层、独立标题与紧凑新建表单均截图检查。
- 原生标题/正文输入后发 `WM_CLOSE`，日志为 `app.exit.requested` → `exit.composing.timeout`（500 ms）→ `chapter.saved` → `app.exit.accepted`，重启后两者仍在且 txt 不含标题。另从作品信息保存 `native-notes-020`，关窗重启后表单回显一致。只关闭本轮明确记录并校验 exe 路径的进程，未强杀其他实例。
- 原生 SendKeys 受输入法影响，Ctrl+A 自动输入未得到可靠的全选替换；独立 widget 键盘事件测试确认两个字段均可 Ctrl+A。不能把脚本输入当作微软/搜狗中文候选窗的完整人工验收。

尚待作者体验：中文长句、候选窗/失焦/撤销重做；150%/200%、多屏与系统文字缩放；其他平台仅保留代码适配边界，未构建。不包含 M2 功能，§6 所述初始化异常 UI 提示缺口仍未扩展修复。

本轮在 `ui/writing-workspace` 分支，原 M1 工程本就大多未跟踪。保留原始源码快照并在**副本**统一格式化后对照：生产逻辑差异仅 10 个文件（模型、原子写、入口、两个既有控制器、工作区控制器、三个工作区 UI 组件与书架）；其余 Dart 变动仅格式化。未把旧 M1 工程宣称为本轮新功能，也未合并或推送。

## 8. 0.3.0 目录、编号与安全移动验证（2026-10-27）

### 最终门禁与包身份

- 按作者 09:13 修订恢复 0.2 的朱砂、字体、彩色书脊、按钮、状态色、选区与 Fluent 弹窗，只把内容底色改为 `#FFFFFF` / `#000000`。对照实施前当前源码快照，主题 token 除这两个颜色外不变。
- `dart format --output=none --set-exit-if-changed lib test`：**57 文件、0 变化**；`flutter analyze --no-pub`：**No issues found，8.0 s，exit 0**；全测：**107 项通过，21 s，exit 0**。最后只补充损坏迁移记录的既有保护测试并格式化该测试，未再改生产代码。证据：[格式检查](<../.devdata/section17/final-format-check.log>)、[analyze](<../.devdata/section17/final-analyze.log>)、[全测](<../.devdata/section17/final-test.log>)。
- 最后一次生产代码构建：Windows x64 release **61.9 s**，exit 0；FileVersion / ProductVersion 均为 **0.3.0+3**。后续仅测试、文档及隔离验收脚本变化。证据：[构建](<../.devdata/section17/build.log>)、[发布门禁](<../.devdata/section17/final-label-gates.log>)。
- [完整 ZIP](<../build/packages/no-white-writer-0.3.0-windows-x64.zip>)：**25,465,992 字节**。SHA-256：`1D48C5E95DC80BA1C7FEF71C906BAF1021D5A016C3A6DEA4BB3900A94E270C0C`。旧 0.2.0 ZIP 的 `4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064` 仍一致，未覆盖。两个本轮中间候选已另行归档，不作交付包。
- 工作区外解压位置：`C:/Users/userSigma/Downloads/no-white-writer-0.3.0-windows-x64-20261027-103743`。**21 个文件**逐一与 Release 核对 SHA-256；原生运行后再次逐一核对，Release、解压副本与清单仍一致。证据：[包清单](<../.devdata/section17/package-manifest.json>)、[运行后校验](<../.devdata/section17/post-native-proof.log>)。

### 自动化安全覆盖

- 编号兼容、中文数词/补零/边界/溢出、独立规则与旧章名原样保留；目录、只读编号、窗口标题、导出名共用格式化，正文不插号。
- 真实 widget 握柄拖动覆盖 1280 / 900、同卷/双向跨卷、空卷/折叠卷、卷排序、原位/无效/取消、长目录边缘滚动及 Tab/方向键/Esc；带编号的真实应用根监听也参与测试，不以直接调用控制器冒充交互。
- 跨卷存储保留 txt / `.bak` 原字节、章 ID 和唯一归属；八个故障阶段重建服务并接续普通章节恢复。坏索引、坏迁移记录、预存目标、缺源、`.tmp` / `.bak.tmp` 停止而不重建覆盖。修正了复制旧备份后时间较新的假象：只在字节核验后校准正文时间，避免普通恢复误用旧备份；时间戳不是归属判据。
- 在途联合保存、组合输入阻止结构变更、移动后绑定、删除不复活、摘要失败与删除补偿、快速重复请求；内联卷名 Enter/失焦/Esc、失败留稿、宽窄关闭面板先提交或等待组合输入均有回归。设置版本号及纯白/纯黑标签也由真实 widget 断言。

### 最终包的原生隔离验收

- 数据根：`C:/Users/userSigma/AppData/Local/Temp/nww-section17-030-efc27761d2ab456d87d5b7f012ec4020`，仅本轮三本合成作品；从本轮中间验收根转入 25 个测试文件并逐一 hash 核验，不复制锁或日志。未读取、写入或迁移作者默认 AppData 作品，也不冒充再次完成默认路径普通启动验收。
- DPI **120 / 125%**：逻辑 1280×820、900×600；实际截图 1600×1025、1125×750。浅/深背景、0.2 彩色控件、目录与右键菜单可用；最终设置页实际显示 0.3.0 / 纯白 / 纯黑。
- 最终提取包的原生鼠标握柄：宽屏把当前章拖入折叠目标卷，标题即时为 `No.002 Raw chapter 0`，不展开目标；窄屏拖回折叠源卷，原 ID、当前选择、正文及备份保留，未遗留重复源文件或迁移记录。txt SHA-256 为 `FDD30176341C5F954EEF68EEC2F568CA0BCD5A689042C7F7CC8522F84B036F90`，bak 为 `D36B6363526E80029B220C0B1ECBAA54F8B251F99605AEE65C5F9DBFC36A0707`，前后相同。证据：[原生断言](<../.devdata/section17/release-native-assertions.log>)、[宽屏落点](<../.devdata/section17/release-wide-dragged.png>)、[窄屏返回](<../.devdata/section17/release-narrow-returned.png>)。
- 已通过真实 UI 编辑指定书的备注、卷名 `TargetEdited`、直接 `+` 新建默认未命名章节；中间候选先核验，最终包又完成独立原生输入 `release-title-030` / `release-body-030`。PID **36540** 关窗日志为 `app.exit.requested` → `chapter.saved` → `app.exit.accepted`；重启 PID **39884** 后两字段与字节校验仍通过，窗口标题为 `不白写作 — Native Book 0 · No.001 release-title-030`。两进程均先校验 exe 路径，仅发本轮自己的 `WM_CLOSE`，未强杀其他实例；最终无遗留自有进程。证据：[重启日志](<../.devdata/section17/release-restart.log>)、[重启正文截图](<../.devdata/section17/release-restart-editor.png>)。
- 两次验收脚本尝试不计为通过：等待期间测试实例已正常退出；一次沿用了恢复后的不同窗口几何、没有命中握柄。查明后重启并显式调整尺寸，才执行上述成功拖放；无文件归属或字节变化被误报为成功。

### 保留边界

- 原生输入是英文 SendKeys，不等于微软/搜狗中文候选窗的完整人工验收。中文长句、失焦/撤销重做、组合态跨响应式断点、多屏和 150% / 200% 仍待作者体验；其他平台未构建。
- 交互轮曾见 Flutter 引擎 AXTree 更新警告；未据此宣称无障碍读屏已完整验收。最终重启 stderr 仅为 Impeller 后端说明，无 Dart 异常；启动初始化失败的 UI 提示缺口仍是 §6 的既有边界。
- 分支仍为 `ui/writing-workspace`，HEAD `faa3f88f8080e784eb66f81a691ef159dd171ea1`。实施前快照与主题修订前快照均保留；当前对照 01:15 源码，lib 下有意差异为 **19 个文件路径（4 新建、15 修改）**，不把原未跟踪 M1 工程算成本轮新增。未使用子代理、未 reset/clean、未合并或推送。

## 9. 0.4.0 无框目录菜单与三级导出验证（2026-10-27）

### 门禁与交付包

- 最后生产修改是窄目录平台返回保护；之后仅文档／隔离验收脚本变化。新鲜 [format 检查](<../.devdata/section20/final-format-check.log>)：**71 文件、0 changed**；[analyze](<../.devdata/section20/final-analyze.log>)：**No issues found，7.0 s，exit 0**；[全测](<../.devdata/section20/final-test.log#L301>)：**280 项全部通过，45 s，exit 0**；[Windows x64 release](<../.devdata/section20/final-build.log>)：**60.8 s，exit 0**。FileVersion／ProductVersion 均为 **0.4.0+4**，设置选单关于为 0.4.0。
- [完整 ZIP](<../build/packages/no-white-writer-0.4.0-windows-x64.zip>)：**25,474,636 字节**，SHA-256 `2E6A26154126BEBD3E8046C92D757FC679E098E131BEE152B8461EB4A92B725E`。第一候选 `FFE96D220282DCCFBC9B18C5CF0E32166E6DFFF96FAECD121DCFDFF066B49515` 已归档，不是交付包。
- 外目录 `C:/Users/userSigma/Downloads/no-white-writer-0.4.0-windows-x64-20261027-211719`；Release 与外解压副本的 **21 个文件**在运行后再次逐一对照 [文件清单](<../.devdata/section20/package-manifest.json>)，无遗漏或多余项，SHA256 全部相等。[最终运行后核验](<../.devdata/section20/post-native-proof.log>) 同时确认自有 PID=0、版本与 ZIP 字节／hash。
- 旧 [0.2.0 ZIP](<../build/packages/no-white-writer-0.2.0-windows-x64.zip>) `4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`、[0.3.0 ZIP](<../build/packages/no-white-writer-0.3.0-windows-x64.zip>) `1D48C5E95DC80BA1C7FEF71C906BAF1021D5A016C3A6DEA4BB3900A94E270C0C` 均未覆盖。

### 自动化与实际纠错

- 真实 widget 菜单覆盖章／卷／书、当前／非当前、不同卷独立编号、真正空标题、空正文／无章／空卷混合、用户目录、重名两次、具体 TXT 全文与顺序；对源字节、当前绑定、偏好和唯一输出断言。旧真实拖放、迁移 8 阶段故障／重启恢复、摘要失败及删除不复活继续回归。
- 新增真实焦点及输入客户端测试，而不是只给 controller 设置 composing；修复点击目录菜单先失焦清除组词、生命周期强制保存提前提交候选。保存／读取／写出均有排他、延迟、失败、部分 tmp 清理与重试覆盖。
- 纠正 footer 放在整页外侧的错误及旧测试的错误期待，增加 1280／1100／900 目录内矩形、隐藏后不可达断言；平台返回先关窄目录，显式返回仍回书架。设置失败重试必须把保留的路径草稿真正写回，而非仅提示旧内存保存成功。原生打开目录失败不能否认已有输出，也不能重新生成文件。
- 初期编译／夹具／等待错误不算有效 RED；G1 缺项先红的过程偏差明确记于 [根计划 §22](<../PLAN.md#L1965>)，没有事后伪造 TDD 顺序。其余有效行为失败与修复及全部 280 项最终结果保留日志。

### 最终包的原生隔离验收

- 独立 `NWW_DATA_ROOT` 为 `C:/Users/userSigma/AppData/Local/Temp/nww-section20-040-791d4dc72b4a48abab8fdd3d33a735f3`，仅合成三本作品，不接触作者默认 AppData 作品。PID **18476** 实际清空卷章名、保存后 JSON 原名为空；原 **18 份 TXT／BAK**导出前后 hash 不变。
- 实际章／卷／书菜单导出逐字比对 UTF-8 内容、分隔、数组顺序及末尾换行。自有 `.txt.tmp` 故障明确拒绝；复核归属与原字节后删除本轮注入项，点击重试成功，无导出 tmp 残留。见 [最终导出验收](<../.devdata/section20/final-native-exports.log>)、[导出文件 hash](<../.devdata/section20/native-exports.json>)。
- 浅深无框菜单、扁平目录、宽屏完全收起／展开、目录内底部返回／向上设置／主题子选单、窄屏新建由真实鼠标键盘操作。新章输入 release-title-040／release-body-040 后立即 WM_CLOSE：21:21:16.890 请求、16.915 保存 words 16、16.927 接受退出，未等自动保存再假称关窗 flush。
- 重启 PID **11664**，实际点击书卡后 [正确回显标题／正文](<../.devdata/section20/final-restart-open-click.png>)，当前章和深色偏好保留；实际打开 [深色章节菜单](<../.devdata/section20/final-chapter-menu-dark.png>)，再以遮罩 [关闭窄目录](<../.devdata/section20/final-narrow-barrier-closed.png>)。仅向每次核对 EXE 路径的自有进程发 WM_CLOSE，最终自有 PID=0。见 [重启验收](<../.devdata/section20/final-native-restart-verified.log>)。
- 主验收 DPI **120／125%**：1280×820→1600×1025、900×700→1125×875。重启时返回 DPI **144／150%**，补充回读与菜单／遮罩观察（1920×1230、1350×1050）；不把它外推为完整 150% 矩阵。脚本初期异步激活检查和零时长按压失败不算通过；等待同一窗口激活、检查指针下 PID 并增加真实按压间隔后才得到成功记录。

### 边界与范围

- 原生中文长句、候选窗、撤销重做、组词跨响应式／多屏，完整 150% 及 200%／系统文字缩放仍待人工。动画中间帧、快速反向和减少动画由 widget 证明，不宣称已拍原生逐帧录像；先前未命中的 SendKeys Escape 不作为原生关闭证据，最终窄屏关闭使用真实遮罩点击。
- 其他平台未构建；本轮不重复声称默认 AppData 普通启动通过，§6 的初始化异常 UI 提示缺口仍保留。没有关闭作者实例，也没有改已有作品、运行目录或旧发布包。
- 以本轮 14:38 的 **87 文件**保护快照对照，实际 lib 差异 **20 条路径（6 新、13 改、1 删；2084 增／808 删）**，见 [逐路径清单](<../.devdata/section20/final-scope.json>) 与 [最终 diff](<../.devdata/section20/final-review-lib.diff>)；不是把未跟踪原 M1 都归为本轮新增。分支 `ui/writing-workspace`、HEAD `faa3f88f8080e784eb66f81a691ef159dd171ea1`，未用代理／队友，未提交、合并或推送，未 reset／clean。

## 10. P1 普通启动故障与修正交付（2026-10-28）

### 复现与根因

- P1 Windows release 构建成功不等于普通启动成功。用户报告后，在不设置 `NWW_DATA_ROOT` 等开发变量的情况下复现：进程存活、没有窗口，stderr 为 `PathAccessException: Creation failed`，目标为默认 `%APPDATA%/不白写作/languages`，`errno = 5`；失败位于 [AppPaths.ensureLayout](<../lib/core/storage/app_paths.dart#L44>)，尚未进入 P1 控制器逻辑。见[普通启动 RED](<../.devdata/p1-normal-startup-red.log>)。
- 原构建 exe 仍继承 `Mandatory Label/Low Mandatory Level:(I)(NW)`；六个已有无窗口进程的完整性均为 `S-1-16-4096`（Low），启动 shell 为 `S-1-16-8192`（Medium）。相同字节在隔离数据目录可启动，复制为正常发布包后也可使用默认数据根，印证是 §6 所述的产物安全标签问题，而非 P1 重构回归。
- 本次只修正交付位置与普通启动验收，不降低数据目录权限、不修改业务代码、不清理或迁移作品、不强杀用户原有进程；原 Low 标签构建路径仍不应作为日常启动入口。

### 可用交付与验证

- [完整 ZIP](<../build/packages/no-white-writer-0.4.1-p1-windows-x64-20261028-235311.zip>)：SHA-256 `A36D097C15FE24DFB35DA1AA24E2557CA63C8162FDEF5A07BC46AAE8BFD67726`。包含 P1 的现有 release，未更换二进制或伪称重新构建。
- 已解压到普通目录 `C:/Users/userSigma/Downloads/no-white-writer-0.4.1-p1-windows-x64-20261028-235311`，从[该目录 exe](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-p1-windows-x64-20261028-235311/no_white_writer.exe>)启动；必须保留同目录 DLL 和 data，不能仅复制 exe，也不要解压回旧 Low 构建目录。
- 发布包全部 **21 个文件**逐一与构建源做 SHA-256 比对；启动后再比对仍一致。提取后的 exe 无 Low 标签，实际 PID **35628** 为 Medium，未设置开发环境变量，默认 AppData 初始化成功，窗口标题准确为「不白写作」。
- 发出正常关窗请求后退出码 **0**；stderr 只有 Impeller 后端说明，无 Dart 异常。默认作品目录全部 **6 个文件**启动前后哈希不变；另与第一次正常启动前的快照复核，同样未变。所有本轮测试进程均已退出，用户此前的无窗口进程未处理。
- [最终原生验证日志](<../.devdata/p1-package-and-launch-final.log>)、[发布与启动验证脚本](<../.devdata/p1-package-and-launch.ps1>)、[源文件清单](<../.devdata/p1-release-startup-20261028-235311/source-manifest.json>)。
- 第一次验证脚本因未预先保留 PowerShell 进程句柄而读到空 `ExitCode`，不能算完整通过；补充句柄保留后，以上最终一轮完整通过。启动异常的界面提示仍是既有稳健性待办；本轮不扩大为初始化流程重构，亦不把启动验收外推为完整中文 IME／目录拖动的原生人工验收。

## 11. P1 原生交互复验（2026-10-29）

### 范围与隔离

- 使用当前 P1 Windows x64 release，通过真实窗口鼠标、键盘完成第 8 节主流程。数据根为 `.devdata/p1-native-acceptance-20261029-0030/data`，导出根为同目录下 `exports`；仅创建合成作品 `P1 Native Acceptance`，未读取或修改默认 AppData 作品，未操作启动前已有的六个同路径无窗口进程。
- 首次实例 PID **32876**，重启实例 PID **27352**，两次均通过原生窗口关闭并确认进程退出；两份 stderr 均只有 Impeller 后端说明，无 Dart 异常。启动、重启及应用日志均保留在上述验收根。

### 实际结果

- **自动保存：** 新建 `P1 Autosave Chapter`，输入英文正文后，界面从「未保存 25 字」变为「已保存 · 刚刚 25 字」；TXT 与 `book.json` 均为 25 字。[应用日志](<../.devdata/p1-native-acceptance-20261029-0030/data/logs/app.log>)记录 `2026-10-29 00:34:18.866 chapter.saved words: 25`。
- **跨卷移动：** 通过真实鼠标握柄把章 ID `8859d06d-210d-44bb-ad58-f306f519d39d` 从源卷 `5719c44e-0358-4104-be27-368b9eb1734d` 拖入折叠目标卷 `08af4174-2ffb-4096-baba-769b8c1d2526`。展开目标卷后 UI 归属正确，源 TXT／BAK 消失且目标出现；TXT SHA-256 前后均为 `152025c423d35e6562bfcfb1d451cec288550831f86610850f275f607b2c5ac1`，空 BAK 的 SHA-256 前后均为 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`。
- **删除：** 新建 `P1 Disposable Chapter`，经章节菜单及确认框删除；目录从 2 章回退为 1 章，当前选择回退到 `P1 Autosave Chapter`，重启后未复活。
- **导出：** 在设置中显式保存本轮隔离导出根，通过章节菜单执行「导出本章」；完成提示及实际路径正确。[导出 TXT](<../.devdata/p1-native-acceptance-20261029-0030/exports/P1 Native Acceptance/P1 Target Volume/P1 Autosave Chapter.txt>)的 UTF-8 正文逐字为 `P1 native autosave body 0029.`。
- **设置：** 从「跟随系统」切到「深色（纯黑）」后界面立即变黑；重启后深色主题及隔离导出目录仍正确回显。
- **关窗保存与重启：** 在正文追加 `P1 close flush 0048.` 后不等待自动保存，立即点击原生关闭。日志依次为 `00:43:47.273 app.exit.requested`、`00:43:47.347 chapter.saved words: 42`、`00:43:47.365 app.exit.accepted`；磁盘正文完整。使用同一数据根重启后，保留章仍位于目标卷，正文含关窗标记且统计为 42 字，删除章、主题和导出目录状态均符合预期。

### 边界

- 移动前一次 `Ctrl+ArrowDown` 未产生可见移动，随后改用真实拖放完成验收；不把该次尝试记为原生组合键通过，也不据此断言业务回归。键盘移动仍由既有组件回归覆盖。
- 原生输入采用英文文本粘贴，不等于微软／搜狗中文候选窗、中文长句、撤销重做或完整 IME 人工验收；未覆盖多屏、150%／200% DPI、系统文字缩放及完整无障碍读屏矩阵。本轮只闭环 P1 指定主流程，未扩展生产代码或 P2 范围。

## 12. P2 第二阶段整理与普通启动验证（2026-10-29）

### 自动化与范围

- 实施范围为[重构清单 §5](<重构清单.md#5-p2第二阶段整理2026-10-29-完成>)：设置浮窗组件拆分、页面显式依赖、导出控制器组合根装配、纯编号值对象／显示投影解耦。未使用子代理；未修改磁盘格式、存储恢复、编号算法、导出格式或状态管理框架。
- [格式检查](<../.devdata/p2-final-format.log>)：**103 文件、0 changed**；[静态分析](<../.devdata/p2-final-analyze.log>)：**No issues found**；[全量测试](<../.devdata/p2-final-full-test.log>)：**341 项全部通过**，含 324 项原有测试与 17 项 P2 新增回归。
- [Windows x64 release 构建](<../.devdata/p2-final-windows-build.log>)：**61.1 s，exit 0**。验证完成后仅回写文档，未继续改动生产或测试代码。

### 可用发布包与普通启动

- 使用现有[普通启动验证脚本](<../tool/verify_normal_startup.ps1>)打包、解压和核对；[完整 ZIP](<../build/packages/no-white-writer-0.4.1-5-windows-x64-20261029-171539.zip>)的 SHA-256 为 `4E7CD260FC0F0BCDA613BBC8FEB0BBAAAB868266B3C7FBBE2B69535156F8EEA3`，未覆盖旧包。
- [普通目录启动入口](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-5-windows-x64-20261029-171539/no_white_writer.exe>)：保留同目录 DLL 和 data；不以仍受 §6／§10 安全标签影响的构建目录 exe 作为日常入口。解压包 **21 个文件**在启动前后与构建源逐一 SHA-256 相符，exe 无 Low 完整性标签。
- 清除 `NWW_DATA_ROOT`、`NWW_DEV_PAGE`、`NWW_DEV_TYPE`，使用默认 AppData。自有 PID **40448** 显示标题「不白写作」、窗口句柄 **2821678**；正常关窗，退出码 **0**。原有 **8 份作品文件**启动前后 SHA-256 不变。stderr 仅 Impeller 后端说明，无 Dart 异常；启动前六个既有无窗口进程未处理。
- [普通启动日志](<../.devdata/p2-normal-startup.log>)、[本次源文件清单](<../.devdata/verify-normal-startup-20261029-171539/source-manifest.json>)、[启动前作品清单](<../.devdata/verify-normal-startup-20261029-171539/books-before.json>)与[最近成功启动记录](<../.devdata/verify-normal-startup-latest.json>)保留本地证据。

### 验收边界

- 本轮新鲜原生验证为普通启动、正常关窗及原作品字节不变；不把 P1 的交互记录记作 P2 重新执行。自定义主题、设置目录、失败留稿、真实输入客户端组词及草稿关闭守卫由组件回归验证，完整中文候选窗、多屏、DPI／文字缩放与无障碍人工矩阵仍待体验。

## 13. P2 浅包装清理与主题原生复验（2026-10-29）

### 自动化与构建边界

- 删除设置入口的 `open()` 私有转发和 `_row()` 共享组件浅包装，新增架构边界断言；定向主题及设置测试 **22 项**、完整套件 **343 项**全部通过，`flutter analyze --no-pub` 无问题。
- 原目录执行 `flutter build windows --release --no-pub` 因既有实例占用目标 exe 而失败：`LNK1104: 无法打开文件 ...\build\windows\x64\runner\Release\no_white_writer.exe`。未关闭或替换原有 **6 个**进程，不将这次失败记为原目录构建成功。
- 改用工作区隔离源码副本 `.devdata/p2-theme-native-src`（排除 `.git`、`build`、`.devdata`），执行依赖恢复、插件链接修复及 Windows x64 release 构建，最终成功。该副本仅用于构建和验收，不记为额外产品源码修改。

### 真实 Windows 界面结果

- 以 `NWW_DATA_ROOT=C:/Users/userSigma/no-white-writer/.devdata/p2-theme-native-acceptance-20261029-1902/data`、`NWW_DEV_PAGE=settings` 启动本轮实例 PID **9196**；仅操作该实例，未读取或修改默认 AppData 作品。
- **创建：** 新建主题「原生纸墨」，设置背景 `F7F2E8`、强调色 `356859`；创建并应用后，下拉框、成功提示、纸张背景和绿色强调色均即时正确显示。
- **关闭守卫：** 创建对话框打开时父设置窗「关闭」禁用；点击原生窗口 X 后应用未退出，创建对话框和父设置窗保留，并提示「草稿尚未完成保存或仍在输入法组词，已取消关闭。」。
- **重命名：** 在管理自定义主题分区将「原生纸墨」改为「原生青墨」，下拉框与管理列表同步更新。
- **删除：** 确认删除后管理入口消失，主题回退「跟随系统」，界面恢复默认朱砂色。最终隔离 `settings.json` 的 `themeMode` 为 `system`、`customThemes` 为 `[]`。
- 关闭设置返回空书架后，通过原生 X 正常退出；PID **9196** 已退出，既有 **6 个**进程仍在且路径不变。stderr 仅 Impeller OpenGL 后端说明，无 Dart 异常。
- 当时非阻断观察：重命名对话框输入区域偏高，功能及关闭流程不受影响；该视觉问题随后在 §14 单独修正并复验。文本通过真实窗口输入粘贴完成，不外推为完整中文输入法候选窗、多屏、DPI／文字缩放或无障碍矩阵验收。

## 14. P2 主题重命名输入区域收窄（2026-10-29）

### 根因与自动化

- 原生现象可在组件测试稳定复现：1568×1007 测试视口下，重命名 `TextBox` 高度为 **595 px**。`ContentDialog` 以两层 `Flexible` 布局内容，直接放置的输入框会占用剩余最大高度；仅增加 `maxLines: 1` 不改变该高度，未作为修正保留。
- 将内容改为 `mainAxisSize: MainAxisSize.min`、横向拉伸的 `Column`，使输入框按固有高度布局。新增大窗口高度不超过 48 px 的回归，先得到 **595 px** 的预期失败，再转为通过；空白名称禁用及确认修剪既有测试继续通过。
- `flutter analyze --no-pub` 无问题；完整套件 **344 项全部通过**。沿用 §13 的隔离源码副本同步这一处生产修正，Windows x64 release 构建成功；未声称被 6 个既有实例占用的原目录构建成功。

### 原生复验与清理

- 使用独立数据根 `.devdata/p2-rename-native-acceptance-20261029-2149/data` 和 `NWW_DEV_PAGE=settings` 启动 PID **37116**，未读取或修改默认 AppData 作品。
- 创建临时主题「紧凑布局验收」后打开重命名对话框，真实 UIA 测得输入区域为 **391×38 px**；对话框恢复紧凑布局，不再出现大段输入空白。实际改名为「紧凑布局已验收」，下拉框和管理列表同步更新。
- 删除临时主题后回退「跟随系统」，最终 `settings.json` 的 `themeMode` 为 `system`、`customThemes` 为 `[]`。关闭设置返回空书架，再通过原生 X 正常退出；PID **37116** 已退出，既有 **6 个**进程保持未动，stderr 仅 Impeller OpenGL 后端说明，无 Dart 异常。

