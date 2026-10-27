# 不白写作 · 设计与实施计划

> 本文件是本项目的唯一事实来源。实现与本文冲突时，先改本文、再改代码。
> 状态：**0.2.0 已交付，整体待作者体验验收；§17 黑白界面、目录交互与卷级编号设计已确认，书面规格待最终审阅，尚未实施**（2026-10-26；§16.8 保留上一轮证据与限制）。
> 技术基线：Flutter 3.47.7 / Dart 3.13.5；v1 只发布 Windows x64；代码结构适配 macOS ARM、Windows ARM、Linux、Android。
> 最后更新：2026-10-26（新增 §17 已确认设计的完整规格；本次只改文档。上一轮 §15 已实施且有 56 项测试与发布包验证记录，但不是 §17 的验证证据。）

---

## 0. 一句话定义

一个本地优先、无账号、无云同步的中文长篇写作工具：书架摆放作品，每本书由「卷 → 章」组成，每章是一个纯文本文件，写着就自动保存，关窗、断电、崩溃都不丢字。

---

## 1. 目标与非目标

### 1.1 v1 目标（必须做到）

| 编号 | 目标 | 可测判据 |
| --- | --- | --- |
| G1 | 启动即书架 | 冷启动 1.5 s 内可见书架，无闪屏路由跳转 |
| G2 | 全分辨率可用 | 900×600 与 3840×2160@200% 下无溢出、无遮挡、正文可读 |
| G3 | 纯文本写作闭环 | 建书 → 建卷 → 建章 → 写 → 关窗 → 重开，内容逐字一致 |
| G4 | 自动保存不丢字 | 停止输入 5 s 后落盘；强杀进程后重启，最多丢 5 s 内容且能恢复 |
| G5 | 中文输入法友好 | 微软拼音连续组合、空格/数字/回车选词上屏，不重复、不丢字、不跳光标 |
| G6 | 数据可带走 | 单章 / 整卷 / 整书三种 txt 导出；整库可备份 |
| G7 | 五端代码结构就绪 | 新增平台只需实现 `core/platform` 接口，不改业务与数据层 |

### 1.2 非目标（v1 明确不做）

- 云同步、账号、协作、多端同步；不做登录。
- Markdown / 富文本 / 插图 / 脚注 / 批注 / 大纲视图。
- 跨书全文搜索（v1 连书内搜索都没有，只有章内查找替换）。
- 拖拽排序（v1.1）、多窗口、标签页。
- 自动更新器（新安装包原地覆盖升级）。
- 遥测、崩溃上报、任何联网行为（v1 除 pub 依赖外零网络）。
- macOS / Windows ARM / Linux / Android 的**构建产物**：只保证代码结构与平台抽象到位，产物留到对应平台阶段。
- 版本库 CI 矩阵、golden 测试、代码覆盖率门槛。

### 1.3 三条不可妥协的红线

1. **数据安全优先于功能**：宁可不保存，也不写出半个文件。
2. **磁盘是最终事实**：索引（json）损坏可以重建，正文 txt 不可丢。
3. **不拦截 IME**：任何排版自动化不得破坏中文输入法的组合态。

---

## 2. 环境与硬约束（2026-10-25 实测）

| 项 | 实测值 | 状态 |
| --- | --- | --- |
| Flutter SDK | `C:\Users\userSigma\develop\flutter`，3.47.7 stable，Dart 3.13.5，engine 2026-10-07 | ✅ 已装 |
| Windows | Windows 11，10.0.26200，AMD64 | ✅ |
| Visual Studio | 生成工具 2026 + VC++ x86/x64（`vswhere -requires VC.Tools` 命中） | ✅ 可编译 |
| Git 仓库 | `C:\Users\userSigma\no-white-writer`，main 干净，`8579eab Initial commit`，仅 GPL-3.0 LICENSE 与一行 README | ✅ |
| 远端 | `https://github.com/userSigma/no-white-writer.git` | ✅ |
| `flutter --version` | **用户于 2026-10-25 在真实 PowerShell 验证通过**：Flutter 3.47.7 stable，revision `abaf9c5237`（2026-10-08），engine revision `deb287481e`（engine hash `d8a2d6c768c334d53e16277f837970ffa1e2de81`，2026-10-07），Tools Dart 3.13.5 / DevTools 2.60.0；`dart --version` = Dart SDK 3.13.5 (stable, 2026-09-29) on `windows_x64` | ✅ 已人工验证 |
| `flutter doctor -v` | **用户于 2026-10-25 验证：`No issues found!`**。VS 生成工具 2026 18.10.3（`18.10.12224.181`），Windows 10 SDK `10.0.26100.0`；Android SDK 36.0.0（platform android-37.2 / build-tools 36.0.0，license 全接受，JDK 25.0.3）；Chrome 155；Network resources 全绿（镜像 `https://mirror.sjtu.edu.cn` 可用） | ✅ 全绿 |
| 沙箱 HTTPS | **本会话已解除**：文件策略改为 `danger-full-access` 后，`curl` 访问 `pub.dev` 得 `http=200`、镜像 `http=301`；`flutter pub add` 实际拉下 40 个包 | ✅ 可用（早期 `SEC_E_NO_CREDENTIALS` 是沙箱限制） |
| pub 镜像 | 环境变量 `PUB_HOSTED_URL=https://mirror.sjtu.edu.cn/dart-pub`、`FLUTTER_STORAGE_BASE_URL=https://mirror.sjtu.edu.cn` 已配；`doctor` Network resources 全绿；`pub add` 实测成功 | ✅ |
| pub 缓存 | `fluent_ui 4.17.0`、`path_provider 2.1.6`、`window_manager 0.5.2` 已落缓存（依赖共 40 个，见 §5.4） | ✅ |
| **Windows 开发者模式** | 注册表 `AppModelUnlock\AllowDevelopmentWithoutDevLicense = 0`（2026-10-26 二测仍为 0；UAC 提权被用户取消）。构建改用 junction 绕过（§2.2） | ⚠️ 未开启，已绕开 |
| **Inno Setup 6** | **6.7.3 已装（per-user）**：`C:\Users\userSigma\AppData\Local\Programs\Inno Setup 6\ISCC.exe`；最小安装包 5.5 s 编译成功（产物 2.1 MB）；**不在 PATH**，脚本必须写全路径 | ✅ 可用 |
| Windows release 构建 | `flutter build windows --release` 成功（127 s），产物 `build\windows\x64\runner\Release\gate0.exe` 双击可运行 | ✅ 通过 |
| 窗口尺寸 / DPI | DPI 120（125%）：窗口 1280×820 **逻辑** = 1600×1025 物理，客户区 1582×978；`setMinimumSize(900,600)` 生效（尝试缩到 300×300 被钳到 900×600）；`window_manager` 尺寸 API 按**逻辑像素**处理 | ✅ 通过 |
| 退出拦截 | `WM_CLOSE` → `AppLifecycleListener.onExitRequested`：有文本返回 `cancel` 窗口存活；无文本返回 `exit` 进程退出 | ✅ 两分支均验 |
| `windowManager.getTitle()` | 中文返回乱码 `Gate0 涓嶇櫧鍐欎綔`（UTF-8 被按 ANSI 解码）；`setTitle()` 正常，进程主窗口标题正确 | ⚠️ 记入 R17 |
| `path_provider` | support = `%APPDATA%\com.example\gate0`（= `<Company>\<Product>`）；documents = `C:\Users\userSigma\Documents`；目录可写 | ✅ 通过 |
| bash 工具 | `EXECUTOR_UNAVAILABLE`（`CreateFileMapping ... Win32 error 5`）；本会话仍只用 pwsh | ❌ 本机只用 pwsh |
| Flutter CLI（本会话） | `flutter --version` 2.9 s 返回 0；`flutter create` / `pub add` / `analyze` / `build windows --release` 全部可跑 | ✅ 沙箱内可执行 |

**结论（2026-10-26 二测）**：Gate 0 的**静态与运行期主体已经通过**——依赖拉取、静态分析、release 构建、窗口尺寸/最小尺寸/DPI、退出拦截、`path_provider` 实路径、Inno Setup 编译全部拿到实证（§2.2）。两端机器前置条件已各自解决一半：Inno Setup 装好了，开发者模式仍关着但用 junction 绕开了。**剩余只有需要人手的两项**：① 微软拼音在 fluent `TextBox` 与裸 `TextField` 里的上屏/组合态行为；② 裸 `TextField` 的 Ctrl+Z / Ctrl+Y 撤销重做。另外"系统文字缩放是否改变 `textScaler`"需人工改一次 Windows 设置验证（默认 100% 时 `textScaler=1.0`，不影响 §4(c) 结论）。

### 2.1 已确认的框架行为（读源码得到，不是猜测）

- `packages/flutter_tools/lib/src/commands/build_windows.dart:68-71`：Windows 目标架构由**宿主架构**决定（x64 宿主出 `windows-x64`，ARM64 宿主出 `windows-arm64`），`flutter build windows` **没有** `--arch` 参数。
- `packages/flutter/lib/src/widgets/app_lifecycle_listener.dart:154-163`：`onExitRequested` 返回 `AppExitResponse.cancel` 可以取消退出。**注意（3.47 实测）**：`AppExitResponse` 已迁到 `dart:ui`（`services/binding.dart` 里写作 `ui.AppExitResponse`），业务代码需 `import 'dart:ui' show AppExitResponse;` 才能编译。
- `packages/flutter_tools/lib/src/flutter_plugins.dart:1215-1239`：Windows 上插件符号链接创建失败（`ERROR_PRIVILEGE_NOT_HELD`，1314）时，工具直接退出，提示「开启开发者模式，或用管理员终端」——这是本机当前唯一挡在 `build/run` 前面的门槛。
- `packages/flutter/lib/src/services/binding.dart:583-589`：`initializationComplete` 的注释说明，Windows 上需要注册引擎的顶层窗口 handler，才能收到 `System.requestAppExit`。
- `packages/flutter/lib/src/services/system_channels.dart:158-173`：`System.exitApplication` 与 `System.requestAppExit` 通道。
- `dart-sdk/lib/io/file.dart:281-284`：`rename` 会替换已存在的目标文件；`:911` 有 `flushSync`。
- `packages/flutter/lib` 下没有 `window*.dart`：**框架不提供窗口尺寸/最小尺寸 API**，必须引 `window_manager`。
- 已知上游 Windows IME issue：`#190042`（重获焦点后组合中断）、`#191194`（`maxLines: 1` 下空格上屏重复文本）、`#191196`（组合态跨 TextField 泄漏）。我们的用法（`maxLines: null`）绕开 #191194，但仍需实测 #190042/#191196。

### 2.2 Gate 0 运行期实证（2026-10-26，临时工程 `%TEMP%\_nww_gate0`）

**如何在没有开发者模式时构建**（临时手段，不是长期方案）：Flutter 把插件以符号链接挂在 `windows\flutter\ephemeral\.plugin_symlinks\<plugin>`；工具逻辑是「目标已存在就跳过」（`flutter_plugins.dart:1259-1276` 的 `if (link.existsSync()) continue;`），所以可以先用**目录联接（junction）**占位——junction 不需要提权：

```powershell
$sym = "windows\flutter\ephemeral\.plugin_symlinks"
# 名字与目标来自 windows\flutter\ephemeral\.flutter-plugins-dependencies
cmd /c mklink /J "$sym\window_manager" "<pub-cache>\window_manager-0.5.2"
```

本次四个 Windows 插件 `jni`、`path_provider_windows`、`screen_retriever_windows`、`window_manager` 都这样占位后，`flutter build windows --release` 一次通过（127 s）。**风险**：`flutter clean`、或任何以 `force: true` 刷新插件列表的命令会删掉该目录，之后必须重新建;真正长期方案仍是开启开发者模式（R15）。

**实测数字（release 版，实机 125% 缩放）**：

| 观测 | 值 | 说明 |
| --- | --- | --- |
| 进程主窗口标题 | `Gate0 不白写作` | `setTitle()` 正常 |
| `windowManager.getSize()` | `1280.0 × 820.0` | 逻辑像素 |
| Win32 `GetWindowRect`（DPI 虚拟化后） | `1280 × 820` | 物理 `1600 × 1025` |
| 客户区物理尺寸 | `1582 × 978` | 逻辑 `1265.6 × 782.4`，边框 9 px、标题栏 47 px（物理） |
| DPI | `120`（125%） | `devicePixelRatio = 1.25` |
| 系统文字缩放 | `textScaler = 1.0`（默认 100%） | 结论同 Q4(c)：字号由应用自控 |
| 缩到 300×300 后 | `900 × 600` | 最小尺寸生效 |
| 退出拦截（有文本） | 窗口存活，`exitRequested=cancel` | `WM_CLOSE` → `onExitRequested` |
| 退出拦截（无文本） | 进程退出，`exitRequested=exit` | 同上 |
| `getApplicationSupportDirectory()` | `C:\Users\userSigma\AppData\Roaming\com.example\gate0` | 结构 = `<APPDATA>\<Company>\<Product>` |
| `getApplicationDocumentsDirectory()` | `C:\Users\userSigma\Documents` | 导出/备份落点 |
| Inno Setup 最小包 | 5.5 s 编译，2.1 MB | `ISCC.exe` 全路径调用 |

**给实现的直接结论**：

1. 数据根若坚持 `%APPDATA%\不白写作\`（Q2/§4 的默认值），**不能**直接用 `getApplicationSupportDirectory()`（它会给出 `<Company>\<Product>` 两级）；要么在 `Runner.rc` 里把 Company/Product 设成期望值，要么用 `%APPDATA%` + `不白写作` 自行拼。建议后者，路径可控且与 §4 一致。
2. **禁止**用 `windowManager.getTitle()` 读标题做判断（中文乱码）；标题只写不读。
3. 初始窗口尺寸要按**工作区**收敛：`min(1280, workAreaW × 0.9) × min(820, workAreaH × 0.9)`，同时不低于 `900 × 600`——否则 1366×768 的笔记本上 820 高会超出屏幕（新增 R18）。
4. 退出拦截的判定条件是 `controller.text.isNotEmpty`；**IME 组合态文本不在 `controller.text` 里**，所以 §7 的"composing 非空则跳过保存"必须在人工 IME 测试里专门覆盖。

---

## 3. 决策清单（Q1–Q29，全部已定）

| # | 主题 | 决策 |
| --- | --- | --- |
| Q1 | 作品结构 | 书 → 卷 → 章；**每章一个独立 txt**，不存数据库大字段 |
| Q2 | 数据位置 | 应用私有目录（AppData），界面上不暴露文件树；只提供导出 |
| Q3 | 保存策略 | 5 s debounce 自动存 + 失焦/切章/回书架/关窗强制 flush；原子写 `.tmp → rename`；每章一份 `.bak` |
| Q4 | 窗口与栅格 | (a) 默认 1280×820、最小 900×600；(b) 书架卡片最大宽 220，列数自适应；(c) 字号应用内自控，**不随系统缩放** |
| Q5 | 平台策略 | 只做代码层 `core/platform` 抽象；v1 只构建 Windows；不做 CI 矩阵 |
| Q6 | 交付物 | 根目录单文件 `PLAN.md`；产品名「不白写作」 |
| Q7 | 规模上限 | 单章 ≤ 2 万字；每卷 ≤ 200 章；单书 ≤ 500 万字；书架 ≤ 200 本 |
| Q8 | 卷章操作 | v1 不做拖拽，只上移/下移 + 新建追加末尾；数据预留 `order`；新建章弹输入框、回车即建、默认「第 N 章」，不吸正文首行 |
| Q9 | 书架卡片 | 按书名哈希生成渐变色书脊 + 书名 + 「N 卷 · M 章 · X 万字」+ 最近编辑；默认最近编辑倒序，可切按书名；v1 无搜索；键盘 ↑↓ 选择、回车打开 |
| Q10 | 导出 | 单章 / 整卷 / 整书合并三种 txt；UTF-8 无 BOM、LF；合并时插卷名与章名分隔行；设置页整库 zip 备份；默认目录 `文档\不白写作\`，完成后可打开文件夹；不做 Markdown |
| Q11 | IME 与保存 | composing 非空 → 跳过本次自动保存并保持 dirty；关窗时组合态最多等 500 ms，超时照常保存并记日志 |
| Q12 | 崩溃恢复 | 启动非阻塞提示「上次异常退出，已恢复第 X 章」；`.tmp` 比 `.bak` 新时优先 `.tmp`；关窗保存失败**阻止退出**，只给「重试」「导出到文档后退出」；`.bak` 每章 1 份，保存前旧文件先改名 |
| Q13 | 视觉与字体 | Fluent 风格 + 自定义暖白/墨色主题（跟随系统亮暗，可手动切）；正文内置霞鹜文楷 GB（OFL），UI 用系统字体 |
| Q14 | 编辑页 | 左侧两级目录 + 正文最大宽 760 + 顶部极简条；< 900 宽目录转抽屉；字号调节、专注模式 F11、章内查找替换、撤销重做、字数统计、脏标记 |
| Q15 | 技术选型 | 依赖 3 个（path_provider、window_manager、fluent_ui）；状态用 `ChangeNotifier` + `ValueListenableBuilder`；导航 `Navigator 1.0` |
| Q16 | 分发与单实例 | Inno Setup 安装包；运行期文件锁检测单实例并提示 |
| Q17 | 三方 UI 库 | 引入 `fluent_ui`，`FluentIcons` 取代 Material 图标；Android 的桌面观感留到平台适配阶段 |
| Q18 | 标题栏与底色 | 系统原生标题栏；不透明纸感底（暖白 `#F7F3EC`、墨色 `#17181A`）；**不做 Mica、不自绘标题栏** |
| Q19 | 签名 | 不签名；接受 SmartScreen 首次提示；Release 附 SHA256 |
| Q20 | 排版 | 首行缩进在**存储层真插两个 U+3000**；段间默认不空行、可选开启；行距默认 1.9（可调 1.4–2.4）；v1 字体固定，只调字号 |
| Q21 | 查找替换 | 仅当前章；「全部替换」弹确认并显示替换条数；不做大小写敏感；保留全角/半角匹配开关 |
| Q22 | 保存节奏 | 固定 5 s 不可配置；加每日自动备份 |
| Q23 | 标识 | 包名 `no_white_writer`、exe `no_white_writer.exe`、org `com.usersigma`、版本 `0.1.0`、Inno AppId `ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b`；窗口标题与快捷方式「不白写作」 |
| Q24 | 里程碑 | M1 可写闭环（书架/卷章树/编辑器/自动保存/崩溃恢复/单章导出）；M2 完整版（查找替换/Fluent 打磨/卷与书导出/整库 zip/安装器/专注模式） |
| Q25 | 安装与卸载 | 按用户安装到 `%LOCALAPPDATA%\Programs\不白写作`，不弹 UAC；卸载默认保留作品，勾选「同时删除我的作品」才删；卸载器**永不主动**碰 `%APPDATA%\不白写作` |
| Q26 | 编辑器实现 | 外壳控件用 `fluent_ui`；正文用**裸 `TextField`**（精确控制 controller / composing / UndoHistory / 自动保存） |
| Q27 | 回车缩进 | 回车自动补两个 U+3000；新行已有则不重复；段中回车前半保留、后半补缩进；粘贴不自动补（「规整缩进」列 v1.1）；首段也缩进、可手动删 |
| Q28 | 兼容性闸门 | Gate 0 在示例工程验证 fluent_ui 能编译 + 中文输入可用；不通过则回落「自绘 Fluent 观感」，架构与数据层不动 |
| Q29 | 每日备份 | 落 `文档\不白写作备份\`；保留 7 天；先写临时 zip 再改名；设置页显示上次备份时间与「打开备份文件夹」 |

### 3.1 未经逐条确认、视为已接受的默认值

窗口尺寸/位置/最大化记忆；启动永远进书架；侧栏折叠状态记忆；Esc 回书架；Ctrl+S 立即保存；主题三态（跟随/浅/深）默认跟随；索引分层 `library.json` + 每书 `book.json` + 每章 txt；日志 `logs/app.log` 滚动 5 份；单实例锁在数据目录；图标用 `FluentIcons`；字体只打包 Regular 一个字重；单元测试覆盖存储/自动保存状态机/索引重建，不做 golden；单人直推 main；窗口标题格式「不白写作 — 书名 · 章名」；v1 无自动更新；无遥测、无崩溃上报、日志仅本地；备份 zip 不含 `.bak` 与日志。

### 3.2 两处默认值（2026-10-26 已按推荐采纳，仍可随时推翻）

1. **字数口径**：默认「去除所有空白字符（空格、换行、U+3000、Tab、NBSP）后的字符数，含标点」——**已采纳并实现**（`core/text/word_count.dart`）。
2. **数据目录名**：默认 `%APPDATA%\不白写作`（中文目录名，便于用户手动找）——**已采纳并实现**（`Platform.environment['APPDATA']` 自拼，不用 `getApplicationSupportDirectory`）。

---

### 3.3 实施期的边界修正（不改决策，只解决两处冲突）

1. **Q14 的「< 900 转抽屉」与 Q4 的「最小窗口 900×600」冲突**（窗口永远不会小于 900，抽屉分支成死代码）。实施改为：**目录抽屉断点 `< 1000`**；侧栏宽度 `≥1280` 取 280，`1000–1280` 取 240。
2. **Q7 的单章上限 2 万字**意味着"20 万字压测"没有现实入口。性能验证改为：**2 万字（上限）必测 + 5 万字（超限压力）观测**，5 万字卡顿时不作为缺陷，只记录。

## 4. 数据模型与磁盘布局

### 4.1 目录结构

```
%APPDATA%\不白写作\                     ← 数据根（path_provider 实测校准，见 §5.3）
├─ instance.lock                        ← 单实例文件锁（含 pid 与启动时间）
├─ settings.json                        ← 窗口几何、主题、字号、行距、开关、上次备份时间
├─ library.json                         ← 书架索引（书列表）
├─ books\
│  └─ <bookId>\
│     ├─ book.json                      ← 本书卷章索引
│     ├─ book.json.bak
│     └─ volumes\
│        └─ <volumeId>\
│           ├─ <chapterId>.txt          ← 正文（唯一事实来源）
│           ├─ <chapterId>.txt.bak      ← 上一份完整正文
│           └─ <chapterId>.txt.tmp      ← 仅崩溃残留时存在
├─ logs\
│  ├─ app.log                           ← 当前日志
│  └─ app.log.1 … app.log.4             ← 滚动备份，合计 5 份 × 512 KB
└─ trash\                               ← v1 删除的章/卷移到这里，不物理删除
   └─ <bookId>\<timestamp>-<chapterId>.txt
```

外部目录：

```
文档\不白写作\                          ← 默认导出目录（可改）
文档\不白写作备份\                      ← 每日 zip（固定，不随导出目录改）
```

### 4.2 为什么用 id 做文件名

章节标题随时改、卷可重排。若文件名含标题或序号，每次重命名都要改文件，崩溃时会出现"索引与文件不一致"的中间态。**用不可变 id 做文件名、标题只存 json**，重命名/排序都是纯索引操作，零文件风险。用户看不到这一层（私有目录 + 导出时还原成书名目录）。

### 4.3 `library.json`

```json
{
  "schemaVersion": 1,
  "books": [
    {
      "id": "6f1d0c2e-8a4b-4c1d-9f2e-3a5b7c9d1e0f",
      "title": "长夜将明",
      "createdAt": "2026-10-20T21:14:03+08:00",
      "updatedAt": "2026-10-25T09:31:22+08:00",
      "coverSeed": 481916,
      "lastOpenedChapterId": "a1b2c3d4-0000-4000-8000-000000000002",
      "volumeCount": 3,
      "chapterCount": 47,
      "wordCount": 386421
    }
  ]
}
```

- `coverSeed` 由书名哈希得到，决定书脊渐变配色（见 §6.9），保证同一本书每次打开颜色一致。
- `wordCount` / `chapterCount` 是缓存值，仅供书架显示；与磁盘不一致时以重建结果为准。

### 4.4 `book.json`

```json
{
  "schemaVersion": 1,
  "id": "6f1d0c2e-8a4b-4c1d-9f2e-3a5b7c9d1e0f",
  "title": "长夜将明",
  "volumes": [
    {
      "id": "b7e2...",
      "title": "第一卷 雪线",
      "order": 0,
      "chapters": [
        {
          "id": "a1b2c3d4-0000-4000-8000-000000000001",
          "title": "第 1 章 名字",
          "order": 0,
          "wordCount": 3210,
          "updatedAt": "2026-10-25T09:31:22+08:00"
        }
      ]
    }
  ]
}
```

- `order` 是 0 起始整数，允许并列（并列时按标题拼音排序作为稳定兜底）。
- 章号「第 N 章」是**标题字符串的一部分**，不是计算属性：用户可把标题改成任意文字，界面不自动重编号（避免改标题导致序号错乱）。
- 没有 `fileName` 字段：文件名恒为 `<chapterId>.txt`。

### 4.5 版本与迁移

- `schemaVersion` 目前为 `1`。
- 读到 `schemaVersion > 1`：**只读模式**，界面顶部常驻横幅「本作品由更新版本创建，只能查看不能编辑」，所有写入入口禁用。
- 读到 `schemaVersion < 1` 或缺失：视为损坏，走 §4.8 重建。
- v1 不写迁移代码；未来新增字段一律"有默认值即可缺省"，只在**结构变化**时才升版本。

### 4.6 原子写协议（唯一允许的正文写入路径）

```
S0  markDirty(chapterId, newText)
S1  触发：5s debounce 到期 / flush(失焦、切章、切书、Ctrl+S、关窗) / 重试
S2  若 controller.value.composing.isValid && !isCollapsed → 本次跳过，保持 dirty，安排下一轮
S3  写 <id>.txt.tmp：open(write) → writeString(UTF-8) → flush() → close()
S4  若 <id>.txt 存在：rename(<id>.txt → <id>.txt.bak)      // 覆盖旧 bak
S5  rename(<id>.txt.tmp → <id>.txt)                        // 覆盖旧 txt
S6  更新内存索引 wordCount/updatedAt，索引标记为 dirty（30 s debounce 或切章时落盘）
S7  状态 → clean，记录日志 chapter.save.ok
```

失败处理：任一步抛异常 → 状态 `failed`，**保留 `.tmp`**，不进入 clean，写 `chapter.save.fail`，界面显示「未保存」+ 重试按钮，并按 5 s / 10 s / 20 s / 40 s / 60 s 退避重试。

**不变量**：

- I1 任何时刻，磁盘上 `<id>.txt` 或 `<id>.txt.bak` 至少有一个存在。
- I2 `<id>.txt` 一旦存在，必为完整文件（先 tmp 后 rename，rename 是原子替换）。
- I3 退出流程在 flush 返回成功之前，不得调用退出 API。
- I4 索引落后于正文是可接受状态，任何时刻可由目录重建。

### 4.7 崩溃恢复判定表

启动后逐章扫描（M1 只扫上次打开的 1 本书，M2 起扫全部书、限 200 章/扫描窗口）：

| 现场 | 判定 | 动作 |
| --- | --- | --- |
| 有 `.tmp`，且 `.txt` 不存在或 `mtime(tmp) > mtime(txt)` | 崩在 S5 之前（tmp 是最新内容；也可能是 S4 后 txt 暂时消失） | 候选 = `.tmp`；提示「已恢复第 X 章」，确认后 `rename(tmp → txt)`，旧 txt 转 bak |
| 有 `.tmp`，且 `mtime(tmp) <= mtime(txt)` | 崩在 S3 中途或残留 | 删除 `.tmp`，用 `.txt` |
| 无 `.tmp`，有 `.bak`，`mtime(bak) > mtime(txt)` | 崩在 S4 与 S5 之间 | 候选 = `.bak`，恢复流程同上 |
| `.txt` 缺失，有 `.bak` | 文件被外部删除 | 从 `.bak` 恢复，提示 |
| `.txt` 与 `.bak` 都缺失 | 正文丢失 | 索引里标记该章「文件缺失」，允许用户重新建章或从备份 zip 恢复 |
| `book.json` 无法解析 | 索引损坏 | 走 §4.8 重建，标题回退「第 N 章」 |

提示形态：书架页底部 InfoBar（非模态、可关闭），点击跳到该书该章；**任何情况下不弹模态框拦截启动**。

### 4.8 索引重建

触发：`library.json` / `book.json` 无法解析、`schemaVersion` 异常、用户手动删改文件、恢复流程发现索引与目录不一致。

```
1. 扫描 books\* → 对每个目录尝试读 book.json
2. book.json 坏 → 扫描 volumes\* 目录（目录名即 volumeId），标题回退「卷 N」
3. 每个 volume 目录下的 *.txt（排除 .bak/.tmp）→ 每文件一章
   章 id = 文件名去掉 .txt；章标题回退「第 N 章」；order 按文件名排序
4. wordCount 按 §8.3 口径现场统计；updatedAt 取文件 mtime
5. 重建结果先写成 book.json.tmp，再 rename 覆盖；原损坏文件改名 book.json.corrupt-<ts>
6. 写日志 library.rebuild / book.rebuild，书架提示一次
```

### 4.9 导出规格

| 类型 | 目标路径 | 内容 |
| --- | --- | --- |
| 单章 | `文档\不白写作\<书名>\<卷名>\<章名>.txt` | 该章正文原样 |
| 整卷 | `文档\不白写作\<书名>\<卷名>.txt` | 卷内各章按 order 拼接 |
| 整书 | `文档\不白写作\<书名>.txt` | 所有卷所有章按 order 拼接 |
| 整库备份 | 用户选定目录 `<YYYYMMDD-HHmmss>-不白写作.zip` | `library.json` + 全部 `book.json` + 全部 `.txt`；不含 `.bak`、`.tmp`、日志 |

- 编码 UTF-8 无 BOM，换行 LF，末尾补一个换行。
- 合并分隔行（默认，可推翻）：

```
──── 卷：第一卷 雪线 ────

──── 章：第 1 章 名字 ────

（正文）
```

- 文件名清洗：去掉 `\ / : * ? " < > |` 与控制字符，长度上限 80 字符，重名加 ` (2)`。
- 导出完成弹 InfoBar：「已导出 N 个文件」+「打开文件夹」按钮（`Process.run('explorer', [dir])`）。
- 写入同样走"临时文件 → rename"，中途失败不留半个文件。

---

## 5. 模块与目录结构

### 5.1 分层与依赖方向（单向，不允许反向 import）

```
features/  →  state/  →  core/storage/, core/text/, core/platform/, theme/
                 ↘  core/logging/
```

- `features/` 只做界面与交互，不碰 `dart:io`。
- `state/` 持有内存模型与自动保存状态机，调 `core/storage`。
- `core/storage/` 只管读写与恢复，不认识 Flutter widget。
- `core/platform/` 是唯一允许出现 `Platform.isWindows` / `Process.run` / `window_manager` 的地方。

### 5.2 `lib/` 树

```
lib/
├─ main.dart                        启动：目录 → 日志 → 单实例 → 窗口 → runApp
├─ app.dart                         FluentApp、主题、路由表、全局生命周期监听
├─ core/
│  ├─ platform/
│  │  ├─ platform_services.dart     抽象接口（见 §5.3）
│  │  ├─ platform_services_desktop.dart   Windows/macOS/Linux 实现（window_manager）
│  │  ├─ platform_services_mobile.dart    Android/iOS 实现（无窗口，no-op）
│  │  └─ path_utils.dart            自实现 join/basename/sanitize（不新增 path 依赖）
│  ├─ storage/
│  │  ├─ atomic_file_writer.dart    writeAtomically(path, text)
│  │  ├─ library_store.dart         library.json + settings.json 读写
│  │  ├─ book_store.dart            book.json 读写 + 重建
│  │  ├─ chapter_store.dart         章 txt 读/写/删（进 trash）/恢复扫描
│  │  ├─ backup_service.dart        每日 zip
│  │  └─ export_service.dart        单章/卷/书导出
│  ├─ text/
│  │  ├─ word_count.dart            字数口径
│  │  └─ indent_rules.dart          回车缩进规则（纯函数，可单测）
│  ├─ logging/app_logger.dart       滚动日志
│  └─ ids.dart                      UUID v4（Random.secure，零依赖）
├─ state/
│  ├─ app_state.dart                依赖装配（InheritedWidget 风格，不用 provider 包）
│  ├─ library_controller.dart
│  ├─ book_controller.dart
│  ├─ editor_controller.dart        文本缓冲、composing、undo 快照
│  ├─ autosave_controller.dart      §7 状态机
│  └─ settings_controller.dart
├─ features/
│  ├─ shelf/                        shelf_page / book_card / new_book_dialog
│  ├─ catalog/                      catalog_panel / chapter_tile / rename_dialog
│  ├─ editor/                       editor_page / editor_toolbar / status_strip
│  ├─ find/                         find_replace_bar / highlighting_controller
│  ├─ export/                       export_dialog
│  ├─ settings/                     settings_page
│  └─ shell/                        app_shell / route_observer / exit_guard
└─ theme/
   ├─ tokens.dart                   颜色、间距、圆角、字号常量
   └─ app_theme.dart                FluentThemeData 亮/暗
assets/fonts/LXGWWenKaiGB-Regular.ttf
assets/fonts/OFL-LXGWWenKai.txt
test/..                             见 §10.4
```

### 5.3 `core/platform` 抽象

```dart
abstract interface class PlatformServices {
  Future<Directory> dataRoot();          // Windows: %APPDATA%\不白写作
  Future<Directory> documentsRoot();     // Windows: 文档\不白写作 (导出默认)
  Future<void> setWindowTitle(String title);
  Future<void> setMinimumWindowSize(Size size);
  Future<WindowGeometry?> restoreGeometry();
  Future<void> saveGeometry(WindowGeometry geometry);
  Future<void> setFullScreen(bool on);   // 专注模式
  bool get supportsExitIntercept;        // 桌面 true，Android false
  Future<bool> revealInFileManager(String path);
  Future<void> quit();
}
```

- 窗口几何 = `{x, y, width, height, maximized}`，存 `settings.json`。
- `path_provider` 的 `getApplicationSupportDirectory()` 在 Windows 上实际落在哪，Gate 0 实测；**若路径不是 `%APPDATA%\不白写作`，则不用它，改为读 `Platform.environment['APPDATA']` 自行拼路径**（中文目录名不能被包名覆盖）。
- `revealInFileManager`：Windows `explorer`，macOS `open`，Linux `xdg-open`。
- `supportsExitIntercept` 在 Android 上恒 false，退出改为 `AppLifecycleState.paused` 时 flush。

### 5.4 依赖（3 个运行时 + 2 个开发）

| 包 | 约束 | 用途 | 平台说明 |
| --- | --- | --- | --- |
| `path_provider` | `^2.1.0`（实测锁定 `2.1.6`） | 文档目录、平台数据目录兜底 | 全平台 |
| `window_manager` | `^0.5.2`（Gate 0 实测版本） | 最小尺寸、几何、标题、全屏 | 仅桌面；移动端不 import |
| `fluent_ui` | `^4.17.0`（Gate 0 实测版本） | 外壳控件、FluentIcons、ContentDialog、InfoBar | 全平台 |
| `flutter_lints`（dev） | 用 `flutter create` 生成的版本，不手改 | 静态检查 | — |
| `flutter_test`（dev） | SDK | 单测 | — |

- **Gate 0 实测依赖体积**：`pub add` 一次引入 40 个包，其中 `fluent_ui` 4.17.0 会带进 `material_ui` / `cupertino_ui` / `intl` / `math_expressions` / `scroll_pos`，以及仅移动端用得上的 `jni` / `objective_c` 等。桌面 release 只链实际用到的代码，但**安装包体积要在 M3 量一次**；若超预算，优先怀疑这些传递依赖与内置字体，而不是先砍功能。
- **fluent_ui 4.17.0 API 实测要点**（写代码前先看，避免返工）：
  - `FluentThemeData.accentColor` 要的是 `AccentColor`（`AccentColor.swatch({'normal': color})`），不是裸 `Color`；
  - 4.17 **没有** `NavigationBody`；`NavigationView` 的页面由 `NavigationPane` 里每个 `PaneItem.body` 提供；
  - `AppExitResponse` 在 `dart:ui`，不在 `services`；
  - `FluentIcons` 名称按 4.17 的 `FluentIcons.library` 一类取（不是 Material 名）。
- 版本策略：pubspec 用 caret，**提交 `pubspec.lock`**，升级单独提交并跑全量测试；不从 transitive 依赖直接 import。
- 不新增其他依赖：UUID、路径拼接、字数、缩进、查找替换全部自己写（都在 `core/`，可单测）。
- 字体：`assets/fonts/` 打包 Regular 一个字重，`pubspec.yaml` 声明 family `LXGWWenKaiGB`。

### 5.5 条件导入与平台差异

| 关注点 | Windows | macOS | Linux | Android |
| --- | --- | --- | --- | --- |
| 窗口 API | `window_manager` | 同左 | 同左 | 不 import（stub） |
| 数据根 | `%APPDATA%\不白写作` | `~/Library/Application Support/不白写作` | `~/.local/share/不白写作`（或 `$XDG_DATA_HOME`） | app 私有目录（`getApplicationSupportDirectory`） |
| 文档根 | `%USERPROFILE%\Documents` | `~/Documents` | `~/Documents` | app 外部文档目录 |
| 退出拦截 | `AppLifecycleListener.onExitRequested` | NSApplication terminate（需实测） | GTK delete-event（需实测） | 无 → paused 时 flush |
| 打开文件夹 | `explorer` | `open` | `xdg-open` | 不支持（禁用按钮） |
| 构建命令 | `flutter build windows --release`（宿主架构） | `flutter build macos` | `flutter build linux` | `flutter build apk` |

实现方式：`platform_services.dart` 用 `dart.library.io` + `Platform.isXXX` 在同一文件里分支即可，**不需要**三方条件导入语法（没有 web 目标）；`window_manager` 的 import 放在 desktop 实现内，mobile 实现不引用它。

### 5.6 状态与导航

- `AppState` 用 `InheritedNotifier` 挂在 `FluentApp` 之上，暴露各 Controller（不引 provider）。
- 正文滚动/输入不走 setState 高频重绘：`TextEditingController` + `ValueListenableBuilder` 局部刷新；字数/状态条 300 ms 节流。
- 路由：`onGenerateRoute` → `/shelf`、`/book/:bookId`、`/settings`、`/export`（对话框优先，路由仅用于整页）。`FluentPageRoute` 做转场。
- 退出守卫：`app.dart` 注册 `AppLifecycleListener(onExitRequested:)`，直接 await `autosaveController.flushAllForExit()`。

### 5.7 错误处理分层

| 层 | 处理方式 |
| --- | --- |
| IO 失败（磁盘满、权限、文件被占用） | 不抛给 UI 崩溃：转 `SaveFailure`，进 §7.5 流程 |
| JSON 解析失败 | 走重建（§4.8），提示一次，不阻塞 |
| 未捕获异常 | `FlutterError.onError` + `runZonedGuarded` → 写日志 + InfoBar「出现异常，已记录日志」 |
| 断言/开发期错误 | debug 直接红屏，release 走上一行 |

---

## 6. 界面与交互规格

### 6.1 书架（`/shelf`）

```
┌ 顶部 64 ─────────────────────────────────────────────┐
│ 书架     [排序：最近编辑 ▾]              [＋ 新建书] [⚙] │
├──────────────────────────────────────────────────────┤
│  ▢ 卡片  ▢ 卡片  ▢ 卡片  ▢ 卡片  ▢ 卡片  ▢ 卡片        │
│  ▢ 卡片  ▢ 卡片  …                                    │
└──────────────────────────────────────────────────────┘
```

- 内容区 `SliverPadding(horizontal: 32, vertical: 24)`，`GridView` 用 `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, crossAxisSpacing: 16, mainAxisSpacing: 20, childAspectRatio: 0.72)`；整块内容再套 `ConstrainedBox(maxWidth: 1600)` 居中，超宽屏不把卡片拉成一片。按此参数，900 宽约 4 列、1280 宽约 6 列（验收不锁死列数，只看不溢出）。
- 卡片（220×305 上限）：
  - 上部 62% 高度：书脊色块，135° 线性渐变，两色由 `coverSeed` 从 12 组低饱和配色里取（§6.9）；圆角 8；左上角竖排 3 个像素宽的书脊亮线（1 px 白 12% 叠层）。
  - 下部：书名 15 sp 最多 2 行、`ellipsis`；第二行 `12 sp` 次要色「3 卷 · 47 章 · 38.6 万字」；第三行「昨天 22:41」。
  - hover：抬起 2 px 阴影 + 边框高亮；focus：2 px 强调色描边（键盘可见）。
- 排序：默认 `updatedAt` 倒序；下拉切「按书名」（`title.compareTo`，中文按 Unicode 码位序，不是严格拼音序；v1 不引拼音库，接受这个局限）。
- 空态：居中 `FluentIcons.library` 48 px + 「还没有作品」+「新建第一本书」按钮。
- 键盘：方向键在网格内移动焦点，`Enter` 打开，`F2` 重命名，`Delete` 删除（`ContentDialog` 二次确认，文案含「作品目录：…」与「不会立即物理删除」）。
- 新建书：`ContentDialog`，一个 `TextBox`（默认「未命名作品」），`Enter` 确认，重复名允许（id 唯一）。
- 底部恢复 InfoBar 见 §4.7。

### 6.2 书内目录树（`/book/:bookId` 左栏）

- 宽 280（`≥1280` 时）；`1000–1280` 取 240；`<1000` 收进抽屉（与 §3.3 的边界修正一致）。
- 头部：返回书架、书名（`F2` 改名）、`＋卷`。
- 两级：卷行（展开箭头 + 卷名 + `＋章` + 更多菜单）、章行（缩进 16 + 标题 + 字数右对齐 12 sp）。
- 行高 32；当前章背景强调色 12% + 左侧 3 px 强调色条。
- 菜单（右键或行尾 `⋯`）：重命名、上移、下移、删除。首项时「上移」禁用、末项时「下移」禁用（v1 不做拖拽，见 Q8）。
- 卷级菜单：重命名、上移、下移、删除（卷下有章时，删除需二次确认，整卷移入 `trash\`）。
- 底部：`＋ 新建章`（在当前卷末尾追加）、`＋ 新建卷`。
- 新建章：轻量输入框（不是完整对话框），默认填「第 N 章」（N = 该卷章数 + 1），`Enter` 建章并选中，`Esc` 取消；**不读取正文首行做标题**。
- 状态记忆：每本书的展开卷、选中章存 `settings.json`；折叠态跨会话保留。

### 6.3 编辑器（`/book/:bookId` 右侧）

```
┌ 工具条 48 ────────────────────────────────────────────┐
│ ← 长夜将明 · 第 3 章 雪夜      3,214 字  已保存 22:41  [🔍][⛶][⋯] │
├ 正文区（水平居中，最大 760）────────────────────────────┤
│     　　他推开窗，风灌进来，带着雪粒。                  │
│     　　远处有人在敲钟。                               │
│                                                       │
└───────────────────────────────────────────────────────┘
```

- 只有裸 `TextField`（`maxLines: null`, `expands: true`, `keyboardType: TextInputType.multiline`, `textInputAction: TextInputAction.newline`），外面包 `Scrollbar`。
- 样式：`fontFamily: 'LXGWWenKaiGB'`，默认 `fontSize 18`（设置可调 14–28），`height: 1.9`（设置可调 1.4–2.4），颜色 `ink`，光标 `accent`，`cursorWidth 1.5`，`selectionColor` accent 20%。
- 正文区左右 padding：宽度 ≥ 1280 时 `(可用宽 - 760)/2`，否则 24/32；上下 padding 48/80，保证首行不贴工具条。
- 工具条右侧状态：`clean` → 「已保存 HH:mm」灰；`dirty`/`saving` → 「保存中…」强调色 + 转圈 12 px；`failed` → 「未保存」危险色 + 点击展开重试。
- 工具条按钮：查找（Ctrl+F）、专注（F11）、更多（导出本章、重新加载、打开数据目录、删除本章）。
- 切章：先 `await flush()`，再换 controller；切换过程 100 ms 内完成，不闪白。
- 光标：每章保存最后 `selection.baseOffset` 到内存（v1 不写盘），切回时恢复；进程重启后回到开头（可接受，写入 §13 观察项）。
- 章节为空时显示占位「从这里开始写…」，占位不参与字数。

### 6.4 查找替换（章内）

- `Ctrl+F` 在工具条下方展开一条 40 px 面板，不遮挡正文；`Esc` 关闭并清除高亮。
- 组成：查找框、替换框、`全/半` 匹配开关、`↑` `↓`、`全部替换`、关闭（v1 不做大小写敏感，故不设 `Aa` 开关）。
- 匹配：全部命中高亮 `accent` 25%，当前命中 `accent` 55% + 自动滚动可见；`Enter` 下一个，`Shift+Enter` 上一个。
- 实现：自定义 `HighlightingTextEditingController extends TextEditingController`，覆写 `buildTextSpan`，保留父类对 composing region 的下划线处理（**不得**覆盖 composing 高亮，否则 IME 预编辑区会花掉）。
- 全角/半角开关打开时，匹配前把模式与正文都做 NFKC 归一化再比较（只影响匹配，不改文本）。
- 全部替换：`ContentDialog`「将在本章替换 N 处，替换后可用下方「撤销本次替换」恢复」；执行前把旧全文存入内存快照；替换后 InfoBar 提供「撤销本次替换」（30 s 内有效，进程内）。
- 单条替换：替换当前命中的这一处，光标跳到下一处。

### 6.5 专注模式

- `F11` 或工具条按钮 → `window_manager` 全屏 + 隐藏工具条与目录栏，只留正中央正文与右下角淡出的字数（2 s 后 30% 透明度）。
- `Esc` 第一次退出专注，第二次回书架（两级 Esc，写进 §6.7）。
- 退出专注恢复原窗口几何（几何在进入前快照）。

### 6.6 设置页（`/settings`，从书架齿轮进入）

| 分组 | 项 | 默认 | 说明 |
| --- | --- | --- | --- |
| 外观 | 主题 | 跟随系统 | 跟随 / 浅色 / 深色 |
| 外观 | 正文字号 | 18 | 14–28，步进 1，实时预览 |
| 外观 | 行距 | 1.9 | 1.4–2.4，步进 0.1 |
| 排版 | 段间空行 | 关 | 开 → 回车插入空行 + 缩进（§8.2） |
| 排版 | 自动缩进 | 开 | 关 → 回车只换行（§8.1） |
| 数据 | 数据目录 | `%APPDATA%\不白写作` | 只读显示 + 「打开」 |
| 数据 | 导出目录 | `文档\不白写作` | 「更改」「打开」 |
| 数据 | 每日备份 | 开 | 上次备份时间 + 「立即备份」「打开备份文件夹」 |
| 关于 | 版本 | 0.1.0 | 点 5 次显示日志目录 |
| 关于 | 许可 | GPL-3.0 / 字体 OFL | 链接到仓库与字体许可 |

所有设置改动立即生效并写 `settings.json`（`atomic_file_writer`，不需要 debounce，量小）。

### 6.7 快捷键总表

| 快捷键 | 作用域 | 行为 |
| --- | --- | --- |
| `Ctrl+S` | 全局 | 立即 flush 当前章 |
| `Ctrl+Z` / `Ctrl+Y` | 编辑器 | 撤销 / 重做（由 `TextField` 的 UndoHistory 提供，Gate 0 实测确认） |
| `Ctrl+F` | 编辑器 | 打开查找替换 |
| `Esc` | 查找面板 → 专注 → 书架 | 逐级退出 |
| `Ctrl+=` / `Ctrl+-` | 全局 | 字号 +1 / -1 |
| `F11` | 全局 | 专注模式开关 |
| `F2` | 书架/目录树 | 重命名当前项 |
| `Delete` | 书架/目录树 | 删除（二次确认） |
| `Enter` | 书架/树/新建章 | 打开 / 确认 |
| `↑ ↓ ← →` | 书架 | 网格焦点移动 |
| `Ctrl+N` | 书架 | 新建书 |

### 6.8 响应式与缩放

- 断点（与 §3.3 一致）：`< 1000`（目录转抽屉，书架 3–4 列）；`1000–1600`（双栏：240 或 280 目录 + 正文）；`> 1600`（内容居中限宽 1600，书架最多约 7 列）。
- **系统文字大小**：在 `app.dart` 根部用 `MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling))` 显式忽略，字号只由应用内设置决定（Q4c）。这违反常规无障碍预期，已在 §11 R10 登记。
- **系统 DPI（100/125/150/200%）**：由 Flutter `devicePixelRatio` 处理，不写死像素；验证项进 §10.5。窗口最小尺寸 900×600 是**逻辑像素**，在高 DPI 下物理更大，符合预期。
- 不允许出现横向滚动条；卡片文字超长一律截断，不撑破布局。

### 6.9 主题令牌（`theme/tokens.dart`）

| Token | 亮（暖白纸） | 暗（墨） |
| --- | --- | --- |
| `paper` 底色 | `#F7F3EC` | `#17181A` |
| `surface` 卡片/栏 | `#FFFDF8` | `#1F2023` |
| `ink` 正文 | `#2B2A27` | `#EDE8DF` |
| `inkSecondary` | `#6B655C` | `#A8A29A` |
| `divider` | `#E3DBCC` | `#33353A` |
| `accent` | `#A6402B`（朱砂） | `#D97A5E` |
| `accentHover` | `#8C3524` | `#E8907A` |
| `danger` | `#B3261E` | `#E98A80` |

- Fluent 主题用 `FluentThemeData(accentColor: …, scaffoldBackgroundColor: paper, …)`，控件圆角统一 6，控件密度 `compact`（桌面阅读场景）。
- 书脊 12 组配色（低饱和、同明度）：赭石、黛青、松绿、绛紫、茶褐、靛蓝、苔绿、砖红、灰蓝、杏黄、墨绿、紫檀；`coverSeed % 12` 取主色，副色为主色 HSL 明度 +12%。
- 不引第三方配色库；色值全部集中在 `tokens.dart`，禁止在 widget 里写十六进制。

### 6.10 提示规范

- 需要用户决策 → `ContentDialog`（删除、覆盖、全部替换、退出失败）。
- 只需告知 → `InfoBar`（恢复成功、导出完成、备份完成、保存失败），2–6 s 自动消失，可手动关闭，最多同屏 2 条。
- 禁止用 `SnackBar`（Fluent 视觉不统一）。

---

## 7. 自动保存与数据安全状态机

### 7.1 状态定义（`SaveState`）

| 状态 | 含义 | 界面 |
| --- | --- | --- |
| `clean` | 内存与磁盘一致 | 「已保存 HH:mm」灰 |
| `dirty` | 有未落盘改动，5 s 计时中 | 「保存中…」（等待态） |
| `saving` | 正在写 | 「保存中…」+ 转圈 |
| `failed` | 写失败，`.tmp` 已保留 | 「未保存」红 + 重试 |
| `blocked` | 处于 IME 组合态，暂不写 | 无额外提示（避免干扰输入） |

### 7.2 转移表

| 事件 \ 当前 | clean | dirty | saving | failed | blocked |
| --- | --- | --- | --- | --- | --- |
| 文本变化 | → dirty(重置 5 s) | → dirty(重置) | 记 pending，完成后再存 | → dirty(重置) | → dirty(保持) |
| 5 s 到期 / flush | ─ | 组合态→blocked；否则→saving | 排队等当前完成 | 退避后→saving | 组合结束→saving |
| 写成功 | ─ | ─ | → clean(更新索引) | → clean | ─ |
| 写失败 | ─ | ─ | → failed(保留 tmp) | → failed(退避+1) | ─ |
| 组合开始 | ─ | → blocked | 不打断当前写 | → blocked | ─ |
| 组合结束 | ─ | ─ | ─ | → dirty | → dirty(立即 5 s) |
| 切章/切书 | 立即放行 | await flush | await | 弹失败流程 | await ≤500 ms |

### 7.3 触发源（全部走同一个 `flush()`，串行）

1. 编辑停止 **5 s**（固定，不可配）。
2. 编辑器失焦（窗口失焦、点目录树、点工具条）。
3. 切章、切书、回书架、退出专注。
4. `Ctrl+S`。
5. 关窗请求（`onExitRequested`）。
6. 保存失败后的退避重试（5/10/20/40/60 s，上限 60 s）。
7. 应用进入 `paused`/`inactive`（Android 上就是唯一保存时机）。

### 7.4 IME 保护

- 判定组合态：`controller.value.composing.isValid && !controller.value.composing.isCollapsed`。
- 组合中：不写、不重建 `TextEditingValue`、不做任何会改变 selection 的操作（查找高亮只改 `buildTextSpan`，安全）。
- 关窗时仍在组合：最多等 **500 ms**，期间每 50 ms 轮询一次；超时按当前文本保存并写日志 `exit.ime-timeout`（Q11）。
- 已知规避点：不实现"输入即格式化"（不在 `TextInputFormatter` 里改文本），避免 #190042/#191194 类问题；缩进只在换行这一动作上做（§8.1 的方案仍需 Gate 0 验证）。

### 7.5 保存失败流程（关窗）

```
onExitRequested
  ├─ flush() 成功 → AppExitResponse.exit
  └─ flush() 失败 → ContentDialog（不可 Esc 关闭）
        ├─ [重试] → 再 flush，仍失败则停在对话框
        └─ [导出到文档后退出] → exportService.exportChapter(临时路径)
              ├─ 成功 → AppExitResponse.exit（并在下次启动提示"已导出到…"）
              └─ 失败 → 回到对话框，只留 [重试]
```

`AppExitResponse.cancel` 后不退出，窗口保持；日志记 `exit.cancel` + 错误原因（磁盘满 / 权限 / 被占用）。

### 7.6 并发与幂等

- 每个 `chapterId` 一条串行 Future 链（`_writeQueue`），同一章永不并发写。
- `flush()` 在 `saving` 中再次被调用：不新开写，复用一个"等待句柄"，返回同一个 Future。
- 写盘内容取**调用瞬间的快照**（`controller.text` 的不可变副本），写完只把 `clean` 打在该快照对应的版本号上；若写完发现版本号已变，状态回 `dirty` 并再排一次（防"写旧文本把新文本标成已保存"）。
- 索引写入独立 30 s debounce；退出前强制写索引，失败不阻断退出（索引可重建）。

### 7.7 日志事件（`logs/app.log`，行格式 `时间 | 级别 | 事件 | 详情`）

`app.start` / `app.exit` / `library.load` / `library.rebuild` / `book.rebuild` / `chapter.save.ok`（含字数与耗时 ms）/ `chapter.save.fail`（含异常与路径）/ `chapter.recover`（含来源 tmp/bak）/ `exit.request` / `exit.cancel` / `exit.ime-timeout` / `backup.ok` / `backup.fail` / `export.ok` / `export.fail`。

滚动：单文件 512 KB，保留 5 份（`app.log` … `app.log.4`），写满即轮转。

---

## 8. 中文排版与文本规则

### 8.1 回车缩进（Q20/Q27）

常量：`INDENT = '\u3000\u3000'`（两个全角空格，U+3000）。

| 场景 | 结果 |
| --- | --- |
| 段末回车（光标在行尾） | 插入 `'\n' + INDENT`，光标落在缩进之后 |
| 段中回车（光标后还有正文） | 插入 `'\n'`；光标后的文本若已以 `INDENT` 开头则不再补，否则补上 `INDENT`；前半段原样保留 |
| 连续回车（新行位置已带缩进） | 只插入 `'\n'`，不叠加 U+3000（避免空段落累积空格） |
| 段首回车（光标在行首、该行有字） | 当前段落整体下移一行，新行插入 `INDENT`，原行保留自身缩进 |
| 粘贴多行文本 | **不自动补缩进**（v1.1 提供「规整缩进」命令） |
| 用户手动删掉缩进 | 尊重现状，不追着补；下一次回车仍按规则补新行 |
| 「自动缩进」开关关闭 | 一律只插入 `'\n'` |

实现路径（需 Gate 0 验证，见 R3）：监听 `TextEditingController` 的文本差分，检测"单个换行插入"，再在一次 `value` 赋值里完成缩进补齐；**不使用** `TextInputFormatter` 拦截，避免与 IME 的组合提交冲突。若差分方案在 IME 下仍不稳，回落为"保存前规整"（会把用户故意删缩进的行补回来，需在设置里说明，再不行则 v1.1 做）。

### 8.2 段间空行（默认关）

打开后回车产生：

```
（上一段）
（空行，不含全角空格）
　　新段落
```

即插入 `'\n\n' + INDENT`。

### 8.3 字数口径（默认，可推翻）

- 计数单位：Unicode 码点（`text.runes.length` 前先过滤）。
- 过滤：删除所有空白字符——`\u0020`、`\t`、`\n`、`\r`、`\u00A0`、`\u3000`。
- 结果含标点（中文标点、英文标点都算 1 个字）。
- 显示：`n < 10000` → 「3,214 字」；`n >= 10000` → 「38.6 万字」（一位小数，四舍五入）。
- 聚合：章 → 卷（章和）→ 书（卷和）→ 书架（书和）；缓存值不符时以现场统计为准（§4.8）。

### 8.4 编码与换行

- 落盘：UTF-8 无 BOM，`\n`。
- 读入：容忍 BOM（读时剥掉）、CRLF 与 CR（统一转 `\n`），保证用户用记事本改过也能读。
- 不做：繁简转换、标点转换、自动校对、敏感词过滤。

### 8.5 字体

- 正文唯一字体：霞鹜文楷 GB（LXGW WenKai GB），Regular 一个字重。
- 界面文字：系统字体栈（`Segoe UI` / `-apple-system` / `Noto Sans`），不做中文等宽。
- 字体许可 OFL 原文随包：`assets/fonts/OFL-LXGWWenKai.txt`；设置页「许可」可见。
- 体积预期：字体文件 10–20 MB，安装包总量落在 45–60 MB，可接受（§11 R6）。

---

## 9. 五端适配清单

### 9.1 现状与目标

| 平台 | v1 状态 | 构建方式 | 主要在等什么 |
| --- | --- | --- | --- |
| Windows x64 | **交付物** | `flutter build windows --release`（x64 宿主自动出 x64） | — |
| Windows ARM64 | 代码就绪 | 同命令，但必须在 **ARM64 宿主**（含 VS ARM64 工具链）上构建 | 无 ARM 机器，只能代码层保证 |
| macOS ARM64 | 代码就绪 | `flutter build macos` | 签名/公证、退出语义、字体渲染实测 |
| Linux x64 | 代码就绪 | `flutter build linux` | GTK 依赖、IME（fcitx/ibus）、退出语义 |
| Android | 代码就绪 | `flutter build apk` | 本机 Android SDK 36 + 模拟器已就绪（§2），缺真机/模拟器实测；窗口概念缺失、退出即失焦保存、字体体积 |

### 9.2 各端必须差异化的点（全部收敛在 `core/platform`）

| 点 | Windows | macOS | Linux | Android |
| --- | --- | --- | --- | --- |
| 数据根 | `%APPDATA%\不白写作` | `~/Library/Application Support/不白写作` | `${XDG_DATA_HOME:-~/.local/share}/不白写作` | `getApplicationSupportDirectory()`（沙箱内） |
| 窗口最小尺寸/几何 | `window_manager` | 同左 | 同左 | 不适用（无自由窗口） |
| 退出拦截 | `onExitRequested` | 需实测（NSApplication terminate 是否走同一通道） | 需实测（GTK delete-event） | 无，`paused` 时 flush |
| 单实例 | 文件锁（`RandomAccessFile.lock`） | 同左 | 同左 | 不适用（系统单实例） |
| 打开文件夹 | `explorer` | `open` | `xdg-open` | 禁用 |
| 快捷键 | Ctrl 系 | Cmd 系（`LogicalKeyboardKey` 用 `HardwareKeyboard` 的 meta 判定） | Ctrl 系 | 无硬件键盘假设 |

### 9.3 跨端代码纪律（写进 code review 检查项）

1. 业务层与 `features/` **禁止** import `dart:io`、`window_manager`、`process`。
2. 路径拼接一律走 `core/platform/path_utils.dart`，不写死 `\` 或 `/`。
3. 文件编码、换行、BOM 处理只在 `core/storage`。
4. 任何"窗口"假设（最小尺寸、全屏、标题）必须经过 `PlatformServices`。
5. `pubspec.yaml` 的 `assets/fonts` 路径大小写敏感（Linux 区分大小写，Windows 不区分）——全部小写。
6. 条件编译只按 `Platform.isWindows/isMacOS/isLinux` 分，不出现 `dart:html`、`kIsWeb` 分支（v1 无 web 目标）。
7. 新增平台 = 实现 `PlatformServices` + 在 `main.dart` 选实现，不改 `state/` 与 `core/storage`。

### 9.4 平台就绪的定义（不是"能编译就算"）

某个平台可宣布"适配完成"，需要：能建书写作、能自动保存、能关窗落盘、能导出、数据目录符合该平台惯例、中文输入法可用。**v1 只对 Windows x64 做这个宣布**，其余平台写进 README 的"未验证"清单。

---

## 10. 里程碑、任务与验收

总估算：Gate 0 半天 + M1 2.5 天 + M2 2.5 天 + M3 1.5 天 ≈ **7 个工作日**，另留 2 天缓冲，合计约 9 个工作日。单人开发，直接提交 `main`，每个里程碑打 tag（`v0.1.0-m1`、`v0.1.0-m2`、`v0.1.0`）。

### 10.1 Gate 0（半天，通过才开工）

临时工程已在 `%TEMP%\_nww_gate0`（`flutter create --platforms=windows --project-name gate0 .`）；`lib/main.dart` 里放了 `FluentApp` + `NavigationView` + `TextBox` + 裸 `TextField` + `window_manager` 尺寸/标题 + `AppLifecycleListener(onExitRequested)` + `path_provider` 探针，并用一个 PowerShell 脚本自动点 `WM_CLOSE` 验退出分支。**2026-10-26：除需要人手敲键盘的两项外全部通过。**

- [x] `flutter --version` —— **已于 2026-10-25 由用户在真实 PowerShell 验证通过**（3.47.7 / Dart 3.13.5，完整输出见 §2）。
- [x] `flutter doctor -v` 全绿（VS 工具链无红叉）—— **已于 2026-10-25 验证：No issues found**（VS 生成工具 2026 18.10.3 + Windows 10 SDK 10.0.26100.0）。
- [x] `flutter pub add fluent_ui path_provider window_manager` 能拉到包 —— **2026-10-26 实测成功**：`fluent_ui 4.17.0`、`path_provider 2.1.6`、`window_manager 0.5.2`，共 `Changed 40 dependencies!`。
- [x] `FluentApp` + `NavigationView` + `TextBox` 示例页**通过静态分析** —— `flutter analyze` = `No issues found!`（先决条件：4.17 的 `AccentColor.swatch`、`PaneItem.body`、`dart:ui` 的 `AppExitResponse`，见 §5.4）。
- [x] release 构建 + 运行 —— **2026-10-26 实测**：junction 绕过后 `flutter build windows --release` 127 s 通过，产物双击可运行（§2.2）。
- [x] `setMinimumSize(Size(900, 600))` 生效、标题可变 —— **实测**：缩到 300×300 被钳到 900×600；`setTitle` 后进程主窗口标题为 `Gate0 不白写作`；但 `getTitle()` 中文乱码（R17）。
- [x] 点窗口 X 时 `onExitRequested` 被调用、`cancel` 能阻止退出 —— **实测两分支**：有文本 → 窗口存活（cancel）；无文本 → 进程退出（exit）。
- [x] `getApplicationSupportDirectory()` 实路径 —— **实测** `%APPDATA%\com.example\gate0`，`documents` = `C:\Users\userSigma\Documents`，可写（§2.2 结论 1）。
- [x] Inno Setup 6 `iscc` 可用 —— **6.7.3 已装（per-user，不在 PATH）**，最小脚本 5.5 s 编译出 2.1 MB 安装包。
- [x] 中文输入（微软拼音：连续输入长句 / 空格上屏 / 数字选词 / 回车上屏 / 候选窗不消失）无重复无丢字 —— **2026-10-26 作者手工验证「暂时未发现问题」**。
- [x] `controller.value.composing` 在组合期间确实为有效区间（作为 §7.4 的判定依据）—— **同上，作者在 Gate 0 窗口内实测通过**。
- [x] `TextField` 的 `Ctrl+Z` / `Ctrl+Y` 行为符合预期 —— **同上，实测通过；不再改自实现撤销栈**。
- [x] "换行差分 + 一次 value 赋值补缩进"在中文输入法下稳定（§8.1 方案）—— **M1 已实现并以单测 + 真机输入验证**（`applyEnterIndent`，作者手工打中文无异常）。

**通过** → 建正式工程，把实际版本号写入 `docs/env.md`。
**不通过** → 按 R2 回落：外壳不用 `fluent_ui`（改 Material 3 + 自定义 Fluent 观感样式），依赖降为 2 个，`state/`、`core/`、数据格式一律不动；若 Flutter 本身跑不起来，暂停并回报，不硬改环境。

### 10.2 M1：可写闭环（2.5 天）

> **2026-10-26：M1 实现与自动化验证完成**（代码在仓库，`flutter analyze` 干净，`flutter test` 28 个全绿，release 可运行）。
> 各项完成证据见括号内；唯一未做的是末尾的“人工走查”整条链路与 `v0.1.0-m1` tag，留待作者验收。

- [x] 工程骨架：`flutter create --platforms=windows` 正式目录、`pubspec`、lints、字体资产、目录与分层落地。
- [x] `core/platform`：接口 + Windows 实现 + mobile stub；数据根、单实例锁、窗口几何记忆、退出拦截。
- [x] `core/storage`：`atomic_file_writer`、`chapter_store`、`book_store`、`library_store`、恢复扫描、索引重建。
- [x] `state`：library/editor/settings 三个 controller + `AppContext` 装配（原计划的 book/autosave controller 合并进 library/editor，减少一层转发）。
- [x] 书架页：网格、卡片、排序、新建/重命名/删除书、空态、键盘导航（↑/↓ + Enter）。
- [x] 目录树：两级、新建卷/章、重命名、上移/下移、删除进 trash；折叠状态按书持久化（settings.expandedVolumes）。
- [x] 编辑器：裸 TextField、字体/字号/行距、状态条、切章 flush、字数；`Ctrl+S` 立即保存。
- [x] 自动保存：状态机（clean/dirty/saving/failed/blocked）、5 s 防抖、关窗 flush + 失败对话框（重试/导出后退出/取消）。
- [x] 崩溃恢复：`.tmp`/`.bak` 判定 + InfoBar 提示；恢复后只重算字数、不改卷章标题（`refreshWordCounts`）。
- [x] 单章导出。
- [x] 单测：`word_count`、`indent_rules`、原子写与恢复判定、导出合并、书架/编辑器流程、书卷章增删改，共 28 个。
- [ ] `v0.1.0-m1` tag —— **待作者验收后打**。

**M1 验收（人工走查）**：空目录启动 → 建《测试书》→ 建卷 → 建章 → 输入 2000 字中文 → 等 5 s → 关窗 → 重开，字数与内容一致；`taskkill /F` 强杀 → 重开，出现恢复提示且内容为最后 5 s 内；断开写入权限（改只读）→ 关窗被拦截并出现失败对话框。

> 2026-10-26 已用类似路径跑通：`.tmp` 恢复 + 提示、WM_CLOSE 保存后退出、单实例提示；
> 未覆盖的是“2000 字长文 + 只读目录失败对话框”这一段，验收时补。

### 10.3 M2：完整版（2.5 天）

- [ ] 查找替换：面板、高亮（含 composing 保护）、上/下一个、单项替换、本章全部替换 + 快照回滚。
- [ ] 全角/半角匹配开关。
- [ ] 专注模式 `F11` 与两级 `Esc`。
- [ ] 设置页全部项 + 立即备份按钮。
- [ ] 导出：整卷、整书（分隔行、文件名清洗、临时文件 + rename）。
- [ ] 整库 zip 备份（手动）+ 每日自动备份（保留 7 份、临时 zip 改名、失败静默记日志）。
- [ ] 主题打磨：亮/暗全量过一遍，卡片书脊 12 色，深色下正文对比度 ≥ 7:1。
- [ ] 图标与版本信息：`app_icon.ico`、`Runner.rc`（产品名「不白写作」、公司 `com.usersigma`、版本 0.1.0）、窗口标题动态格式。
- [ ] Inno Setup 脚本 `installer/no_white_writer.iss`：`PrivilegesRequired=lowest`、`DefaultDirName={localappdata}\Programs\不白写作`、`AppId=ce99ca45-fdcf-4d6f-8f1c-74f7dd3b086b`、卸载保留数据（勾选项「同时删除我的作品」）。
- [ ] `v0.1.0-m2` tag。

### 10.4 M3：收尾与发布（1.5 天）

- [ ] 多分辨率/多 DPI 回归（§10.6 矩阵）。
- [ ] 单章性能压测：2 万字（上限）输入延迟与内存；5 万字（超限）只记录不阻塞。
- [ ] 错误路径演练：磁盘满（用虚拟盘或配额工具模拟）、目录只读、进程占用文件、json 损坏、删 `.txt`。
- [ ] README：是什么、截图、数据目录说明、导出说明、构建命令、已知限制（未验证平台）。
- [ ] `CHANGELOG.md` 记 0.1.0。
- [ ] Release 打包：安装包 + `SHA256SUMS.txt`，附未签名说明。
- [ ] 打 tag `v0.1.0`。

### 10.5 测试策略

| 层 | 内容 | 工具 |
| --- | --- | --- |
| 单测 | 缩进规则（8 例）、字数口径（全角/emoji/空行）、原子写、恢复判定表（6 例）、自动保存状态机（假时钟 + 假存储）、导出分隔与文件名清洗、索引重建 | `flutter test` |
| Widget 测试 | 900 / 1280 / 1920 三档宽度下书架列数与无溢出；编辑器切章 flush | `flutter test`（无 golden） |
| 人工矩阵 | §10.6 | 手工 |
| 静态检查 | `flutter analyze` 零 warning | CI 不做，本地跑 |

不引入 mock 框架：状态机测试用注入的 `ChapterStore` 接口 + 注入的时钟函数（`Now = DateTime Function()`，测试里手动推进），不直接用任何传递依赖。

### 10.6 验收清单

**分辨率与缩放**
- [ ] 900×600（最小窗口）：书架 ≥3 列、目录抽屉、正文不溢出、按钮不重叠
- [ ] 1280×820（默认）：书架 ≥5 列、双栏正常
- [ ] 1920×1080 @125% 与 @150%
- [ ] 2560×1440 @150%
- [ ] 3840×2160 @200%：书架内容限宽 1600 居中，卡片不被拉扁
- [ ] 窗口拖到屏幕边缘/多显示器、拔掉外接屏后重启：几何不越界（记忆值越界则回到默认居中）

**写作与排版**
- [ ] 回车补两个全角空格；段中回车后半补；连续回车不叠空格；手动删缩进后不再补
- [ ] 段间空行开关生效
- [ ] 字数与手工统计一致（含标点、不含空白）
- [ ] 2 万字章节输入无明显卡顿（主观：连打 20 字无掉帧）

**输入法**
- [ ] 微软拼音：空格上屏、数字选词、回车上屏、长句连续输入、候选窗移动
- [ ] 搜狗拼音（若已装）：同上
- [ ] 组合中关窗：不丢字（500 ms 内等上屏）
- [ ] 重获焦点后继续输入不出重复字（针对 #190042）

**数据安全**
- [ ] 强杀进程 → 重启恢复最后 5 s 内容
- [ ] 关窗保存失败 → 被拦截 + 对话框 + 重试/导出两条路
- [ ] 把 `book.json` 改坏 → 重启自动重建
- [ ] 把某章 `.txt` 删掉但 `.bak` 在 → 提示恢复
- [ ] 只读目录 → 保存失败提示，不静默丢字

**导出与备份**
- [ ] 单章/整卷/整书导出的 txt 与编辑器内容逐字节一致（LF、无 BOM）
- [ ] 合并分隔行正确，卷章顺序正确
- [ ] 书名含 `:` `?` 等非法字符时导出文件名被清洗
- [ ] 整库 zip 能解压，含全部 txt 与 json
- [ ] 每日备份只保留 7 份，第 8 天删最旧

**安装与分发**
- [ ] 未签名安装包首次运行有 SmartScreen 提示（属预期）
- [ ] 安装到 `%LOCALAPPDATA%\Programs\不白写作`，不弹 UAC
- [ ] 卸载默认保留作品；勾选「同时删除我的作品」才清空
- [ ] 覆盖安装新版本（同 AppId）保留数据与设置
- [ ] 双击第二个实例 → 提示已在运行，不产生第二个窗口

---

## 11. 风险登记

| ID | 风险 | 触发信号 | 影响 | 缓解 / 兜底 |
| --- | --- | --- | --- | --- |
| R1 | 依赖拉取或解析失败（镜像/证书） | `pub add` 失败 / 证书错误 | 阻塞开工 | **2026-10-26 已实测通过**（40 个包，§2）；保留备用镜像 `pub.flutter-io.cn`、`tuna` 与 R14 版本处置 |
| R2 | `fluent_ui` 与 Flutter 3.47.7 不兼容，或与中文 IME 冲突 | `analyze`/编译失败；输入重复字 | 外壳方案变更 | **编译维度已排除**：`flutter analyze` = `No issues found!`（4.17.0）；IME 维度待开发者模式开启后 Gate 0 实测 |
| R3 | 回车补缩进与 IME 组合提交打架 | 输入中文后回车出现重复/跳光标 | 核心写作体验 | 不用 `TextInputFormatter`；只在变更后做一次 value 归一；Gate 0 专测；再不行退到 v1.1「保存前规整」 |
| R4 | 关窗拦截在 Windows 上不触发（`onExitRequested` 依赖引擎窗口 handler） | 点 X 直接退出，未 flush | 丢最后 5 s 内容 | Gate 0 验证；备选 `window_manager` 的 `setPreventClose` + `onWindowClose`；两者都不行则缩短 debounce 到 2 s 并明确告知 |
| R5 | 上游 IME bug（#190042 焦点、#191196 组合态泄漏） | 重获焦点后字重复、跨章串字 | 输入可靠性 | 每次切章重建 controller；切章前 `clearComposing`；记录复现步骤等上游修 |
| R6 | 霞鹜文楷 GB 体积大，安装包超预期 | 安装包 > 80 MB | 分发体验 | 接受；必要时换子集字体（保留 7000 常用字），列为 v1.1 |
| R7 | macOS/Linux/Android 无法本机验证 | 只能"代码就绪" | 承诺边界 | README 明确"仅 Windows x64 验证"；抽象接口 + 纪律清单；后续平台再补实测 |
| R8 | Windows ARM64 需要 ARM 宿主才能构建 | 无 ARM 机器 | 无法出 ARM 包 | 文档写明；代码不依赖架构假设（无内联汇编、无 x64 位宽假设） |
| R9 | 用户手改 AppData 内文件导致索引/正文不一致 | 启动报错或章节缺失 | 数据困惑 | 重建（§4.8）+ 日志 + 提示；外部删除的章标记而非静默消失 |
| R10 | 忽略系统文字缩放伤害无障碍 | 用户反馈字小 | 可用性 | 应用内字号 14–28 覆盖大多数需求；记录取舍；v1.1 可加"跟随系统字号"开关 |
| R11 | 崩溃后单实例锁残留 | 重启提示"已在运行" | 无法启动 | 锁文件写 pid；启动时用 `Process.killPid(pid, 0)` 探测存活，进程不存在则删锁 |
| R12 | 5 s 窗口内崩溃丢字 | 恢复提示"已恢复至 21:03:12" | 最多丢 5 s | 已知取舍；`Ctrl+S` 随时手动存；恢复提示给出精确时间 |
| R13 | 全文替换走程序化赋值，不进 `UndoHistory` | `Ctrl+Z` 撤不回替换 | 误操作 | 替换前快照全文，InfoBar 提供「撤销本次替换」（30 s）；不依赖 undo 栈 |
| R14 | 三个包互相约束冲突（`intl`/`collection` 版本） | `pub get` 解析失败 | 阻塞 | 已锁定 `fluent_ui 4.17.0` / `path_provider 2.1.6` / `window_manager 0.5.2` 与 `pubspec.lock`；升级单独提交；不使用 `dependency_overrides` 除非万不得已并记录原因 |
| **R15** | **Windows 开发者模式未开启** ⇒ 插件符号链接创建被拒（`ERROR_PRIVILEGE_NOT_HELD`），`build`/`run` 直接失败 | `Building with plugins requires symlink support.` | 构建与运行期验证 | **已绕开**：用 junction 预占 `.plugin_symlinks`（§2.2），release 构建 127 s 通过。**风险**：`flutter clean` / 插件列表强制刷新会删掉占位目录，需手工重建；长期仍建议开开发者模式（一次性） |
| **R16** | **Inno Setup 6 未安装** ⇒ 无法编译安装包 | `iscc` 不是命令 | M3 交付 | **已解决**：6.7.3 per-user 安装，`C:\Users\userSigma\AppData\Local\Programs\Inno Setup 6\ISCC.exe`；最小包编译通过。注意它**不在 PATH**，`.iss` 构建脚本须写全路径或在 Preflight 里加 PATH |
| **R17** | `window_manager.getTitle()` 对中文返回乱码（UTF-8 按 ANSI 解），若用标题做状态判断会误判 | `getTitle()` 得 `Gate0 涓嶇櫧鍐欎綔` | 小，但会让人误以为标题设置失败 | 标题**只写不读**；需要标题时用 `setTitle` 后不再回读；日志里不打印 `getTitle` 结果 |
| **R18** | 默认窗口 1280×820 在 1366×768 等小屏上超高，超出工作区 | 窗口底部按钮被任务栏遮住 | UI 可见性 | 启动时按工作区收敛：`min(1280, workAreaW×0.9) × min(820, workAreaH×0.9)`，且不低于 900×600；窗口几何记忆值越界时回默认居中（§10.6 已列） |

---

## 12. 开工前置检查（Preflight）

按顺序执行，全绿才进入开发（Gate 0 与 M1）：

**A. 机器前置条件（一次性）**

1. **Windows 开发者模式**（推荐但非必需）：`start ms-settings:developers` → 打开「开发人员模式」。**不开也能构建**（junction 占位，§2.2），但 `flutter clean` 后要重建、且每次新插件都要重建一次；开了就一劳永逸。
2. **Inno Setup 6**：✅ 已装 6.7.3（per-user，`C:\Users\userSigma\AppData\Local\Programs\Inno Setup 6\ISCC.exe`，不在 PATH，脚本写全路径）。
3. 保持 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 两个镜像变量（已配好，§2）。

**B. 工具链与临时工程**

```powershell
flutter --version                 # 期望 3.47.7 / Dart 3.13.5，10 秒内返回（已由用户于 2026-10-25 验证通过）
flutter doctor -v                 # 已由用户验证 No issues found（2026-10-25）；重跑用于确认环境未漂移
flutter config --no-analytics

# Gate 0 临时工程必须建在有 pubspec.yaml 的目录里；建在 %TEMP%，验证完整体删除
$gate = Join-Path $env:TEMP '_nww_gate0'
Remove-Item -Recurse -Force $gate -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $gate | Out-Null
Set-Location $gate
flutter create --platforms=windows --project-name gate0 .
flutter pub add fluent_ui path_provider window_manager
flutter analyze                   # 2026-10-26 已通过：No issues found!

# 若未开开发者模式：先给四个插件建 junction 占位（§2.2），再构建
flutter build windows --release   # 2026-10-26 已通过（127 s），产物可运行
```

> 2026-10-25 实际踩到：直接在 `C:\Users\userSigma` 跑 `flutter pub add` 会报 `Expected to find project root in current working directory.` —— 这是"当前目录没有 `pubspec.yaml`"，不是网络或镜像问题，不需要改环境。
>
> 2026-10-26 实际踩到：`flutter build windows` 报 `Building with plugins requires symlink support.` —— 开启 A.1，或按 §2.2 建 junction；项目与 SDK 已在同盘（C:），不是跨盘问题。

**C. 安装器**

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" /?   # 期望输出 Inno Setup 6 用法；不在 PATH
```

验证完成后删除 `%TEMP%\_nww_gate0` 整个目录（不落进仓库，无需 `.gitignore`），并把实际版本写入 `docs/env.md`。

**当前状态（2026-10-26 二测）**：`flutter --version`（2.9 s）、`flutter doctor -v`、`flutter create`、`pub add`（40 个包）、`flutter analyze`、`flutter build windows --release`、release 运行、窗口尺寸/最小尺寸/DPI、退出拦截两分支、`path_provider` 实路径、Inno Setup 编译 **全部通过**。剩余只有需要人手的两项：**中文 IME 输入**、**裸 `TextField` 的 Ctrl+Z / Ctrl+Y**（`flutter run` 已可跑，可用热重载观察）。

---

## 13. 待推翻的默认值与观察项

### 13.1 两处仍可推翻（不阻塞开工）

1. **字数口径**：现定"去空白后的字符数（含标点）"。若你要"只算汉字"或"算上游平台口径"，说一声即可改 `word_count.dart` 与全部展示。
2. **数据目录名**：现定 `%APPDATA%\不白写作`（中文名）。若你希望英文名（如 `no-white-writer`）以便跨工具处理，也可改。

### 13.2 观察项（记录在案，改动成本与影响面已标注）

| 项 | 现定 | 若要改，影响 |
| --- | --- | --- |
| 应用内字号不随系统 | 是 | 无障碍取舍（R10）；改成跟随需做字号叠加逻辑 |
| 无跨书搜索 | 是 | 需建索引与检索 UI，v1.1 |
| 无自动更新 | 是 | 手动下载安装包覆盖，靠同 AppId 升级 |
| 删除进 `trash\` 但无恢复界面 | 是 | 文件还在，需手动取回；v1.1 可做回收站 |
| 光标位置不跨进程保存 | 是 | 重启后回章首；改需在书索引入 offset |
| 默认字号 18 / 行距 1.9 | 是 | 改成 20 / 2.0 也合理，属口味 |
| 段间空行默认关 | 是 | 开启后回车多一空行 |
| 导出合并分隔行样式 | `──── 卷：… ────` | 可换成纯「第 X 卷 卷名」一行 |
| 整库备份只在设置页手动 + 每日自动 | 是 | 无"另存为"对话框，v1.1 可加 |

---

## 14. 本计划的维护规则

1. 任何决策变更，先在本文对应位置改，再改代码；改完在 §14.1 追加一行。
2. 实现与本文不一致视为 defect（除非同时在本文更新）。
3. 里程碑完成后回写勾选项与实测数据（体积、耗时、字数）。
4. 本文不记录"代码怎么写"的细节（函数体、widget 树），只记录"必须是什么行为"。
5. 若 Gate 0 触发 R2 回落，本文 §3 Q17、§5.4、§10.1 需同步改写，并在变更记录里说明原因。

### 14.1 变更记录

| 日期 | 版本 | 变更 | 决策来源 |
| --- | --- | --- | --- |
| 2026-10-25 | 0.1-plan | 初版：Q1–Q29 全部落定，定稿本计划；未开工程 | 4 轮 grilling 追问 |
| 2026-10-25 | 0.1.1-plan | 用户在真实 PowerShell 验证 `flutter --version` / `dart --version`（3.47.7 / 3.13.5，engine revision `deb287481e`），回写 §2 表格与结论、Gate 0 首项打勾、§12 注释、§11 R1；另含 §3.3 边界修正（抽屉断点 `<1000`、压测改 2 万/5 万字） | 用户手测输出 |
| 2026-10-25 | 0.1.2-plan | 用户跑 `flutter doctor -v` = **No issues found**（VS 18.10.3 + Win10 SDK 10.0.26100.0、Android SDK 36、镜像 Network resources 全绿），回写 §2 环境表与结论、Gate 0 第二项打勾、§11 R1 降级为"依赖拉取/解析风险"、§12 注释、§9 Android 行 | 用户手测输出 |
| 2026-10-25 | 0.1.3-plan | Gate 0 临时工程改到 `%TEMP%\_nww_gate0`（原先写在仓库内 `_gate0`）；补记录"在非项目目录跑 `flutter pub add` 报 Expected to find project root"的排查结论 | 用户实测报错 |
| 2026-10-26 | 0.1.4-plan | 沙箱内完整复测：`flutter --version`/`create`/`pub add`（fluent_ui 4.17.0、path_provider 2.1.6、window_manager 0.5.2，40 包）/`analyze`（No issues found）/`test` 全通过；发现**开发者模式未开启**导致 `build/run` 被符号链接拦截（新增 R15），**Inno Setup 未安装**（新增 R16）；同步 §2 表与结论、§2.1（AppExitResponse 在 `dart:ui`、symlink 源码位置）、§5.4（实测版本 + fluent_ui 4.17 API 差异）、§10.1（4 项打勾）、§12（机器前置条件 A/B/C 分组） | 本会话实测 |
| 2026-10-26 | 0.1.5-plan | **Gate 0 二测全部实证**：Inno Setup 6.7.3 安装并编译出 2.1 MB 安装包；用 junction 绕过开发者模式后 `flutter build windows --release` 127 s 通过、产物可运行；实测窗口逻辑/物理尺寸与 125% DPI、`setMinimumSize` 生效、`onExitRequested` 两分支（有文本 cancel / 无文本 exit）、`path_provider` 实路径、`getTitle()` 中文乱码；新增 §2.2（实证表 + 绕过办法 + 4 条实现结论）、R17（getTitle 乱码）、R18（小屏窗口超界）；更新 §2 表/结论、§10.1（8 项打勾）、§12（开发者模式改为可选、iscc 全路径、`run` 重新可用） | 本会话实测 |
| 2026-10-26 | 0.2-plan | **Gate 0 关闭**：作者手工验证中文 IME 与 Ctrl+Z/Ctrl+Y「未发现问题」；两处默认值（字数口径、数据目录名）按推荐采纳并写入 §3.2；状态改「作者已确认，M1 开发中」；`flutter create` 正式工程落地，进入 M1 | 作者 m00689「暂时未发现问题，可以开始」 |
| 2026-10-26 | 0.2.1-plan | **M1 代码全部落地**：`core/`（ids、platform、storage、text、logging、models）、`state/`（settings、library、editor）、`ui/`（shelf、catalog、editor、settings、theme、format）、`app.dart`、`main.dart`、字体资产、`tool/fix_plugin_symlinks.ps1`；实现时修正了原计划的分层（book/autosave controller 并入 library/editor）、新增 `screen_retriever` 与 `material_ui` 两个直接依赖（原因见 §5.4）、新增 `NWW_DATA_ROOT` / `NWW_DEV_PAGE` / `NWW_DEV_TYPE` 验收钩子 | 实现过程 |
| 2026-10-26 | 0.2.2-plan | **M1 自动化验证通过**：`flutter analyze` = No issues found；`flutter test` = 28 个全绿（单词数 2、缩进 8、存储/恢复/导出 8、书架编辑器流程 4、书卷章流程 4…合计 28）；release 构建 64～137 s，产物 `no_white_writer.exe` 可运行 | 本会话实测 |
| 2026-10-26 | 0.2.3-plan | **M1 真机验收补齐**：窗口逻辑 1280×820（125% 下物理 1600×1025）；书架/目录/编辑器/设置四页截图确认；浅色/深色主题；5 s 自动保存、`WM_CLOSE` 退出保存、`.tmp` 崩溃恢复（标题不被改写）、单实例提示；修了 4 个实机才暴露的问题（`_screenSize` 用错成自身窗口 → screen_retriever 工作区、`EditorController.open` 覆盖用户输入、`_write` 成功后未取消 debounce、恢复后字数 stale）；新增 `docs/env.md` 与 README | 验收过程 |
| 2026-10-26 | 0.3-ui-design | 新增 §15：卡片固定宽度、不再独立进入卷章管理页、目录操作迁入写作侧栏、正文上方新增可直接编辑且自动保存的标题栏、新建作品增加名称/备注；补充保存失败、删除当前章、空目录、旧数据兼容及发布验收边界；本轮未开始实现 | 作者 m02676 的四项 UI 要求；m02721 选择标题栏方案 A |

---

## 15. 本轮 UI 修订规格（2026-10-26，作者已确认）

### 15.1 范围与方案选择

- 依据：作者反馈窗口缩放时卡片尺寸跳变，并要求取消独立卷章管理页、把功能合并到写作侧栏、正文新增标题栏、新建作品改为名称和备注两栏。
- 已确认：标题栏采用方案 A，直接编辑章节名称并自动保存、同步侧栏。未采用方案 B（仅展示标题、弹窗改名），因为它增加改名步骤，不符合直接写作的方向。
- 卡片采用固定宽度布局；不采用「只限定最大宽度、再均分剩余空间」的布局，因为后者在列数变化时仍会改变卡片尺寸。
- 保留现有配色、字体、纯文本正文、5 秒自动保存、原子写、备份与单章导出；不加入搜索、拖拽排序、整书导出等 M2 功能。不使用子智能体。
- 作者 m02788 已确认本节并授权实施。本轮以本节覆盖 §6.1–§6.3 中关于卡片伸缩、独立目录页、旧标题入口和单字段新建弹窗的冲突条目；其余既有行为保留。历史实测记录不能当成本轮验收结果。

### 15.2 书架卡片稳定布局

- 每张卡片固定为 **220×300 逻辑像素**，包含封面与下方信息；横向间距 20、纵向间距 26。保持现有书架边距和视觉风格。
- 改变窗口宽度时只重排列数，卡片不被剩余空间拉伸；一行不足整列的空间留在右侧。仍允许纵向滚动，不出现横向滚动条。
- 系统 DPI 改变的是物理像素与逻辑像素的对应关系，不改变以上逻辑尺寸。保留应用内字号自控规则。
- 面向未来的极窄窗口，只有当可用内容宽不足 220 时才按可用宽收敛为一列；当前 Windows 最小 900×600 不会触发该例外。
- 超长书名截断，不撑宽卡片。保留悬停与选中反馈，但窗口缩放不能触发卡片宽高动画。

### 15.3 书架直接进入写作工作区

- 点击书籍后直接进入「左侧卷章管理 + 右侧写作」工作区，不再经过独立卷章管理页；返回按钮回书架。
- 优先打开该作品上次选中的有效章节；记录不存在或章节已删除时打开排序后的第一章。新建作品仍自动建立第一卷及第 1 章，并直接进入该章。
- 打开或新建后使用实际目标作品，不依赖书架排序后的第一项，避免按书名排序时打开错书。
- 没有章节时进入空白工作区，显示新建卷/章入口，禁用正文和标题输入；不擅自生成新章节。
- 侧栏头部提供作品名称、卷章/字数统计、「作品信息」（修改名称、查看/修改备注）和新建卷入口；卷行与章行提供新建、重命名、上移、下移、删除等原有目录功能。首尾项不可越界移动，删除需要二次确认，正文仍移入 trash。
- 保留响应式断点：宽度 ≥1280 时侧栏 280；1000≤宽度<1280 时侧栏 240；<1000 时由工具栏目录按钮打开侧栏面板，功能与宽屏侧栏一致，而不是只有章节选择列表。当前章保持高亮；卷的展开状态在本次运行中按作品记忆，上次选中章持久化。

### 15.4 独立、可编辑的章节标题栏

- 全局工具栏保留返回书架、目录入口、保存状态、正文统计、导出本章、设置；章节标题移到正文区域顶部的一行独立标题输入栏。
- 标题栏与正文共享水平对齐和最大内容宽度 760；位于正文滚动区域之外，滚动正文时仍可见。标题单行显示，长标题在输入框内水平滚动，不撑破布局。
- 输入修改直接作用于章节名称草稿并同步侧栏；中文 IME 组合期间不做截断、修剪或光标重置。标题不从正文首行推断，也不被写成正文第一行。
- 标题与正文共用脏状态及保存入口：停止输入 5 秒自动保存，失焦、Ctrl+S、切章、返回书架、关窗强制保存。只有标题和正文均成功落盘才显示「已保存」。
- 合法标题提交时修剪首尾空白；编辑时可暂时清空，但提交时若仍全为空白则恢复最近一次成功保存的章节名（新建章为创建时的名称）并提示，正文保存不受影响。
- 切换章节时同时切换标题及正文，旧章的异步读取或保存结果不能覆盖新章输入；切换过程中不把旧标题写进新章。
- 保存失败保留标题/正文草稿并显示失败；切章、离开和关窗沿用重试、取消等保护流程，不把失败当成功。关窗对标题与正文的 IME 组合态都适用既有等待规则。
- 章节名称仍只保存在书级索引；正文 txt 的内容和导出正文格式不改变，标题不计入正文字数。导出文件名使用已确认的章节名称。

### 15.5 新建作品弹窗与备注数据

- 弹窗采用内容包裹高度，正常宽度约 480、受窗口边界限制；不得让输入框把弹窗拉满窗口。字段与按钮有明确间距，小窗口必要时让弹窗内容滚动。
- 「名称」：带标签的单行输入框，最多 **50 个用户可见字符**，显示字数提示；限制覆盖键盘输入与粘贴，不能截断 emoji 等组合字符，不能在中文 IME 组合途中破坏输入。空白名称保留原有「未命名作品」默认值。
- 「备注」：带标签的多行输入框，固定可视三行，允许换行、可留空；超过三行后在输入框内部竖向滚动，不继续撑高弹窗。不额外添加备注总字数限制。
- 名称框回车移动到备注，不直接创建；备注内回车换行。创建由「创建」按钮触发，取消不写盘。提交期间防止重复创建，失败保留输入并提示。
- 备注作为作品元数据存入书级索引，与名称一并在创建成功后持久化；通过侧栏「作品信息」查看和修改，不混入任何章节正文或正文字数。
- 兼容现有作品：旧数据缺少备注时读取为空字符串；不重建作品、不改 ID、不改正文、不自动裁切旧作品已有的超长名称。新增可选字段不要求整库迁移。

### 15.6 模块边界与保存安全

- 书架负责固定尺寸布局和进入目标作品；工作区负责章节选择与正文布局；共享的卷章管理面板负责目录操作，窄屏复用同一套能力。
- 新建/作品信息表单负责收集与验证名称、备注；作品模型和存储层负责向后兼容读取与持久化，不将字段散放到全局设置中。
- 编辑状态层统一管理标题/正文快照、脏状态、IME 组合态及退出 flush；同一本书的索引写入必须串行化，避免标题自动保存与侧栏操作竞争同一个临时文件。
- 新建、排序、重命名等目录操作不能覆盖未落盘的正文或标题。涉及当前章的切换或删除前先完成联合保存；失败时留在当前章。
- 删除当前章节或其所在卷后，按目录顺序优先选下一章，无下一章则选上一章，无剩余章节则进入空态；删除其他章不改变当前选择。
- 删除前等待在途保存结束，删除后解除当前章的保存绑定并取消旧定时任务，再进入新章或空态；卸载页面不得将已删除章节重新写回。
- 重复点击或重叠异步导航须串行/去重，不能把草稿保存到错误的章节。作品信息保存失败不显示成功，也不静默丢弃用户输入。

### 15.7 验证与交付标准

1. 卡片：连续改变窗口宽度，并覆盖增减列数的临界点；可用宽≥220 时所有卡片始终 220×300，无宽高跳变、横向滚动或布局异常；覆盖多本书、长书名和不同 DPI。
2. 导航：点书及新建作品均直接进入正确工作区；按书名排序也不打开错书；验证上次章节、失效选择、无卷无章；确认原独立目录页无导航入口。
3. 侧栏：宽屏与窄屏均可新建卷/章、改名、排序、删除；覆盖删除当前章、当前卷、末章后空态，不产生被删除正文重新出现的问题。
4. 标题：仅改标题、仅改正文、同时改动均能自动保存；Ctrl+S、失焦、切章、返回、关窗后重开一致；失败时保留草稿。覆盖快速切章、中文组合态与空白标题规则；正文字数及 txt 不包含标题。
5. 表单：名称 49/50/51 个用户可见字符、长文本粘贴、中文组合态及组合 emoji 边界；备注超过三行仍固定三行高度并能滚动；名称回车不创建、备注回车不提交；取消无作品、重复点击只建一本。
6. 数据：旧作品无备注可正常打开，新增备注重启后仍存在、可再编辑；既有正文、卷章顺序、作品 ID 和旧名称不被迁移破坏。
7. 自动化：先加入能复现旧行为/缺失功能的测试，确认失败原因；再实现并运行完整测试与 analyze，不沿用首版 28 绿作为本轮证据。
8. 交付：构建 Windows x64 release，打包完整目录为新 ZIP；解压到旧低完整性构建目录以外验证普通启动，不降低作品目录权限。验收优先用隔离数据，不强行结束作者正在使用的实例，不覆盖已有发布包或作品。

---

## 16. UI 修订 Implementation Plan

> **For agentic workers:** 按 executing-plans 在本会话逐项执行；作者禁止使用子智能体。本节代替默认独立计划文件，所有步骤使用复选框跟踪。

**Goal:** 完成 §15 四项 UI 改动并交付可运行的 Windows x64 完整发布包。

**Architecture:** 沿用 ChangeNotifier、现有文件存储与 Fluent UI，不引入状态管理或路由框架。标题/正文由 EditorController 联合保存；WorkspaceController 串行协调切章与目录操作；同一文件的原子写入由 AtomicFileWriter 排队。卷章面板和作品表单分别提取为可复用组件。

**Tech Stack:** Flutter 3.47.7、Dart 3.13.5、fluent_ui 4.17、material_ui TextField、flutter_test、Windows x64。

### 16.1 文件责任与执行约束

- 修改 `lib/core/models.dart`：BookIndex 增加 `String notes = ''`，JSON 缺字段默认空串。
- 修改 `lib/core/storage/atomic_file_writer.dart`：按目标绝对路径串行化字符串/字节原子写；失败不能毒化队列。
- 修改 `lib/state/library_controller.dart`：创建支持备注、持久化最近章节、修改作品信息并同步摘要。
- 修改 `lib/state/editor_controller.dart`：标题控制器、联合脏状态/快照、可等待的打开/解除绑定、保存失败保护、dispose 清理。
- 新建 `lib/state/workspace_controller.dart`：选章、目录变更前 flush、删除当前目标的解绑/相邻章选择、重复操作保护。
- 新建 `lib/ui/book_details_dialog.dart`：名称/备注表单、异步提交错误展示与草稿保留。
- 新建 `lib/ui/chapter_pane.dart`：宽/窄屏共用的卷章管理组件，UI 不直接并发写盘。
- 修改 `lib/ui/shelf_page.dart`：固定网格槽、直接进入 EditorPage、使用创建返回值打开作品。
- 修改 `lib/ui/editor_page.dart`：统一写作工作区、空态、独立标题栏、快捷键/失焦保存；不再使用 dispose 强写旧章。
- 修改 `lib/main.dart`：旧 catalog 验收入口改为新工作区，不再引入独立目录页；保留默认书架与其他验收钩子。
- 修改 `test/m1_flow_test.dart`；新增 `test/support/app_harness.dart`、`test/ui_revision_test.dart`、`test/editor_save_test.dart`、`test/workspace_test.dart`，覆盖真实临时目录 IO。单元测试可直接 await；widget 测试的真实 IO 必须使用 tester.runAsync。
- 分支 `ui/writing-workspace`，不在 main 开发；所有实现与验证在当前工作区内完成。原 M1 源码尚未跟踪，不能把它们冒充本轮新实现；收尾 diff 需区分旧基线与本轮改动。

### 16.2 Task 1：备注与索引写入基础

- [x] 在 `test/editor_save_test.dart` 写模型测试：

```dart
final old = BookIndex.fromJson({'id': 'old', 'title': '旧作品'});
expect(old.toJson()['notes'], '');
final roundTrip = BookIndex.fromJson({'id': 'new', 'title': '新作品', 'notes': '第一行\n第二行'});
expect(roundTrip.toJson()['notes'], '第一行\n第二行');
```

- [x] 运行 `flutter test test/editor_save_test.dart --reporter expanded`；先确认旧模型忽略备注导致断言失败，而非环境或语法错误。
- [x] 在 BookIndex 构造/字段/JSON 增加 `this.notes = ''`、`String notes`、`'notes': notes`、`notes: json['notes'] as String? ?? ''`；为 createBook 添加 `{String notes = ''}` 并传给 BookIndex。
- [x] 添加并发字符串/字节写同一文件测试，旧实现应出现临时文件竞争；随后在 AtomicFileWriter 中以绝对路径维护 future 尾链，所有实际写入在前序结束后执行，并从尾链吞掉已交给调用方处理的错误。
- [x] 再运行目标测试，期望全部 PASS；追加失败后下一次写入仍可成功的回归用例。

### 16.3 Task 2：标题与正文联合保存

- [x] 在 `test/editor_save_test.dart` 基于真实临时作品依次加入标题独立保存、标题+正文、仅正文、空白标题还原、失败保留草稿、输入中快照更新、IME 组合态跳过/关窗强制保存、切章隔离、close 后不可复活测试。核心断言：

```dart
editor.title.text = '新章节名';
editor.text.text = '正文';
expect(editor.isDirty, isTrue);
expect(await editor.flush(), isTrue);
final saved = await app.bookStore.load(summary);
expect(saved.allChapters.first.title, '新章节名');
expect(await app.chapterStore.readText(book.id, volume.id, chapter.id), '正文');
```

- [x] 运行该测试，确认缺少标题编辑行为使其 RED；实现 `TextEditingController get title`、保存基线 `_savedTitle` 与 `_savedText`、联合快照以及 `Future<bool> close()`。
- [x] open 时保护异步读取 token，并在读取结束前禁止自动写旧输入；flush 等待在途保存，再保存最新草稿。标题空白恢复成功保存过的名称并给出 notice；错误保留两份草稿。
- [x] 同一次保存先写必要的正文，再写索引；只有双方成功后更新保存基线。标题输入草稿不直接修改共享 ChapterMeta，侧栏通过标题控制器展示当前章草稿，避免保存旧快照时回退正在输入的显示。
- [x] 运行该测试并确认 GREEN；既有正文 txt 内容、字数、导出格式保持不变。

### 16.4 Task 3：统一工作区状态与安全目录操作

- [x] 在 `test/workspace_test.dart` 加入上次章恢复、失效章回退、无章空态、操作前 flush 失败停止、删除当前章选后章/前章、删当前卷、末章后空态、重复操作拒绝及删除后不复活测试。
- [x] 运行 `flutter test test/workspace_test.dart --reporter expanded` 并确认 RED；实现 WorkspaceController 的 `initialize()`、`select(Volume, ChapterMeta)`、`change(Future<void> Function(), {Set<String> deletingIds})` 和 `close()`。
- [x] change 必须先联合 flush，当前章在删除集合中时等待在途保存并解除绑定，再执行删除；以原目录顺序寻找仍存活的后章/前章，无章保持空态。busy 期间禁止重入，失败显示 error，不显示成功。
- [x] LibraryController 新增最近章读取/记忆接口并落入现有 BookSummary.lastOpenedChapterId；作品信息保存失败还原内存名称/备注，表单仍保留待重试的草稿。
- [x] 运行目标测试直至 GREEN；再运行 `flutter test test/library_flow_test.dart`，确认原 CRUD 保持通过。

### 16.5 Task 4：作品表单与稳定书架

- [x] 在 `test/ui_revision_test.dart` 加入书架 900/1000/1015/1016/1280/1600 宽度卡片尺寸断言、直接进入 EditorPage、按书名排序新建仍打开目标作品；加入名称上限、emoji、组合态、备注三行与回车焦点测试。
- [x] 运行 `flutter test test/ui_revision_test.dart --reporter expanded` 确认 RED。
- [x] 表单采用有状态 ContentDialog：`SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: fields)))`。名称 `maxLines: 1`、`maxLength: 50`，使用 Flutter 的字符簇计数与组合态安全限制；备注 `minLines: 3, maxLines: 3`；名称回车 focus 到备注。异步 onSave 成功才 pop；失败留在原表单显示错误，保存期间禁用提交。
- [x] 书架网格列数采用 `max(1, ((usableWidth + 20) / 240).floor())`，使用固定 crossAxisExtent 的 SliverGridDelegate，使每卡片宽 220、间距 20、高 300，余宽不重新均分。它代替外层动态收窄方案，避免 Flutter 根据 slot 再次拉伸卡片；保留纵向滚动和原卡片视觉。
- [x] ShelfPage 的打开目标为 `EditorPage(app: app, book: book)`；创建的返回 BookSummary 直接传入打开流程，不再使用 library.books.first；添加导航重入保护与打开失败提示。
- [x] 运行目标测试确认 GREEN。

### 16.6 Task 5：卷章面板、标题栏和响应式工作区

- [x] 在 `test/ui_revision_test.dart` 加入宽/窄屏目录增改排删入口、独立标题输入与正文输入、无章时禁用输入、删除确认与当前章高亮测试。
- [x] 运行目标测试确认 RED；实现共享 ChapterPane，卷/章行提供菜单，操作均经 WorkspaceController.change，当前章改名经 editor.title/flush，不绕开联合保存。
- [x] EditorPage 接收可空 volume/chapter（兼容既有测试调用），默认用 workspace.initialize 选择上次章；全局工具栏与标题栏分离。标题和正文放在同一 maxWidth 760 的对齐区域，标题单行固定在正文滚动区之外。
- [x] 宽≥1000 时内嵌 ChapterPane，<1000 时目录按钮打开包含同一面板的浮层；浮层管理后刷新，选择章节可关闭浮层。正文与标题 readOnly 跟随 workspace.busy/无章，Ctrl+S 与失焦保存覆盖两者。
- [x] 返回先 workspace.close 成功再 pop；PopScope 保护系统返回。dispose 不再强制保存一个可能已删除的旧章节。旧 catalog 页面不再有导航入口，main 验收钩子也进入新工作区。
- [x] 在 `test/m1_flow_test.dart` 将正文查找改为 `find.byKey(const ValueKey('chapter-body'))`，标题使用 `ValueKey('chapter-title')`，避免 TextField 数量变化造成歧义；执行所有测试确认 GREEN。

### 16.7 Task 6：全量验证与发布

- [x] 执行 `dart format lib test`、`flutter analyze`、`flutter test --reporter expanded`，分别保存输出；期望 analyze 无问题、全部测试 PASS。
- [x] 执行 `flutter build windows --release`；若插件 junction 缺失，按既有 `tool/fix_plugin_symlinks.ps1` 修复后再构建，不清理用户数据或修改系统 ACL。
- [x] 生成不覆盖旧文件的新完整 ZIP（应用版本提升到 0.2.0+2），包含 release 目录所有 DLL/data/运行库；计算 SHA256。
- [x] 在工作区外新建本轮专用解压目录，以 NWW_DATA_ROOT 指向隔离验收目录启动，不触碰作者作品；核对进程、标题、可见窗口与截图。仅关闭本轮启动的测试进程，验证关闭后标题/正文/备注仍在。
- [x] 回读最终改动并检查保存/切章/删除所有路径；对发现的问题先加回归测试再修复。更新 PLAN/README/环境验证记录，明确未能人工确认的 IME 或 DPI 项目。
- [x] 核对本轮有意变更并区别原未跟踪 M1 基线；提供新包路径、测试/构建结果和仍需人工体验的项目。当前保留在开发分支，未将大量旧 M1 源码混作本轮新提交，未合并或推送。

### 16.8 本轮完成记录与验收边界（2026-10-26）

- 四项规格已实现。书架通过固定 extent 的网格委托保持 220×300；卷章增改排删与作品信息归入共用侧栏/窄屏浮层；章节标题和正文共享保存门禁；新建名称单行 50 字、备注固定三行内滚动。
- 新增行为均先观察对应 RED 再实现：旧模型丢备注、同路径临时文件竞争、缺标题控制器、工作区无行为、卡片宽度变化、缺表单/直接入口、失败摘要未回滚、旧长名被裁切、展开记忆与统计缺失。编译错误、错误等待条件和挂起测试不计为有效 RED 或 GREEN。
- 最终 `dart format lib test` 无新增变化；`flutter analyze` 无问题；**56 项自动测试全部通过**（包含原 28 项回归）。宽/窄屏 CRUD、保存失败重试、在途快照、IME 组合态、删除后不复活、字符簇与 Ctrl+A 均有回归覆盖。
- Windows x64 release 构建成功（72.5 s），版本 `0.2.0+2`。完整发布包：[no-white-writer-0.2.0-windows-x64.zip](build/packages/no-white-writer-0.2.0-windows-x64.zip)，25,408,174 字节；SHA-256：`4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`。
- 外目录解压的 21 个文件逐一 hash 比对一致；125% 实机检查 1280×820 与 900×600 窗口、卡片列数变化、共用目录浮层与表单。隔离旧格式书中实际输入标题/正文，关窗并重开后仍在；旧书新增备注经原生表单保存、重启回显一致。旧发布包、作者作品和其他实例均未覆盖或强行终止。
- 初始源码快照在副本中格式化后对照，生产逻辑差异为 10 个有意文件，其他 Dart 差异仅格式化；原 M1 大量未跟踪源码不等于本轮全部新增。独立目录旧源码仍保留用于回归断言，但已无导航入口。
- 边界：此轮新包使用隔离数据根，默认 AppData 普通启动的既有证据仍属于 0.1.0 历史；未把它冒充 0.2.0 的新验证。中文候选窗、连续输入/撤销重做、多屏及其他 DPI 仍需作者体验；其他平台尚未编译。M2 与启动异常 UI 提示不在本轮范围。
- 详细事实见 [环境记录 §7](docs/env.md#7-020-ui-修订验证2026-10-26)。整体状态是「已实现并验证、待作者体验验收」，不是替作者确认最终验收。

---

## 17. 黑白界面、目录交互与卷级编号规格（2026-10-26，设计已确认）

### 17.1 依据、范围与决策

- 作者初始要求：界面与按钮纯白/纯黑；新建章节使用「+」直接创建；作品信息移到书架卡片右键菜单；侧栏手动折叠；卷卡片内联重命名；卷设置控制可编辑的自动章节号；右键「移动」后用握柄拖动卷/章。2026-10-27 09:13 作者将主题修订为「恢复 0.2 样式，仅背景纯白/纯黑」，以 §17.2 与 §18.9 为准，其余功能继续。
- 已确认：自动编号是独立显示前缀，随卷内排序更新，不改章节名称与正文；整个侧栏和卷卡片均手动折叠；允许同书跨卷移动章节，采用目标卷规则。作者随后确认整套设计。
- 方案选择：沿用现有文件存储与 Flutter/Fluent UI，在标题之外计算显示编号、提取安全的目录移动能力。不采用把编号批量写进章节名的方案，因为开关、改规则和重排会破坏作者原名；不为此引入数据库、第三方树控件或任意脚本表达式。
- 本节优先于 §1.2、Q8、§4、§6、§8 和 §15 中关于「暂不拖拽」、默认编号属于章名、彩色书脊、作品信息入口、上移/下移及自动展开的冲突条目。前文保留为历史，不表示两套行为并存；其他 M2 功能不因此纳入本轮。
- 保留固定 220×300 书架卡片、应用内字号、自有字体、5 秒联合自动保存、原子写/备份、单章导出、删除确认与回收站。仍不使用子智能体；仍只构建 Windows x64，保持其他平台的代码适配边界。
- 当前阶段只完成设计和本文规格，产品代码未按本节修改；§16.8 的 56 测试、0.2.0 构建及 ZIP 仅是上一轮历史证据。

### 17.2 主题与状态表达（2026-10-27 09:13 作者修订）

- 作者要求继续实施其余功能，但主题恢复为 0.2 版本样式，只将背景改为纯白/纯黑。本修订覆盖原「全部界面、按钮与状态仅用黑白」的要求，不再执行全控件黑白化。
- 保留「跟随系统 / 浅色 / 深色」。应用内容底色以 `AppColors.paper = #FFFFFF`、`AppColors.ink = #000000` 替换 0.2 的暖白/墨黑；书架、写作区、侧栏和设置内容背景使用这两个底色。控件自身的填充层次、弹窗、蒙层等沿用 0.2 / Fluent 默认样式，而不是强制所有控件背景取纯黑白。
- 除上述底色外，恢复 0.2 token：文字 `#2B2A27 / #EDE8DF`，朱砂 `#A6402B`、柔朱砂 `#C9795F`，细线 `#E3DACB / #2B2D31`，次要文字 `#7A7267 / #9A948A`。保留原有字号、字体、间距与书籍形状。
- 恢复 0.2 的彩色书脊渐变（依 coverSeed 稳定生成）、按钮与悬停/禁用/焦点样式、选中/输入选区、保存状态颜色和通知/弹窗效果；不继续强制黑白反色、零阴影、透明屏障或自定义选字反色。文字错误/成功提示及禁用交互语义保持有效。
- 本轮新增的右键菜单、编号设置和握柄沿用 0.2 的 token 与 Fluent 视觉语义，功能、键盘可达性和数据安全不回退。恢复样式只从本轮当前源码快照抽取对应视觉实现，禁止拿更早 M1 快照覆盖当前功能。
- 操作系统标题栏、输入法候选窗、原生文件对话框仍不改色；人工 IME / DPI / 其他平台验证边界仍须记录。

### 17.3 书架卡片菜单与作品信息

- 卡片右键在指针附近打开真正的上下文菜单，不使用居中的「操作」模态框。至少提供「打开」「编辑信息」「删除」，并提供键盘菜单入口；触屏平台代码保留长按等可达方式，不要求本轮构建。
- 「编辑信息」在书架使用现有名称/备注表单：名称单行 50 个用户可见字符、备注固定三行内滚动、旧超长名称在未改名时不裁切、失败保留草稿与防重复提交规则不变。
- 编辑信息不进入正文工作区；成功同步对应卡片与排序，不因书架按名称排序而改错对象。操作始终按稳定 book ID 定位，不按当前列表下标定位。
- 「删除」保留二次确认与移入 trash；取消无修改。文件移动或索引写入失败时不能提示成功或静默丢失卡片；重试不得把其他作品当目标。
- 写作侧栏移除「作品信息」按钮与编辑入口；保留书名、卷章/字数统计及新建卷入口。书架编辑作品时不得复用仍指向上一部作品的 editor 绑定误写数据。

### 17.4 直接新建章节与紧凑命名

- 卷内容区的「新建章」文字按钮替换为「+」图标按钮，具有「新建章节」提示和无障碍名称；菜单中的「在本卷新建章」复用同一直接创建行为。
- 点击后先联合保存当前草稿，成功才在目标卷末尾创建空正文和索引，不弹出章名输入框。保存失败停止创建并保留当前草稿；等待期间禁用重复操作，一次点击只产生一个章节。
- 新章节原始名称默认为「未命名章节」，与是否启用自动编号无关。创建成功后打开该章，在写作区可交互时聚焦标题并选中默认名称，便于立即改名；窄屏目录浮层仍由用户关闭，关闭后再把焦点交给标题，不抢占浮层内焦点。标题与正文仍统一保存。
- 新建作品附带的首章采用相同默认名，不再把「第 1 章」写入新章名。已有作品/章名原样保留，重复的未命名名称由不可变 ID 区分，导出沿用不覆盖同名文件的规则。
- 卷名不使用自动章节号规则。新建作品的初始卷、未指定名称的新卷使用「未命名卷」；显式输入的卷名照常保存，已有「第一卷」「第 N 卷」不自动改写。
- 新建卷及仍保留的章节重命名表单使用紧凑单行高度、内容包裹布局及窗口边界约束，不再出现截图中输入区撑满窗口的情况。删除确认和卷设置不是本轮取消的对话框。

### 17.5 卷卡片内联重命名

- 卷菜单「重命名」将卡片标题切换为单行输入框，选中旧名，不弹出命名对话框；同时只编辑一个卷名，输入框不撑高卡片。
- 非组合态时回车提交、Esc 取消并还原原名；失焦提交须先安全结束组合输入。中文 IME 组合态的回车/Esc 交给输入法，不提交或取消整次改名，也不裁切或重置光标。取消后随后发生的失焦不能再次提交。
- 提交修剪首尾空白；空白视为未改名并提示，不把有效卷名覆盖成空串。保存前联合 flush 当前章，失败保留卷名草稿和错误提示，不显示已保存；只有成功后才更新显示与索引。
- 内联输入期间不触发卷展开/折叠、选章或拖动。开始移动前先完成或取消重命名，不能一边编辑卷名一边改变目录结构。

### 17.6 仅手动控制的折叠状态

- 宽屏提供始终可达的侧栏收起/展开按钮；收起后正文利用释放空间，章节标题和正文保持同一最大内容宽 760。窄屏保留目录按钮打开同一管理面板，并提供显式关闭入口。
- 宽屏侧栏收起偏好作为全局视图设置、每本书各卷的展开状态按 book ID 写入应用设置，重启可恢复；不把纯视图偏好混入章节名称或正文。窄屏目录浮层的打开/关闭只在当前会话维护，重启不自动弹出，且不覆盖宽屏收起偏好。
- 首次无记忆时，宽屏侧栏可见、卷卡片默认折叠；窄屏目录默认关闭。手动选章、新建卷/章、重开作品、进入移动模式及拖到卷上均不自动展开卷，也不自动收起侧栏/窄屏面板。
- 窗口变窄只切换面板承载方式，不覆盖用户在宽屏的收起偏好；重新变宽按原偏好恢复。宽窄入口共享卷展开状态，不各自维护一份互相覆盖的缓存。
- 当前章可位于已折叠的卷中，正文仍可正常写作；不为了暴露当前章而强行展开。新建卷后也保持默认折叠，用户自行展开后使用「+」。

### 17.7 卷级自动章节号

- 每卷在上下文菜单提供「卷设置」，保存启用开关与该卷独立的编号规则。新卷、旧数据缺字段的卷均默认关闭；关闭时只显示作者的原始章节名称。
- 规则字段：前缀、后缀、数字样式（普通阿拉伯数字 / 小写中文数字）、阿拉伯数字补零宽度、起始值、步长；支持实时预览，规则不是可执行脚本，也不增加导入任意表达式能力。
- 初始规则为前缀「第」、后缀「章」、阿拉伯数字、补零宽度 1、起始值 1、步长 1，但启用开关仍为关闭。示例可配置为「第1章」「001」「第一节」。中文数字使用普通中文数词，不加入大写金额或自定义字表。
- 起始值为 0–999999999 的整数，步长为 1–999999999 的整数；补零宽度为 1–9，仅对阿拉伯数字有效。前后缀为单行文字。预览或实际章节序列超出 999999999 时明确报错并阻止该配置/目录变更，不截断或环绕；未来扩容须另改规格。
- 该卷第 i 个章节（从 0 起）的值为「起始值 + i×步长」，按实际目录顺序计算，不按创建时间、旧 order 数字的间隙或正文内容计算。插入、删除、同卷重排、跨卷移入/移出后立即重算相应卷，卷排序不影响章号。
- 格式化编号为「前缀 + 按规则格式化的序号 + 后缀」；启用时的显示名称为「格式化编号 + 一个分隔空格 + 原始章节名称」，未启用时原样显示名称。目录、标题栏只读编号区、窗口标题及单章导出文件名使用一致的显示名称；标题输入框只编辑原始名称，编号在其旁独立展示。
- 规则仅保存在书级索引的对应卷元数据中；章名、章 ID、正文 txt、正文字数不受编号开关/规则变化影响，导出的正文也不插入编号或标题。卷名不加此编号。
- 开启前展示含现有章名的预览：若旧名已经含「第 N 章」等文字，仍保留，不猜测、剥离或批量替换，避免误伤作者实际标题；可由作者自行改名。
- 取消卷设置不落盘；保存期间防重复提交，失败保留设置草稿。规则变化须先联合 flush 当前稿；不把显示前缀写回 editor 的原始标题保存基线。

### 17.8 右键移动模式与拖动

- 移除「上移/下移」菜单项；右键或可达菜单中的「移动」进入显式移动模式。卷模式将所有卷行右侧菜单图标换成握柄；章节模式将所有章节行右侧菜单图标换成握柄，以便同书跨卷移动。二者不同时开启。
- 仅从握柄开始拖动，普通点击仍用于选章/折叠；不把正文选字、卷名输入或整行点击误识别成拖动。提供握柄提示、可见落点及「完成移动」入口；键盘也可在移动模式中调整位置，不恢复旧菜单上移/下移项。
- 卷仅在本书卷列表内排序；章节可在所属卷排序或拖入本书其他卷。拖到展开卷中的章间隙按该落点插入；拖到空卷或折叠卷标题上追加到该卷末尾，不自动展开目标卷。不允许跨书移动。
- 进入模式前先保存当前标题/正文；实际拖动及异步落盘期间禁止冲突的编辑/结构变更。无效落点、拖回原位或手势取消不改文件和顺序；成功放下后保存一次，不在每次悬停时写盘。
- 每次成功放下立即持久化，完成后可继续拖动；「完成移动」或 Esc 退出模式，Esc 不撤销此前已经保存的拖放。拖放未成功不能提示已完成；失败显示原因并恢复可重试状态。
- 移动当前章保持选择和内存草稿不变；跨卷后重新绑定到目标卷的存储位置与编号规则。移动其他章不得切走当前章。顺序持久化使用连续、唯一的 order 值，章节 ID 不变，不新建副本 ID。
- 手动折叠规则优先：握柄出现、拖动悬停及移动成功都不改变卷展开状态；长目录支持滚动到未显示落点，窄屏面板与宽屏支持相同移动能力。

### 17.9 模块边界与跨卷数据安全

- 主题 token 与控件主题只负责颜色和状态外观；书架负责卡片菜单及作品表单；共享目录面板负责折叠、内联编辑和移动交互，不直接编排磁盘操作。
- 编号模型/纯格式化逻辑负责规则校验、预览和统一显示名称，不访问文件、不改标题字符串。卷设置只提交经过校验的规则；视图偏好由设置层持久化。
- WorkspaceController 继续作为联合保存与结构操作的排他入口；LibraryController 协调元数据快照、顺序和摘要；章节存储层封装跨卷正文/备份转移与恢复，不把多文件事务散在 widget 回调中。
- 当前正文路径包含卷 ID，跨卷不只是调整 List/order。先等待读写与 IME 安全 flush 完成，确认源章节可读；转移 txt 与已有 .bak，不把正文归一化/重编码，也不以空文件代替读取失败。未解决的 .tmp 必须先恢复或停止操作。
- 跨卷采用可恢复的提交协议：先持久化本次移动的内部记录，准备并逐字节校验目标文件，源文件在目标数据与目录索引成功提交前保留；确认提交后才清理源位置及记录。只操作本书该章及本次新建的目标文件，不覆盖无关已有文件。
- 启动在普通章节恢复前处理未完成的移动记录：根据已持久化的目录归属完成或回滚，不从时间戳猜测目标；源/目标至少保留一份已校验正文和既有备份。不确定或恢复失败时保留文件、提示并阻止相关章的自动空白写入，而不是静默重建覆盖。
- 同卷/卷排序失败恢复内存与持久化顺序；跨卷失败回滚目录归属/编号/当前绑定，或保留可恢复记录并明确阻止继续写错误路径。对 book.json 已提交而摘要失败的情况也必须保证重启能确定真实归属，不能只恢复内存伪装为原地。
- 同一本书的结构变更与自动保存串行；删除/移动/改名/改规则不能在旧绑定上遗留定时保存，避免源卷出现已移走章节的复活文件。已有原子写、备份与关闭保存保护仍有效。
- 为旧 JSON 增加可选编号字段和视图设置即可，缺字段按关闭/默认值读取；不重建整库、不批量改旧名称/ID。目录重建遇到未完成移动先走移动恢复，不把同一章节同时登记在两个卷。

### 17.10 验收与交付门禁

1. 主题（以 2026-10-27 09:13 修订为准）：浅/深/系统切换，内容底色纯白/纯黑；其余与 0.2 的文字/朱砂、彩色书脊、按钮及状态/选区/弹窗样式一致。覆盖书架、设置、正文、宽窄目录与新增菜单/弹窗，原生截图确认未残留强制黑白主题且状态可辨识。
2. 卡片菜单：右键锚定、键盘可达；编辑指定书名/备注后排序与卡片正确；取消和保存失败不误改；删除确认、回收站和失败重试不丢作品。正文不再出现作品信息入口。
3. 新建：点击「+」无章名弹窗，只创建一次并进入正确章；新章名不带默认数字；上一稿保存失败时不创建；已有章名不变；旧超长名称与备注表单回归仍通过。
4. 内联卷名：回车/失焦保存、Esc 取消、中文组合回车、空白与失败重试；不误折叠/触发拖动；保留的单行弹窗在 900×600 与大窗口都不撑满高度。
5. 折叠：整个侧栏和所有卷均只能手动改变，切章/新增/重开/拖动悬停不自动改变；应用重启保留偏好；宽窄屏往返不覆盖宽屏收起状态，且目录入口始终可达。
6. 编号：新旧卷默认关闭、启停与重启持久化、各卷独立、前后缀/中文/补零/起始值/步长/零值/边界/非法输入；预览与目录/标题/窗口/导出文件名一致；新增/删除/排序/跨卷更新正确，原名/正文/字数逐字不变，旧名不自动剥号。
7. 拖动：仅握柄可拖、移动模式切换/完成/Esc、无效与原位落点、首尾/空卷/折叠卷/长目录滚动；卷排序、同卷和双向跨卷；当前章不切走；宽屏与窄屏均真实执行拖放，不只直接调用控制器当作 UI 通过。
8. 数据安全：txt 与 .bak 字节/章 ID 保留；在目标复制、记录、索引、摘要、清理等关键点注入失败并重启，证明完成/回滚均可恢复；覆盖当前章在途保存、快速重复操作与删除交错，不复活源卷旧文件、不覆盖作者稿。
9. 自动化：新行为先观察有效 RED 再实现；新增纯规则、存储故障、控制器与 widget 拖放回归，运行全量测试、format 与 analyze。上一轮 56 绿不能替代本轮新结果，不把测试就绪条件/编译错误计作功能 RED。
10. 发布：新版本 Windows x64 release 和完整新 ZIP，不覆盖 0.2.0；外目录解压逐文件核验、隔离根运行原生宽窄布局/菜单/保存/重启/移动验收，只关闭本轮自有进程。记录新的 hash、命令结果和人工 IME、其他 DPI/平台的未验边界；作者作品与运行实例不得被改动。

### 17.11 当前阶段与下一步

- 设计审批及定时实施授权已完成；主题以 §17.2 / §18.9 的作者修订为准。实现与最终验证记录见 §19；早期讨论、56 测试和中间候选均不替代本轮证据。
- 作者已通过书面规格并授权北京时间 2026-10-27 01:15 定时实施（本次触发 2026-10-26T17:15:00.009Z）。实施计划续于 §18；本节的确认不等于功能已实现或验证。
- 本轮不加入跨书移动、自动剥除历史章号、任意脚本规则、整书导出、搜索、云同步、新平台构建或系统原生窗口改色。

---

## 18. 黑白目录工作区 Implementation Plan（2026-10-27）

> **For agentic workers:** 使用 executing-plans 在本会话逐项执行，禁止子智能体、队友、并行代理。根本文是唯一规格/计划来源，不另建计划。以下复选框只依据本轮新鲜证据更新；不合并、不推送、不把原未跟踪 M1 源码当本轮新增提交。

**Goal:** 实现 §17 全部行为，优先证明跨卷正文安全，再完成真实交互及 Windows x64 新包隔离验收。

**Architecture:** 保留 ChangeNotifier、Fluent UI 和原文件布局。独立纯编号模型负责显示；移动存储服务以 book.json 的实际归属为提交判据，先记录、准备及校验正文/备份再提交索引，恢复优先于普通扫描。WorkspaceController 排他协调 IME 安全 flush、结构修改及当前绑定，目录 UI 不直接进行文件 IO。设置仅存视图偏好。

**Tech Stack:** Flutter 3.47.7 / Dart 3.13.5、fluent_ui 4.17.0、material_ui 1.8.0、flutter_test、Windows / VS Build Tools 2026。不新增运行依赖。

### 18.1 保护、基线与执行方法

- [x] 核对 cwd 为 `C:/Users/userSigma/no-white-writer`、分支 `ui/writing-workspace`、规格提交 `faa3f88`。保留原 README 修改和所有未跟踪源码；不 reset/clean。
- [x] 当前源码另存 `.devdata/pre-17-20261027-0115/`，442 个文件逐一 SHA-256 比对无差异，清单为该目录的 `sha256.csv`。旧 `.devdata/ui-baseline` 不作起点。旧 0.2.0 ZIP hash 仍为 `4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`。
- [x] 每一任务先写测试、用 SDK 绝对路径执行并记录有效 RED，再最小实现得到 GREEN；编译/环境错误不算功能 RED。宿主命令使用已验证可用的 PowerShell，日志置于 `.devdata/section17/`；不因历史 bash 不可用切换绕过任何沙箱拒绝。
- [x] 每阶段亲自回读差异和故障路径，不派审查代理；本轮只在现有分支实施，不 stage 整个原 M1 树。

### 18.2 Task 1：编号规则与兼容模型

**Files:** 新建 `lib/core/chapter_numbering.dart`、`test/numbering_test.dart`；修改 `lib/core/models.dart`。

- [x] RED：先通过旧模型 JSON 往返证明 numbering 字段被丢弃，再添加格式化/边界测试。断言 `Volume.fromJson({'id':'v','title':'旧卷','order':0}).toJson()['numbering']` 不为空且 `enabled == false`；章名与正文不参与改写。
- [x] 实现不可变 `ChapterNumbering`，字段 enabled/prefix/suffix/style/padding/start/step，默认 `false/第/章/arabic/1/1/1`。`validate(int count)` 检查单行前后缀、范围、实际末序号和三项预览；`label(int index)` 纯函数；`displayChapterTitle(Volume volume, ChapterMeta chapter, {String? rawTitle})` 以章在列表的下标计算，不依赖 order 间隙。
- [x] GREEN：覆盖 0、10、11、20、101、1001、10001、100000001、999999999 中文数词，001 补零、起始值/步长、旧名不剥号、各卷独立、非法数值/换行及溢出。运行 `flutter test test/numbering_test.dart --reporter expanded`。

### 18.3 Task 2：可恢复跨卷正文事务

**Files:** 新建 `lib/core/storage/chapter_move_store.dart`、`test/chapter_move_test.dart`；修改 `lib/core/storage/book_store.dart`。复用现有 `lib/core/storage/chapter_store.dart` 与 `lib/main.dart` 的启动顺序，不需修改这两个文件；BookStore 先恢复迁移，迁移层核验后处理备份时间关系。

- [x] RED：基于临时数据写入带 BOM/CRLF 的 txt 与不同 .bak 字节，先证明旧接口无跨卷能力。故障测试由可注入 phase 回调逐阶段中断；不以模拟 List 移动冒充文件测试。
- [x] `ChapterMoveStore` 记录稳定 book/章/source/target ID 和正文/.bak 的原始字节校验信息（内部记录只在该书目录）。准备前拒绝未处理 .tmp、缺失源及已有目标；记录持久化后复制原字节到本次新目标并读回逐字节比较，保留源。索引提交为唯一归属判据；摘要不充当提交标志。
- [x] `recover(bookId)` 必须在 BookStore load/rebuild 及普通章节恢复之前执行。索引仍指源则撤销本次匹配目标；索引指目标则校验目标、必要时由已校验源补全，再清源和记录；索引不明/字节不一致则保留并抛明确错误，不重建、不空写。只删除本次记录且内容匹配的文件，记录清理失败保持幂等。
- [x] GREEN：在 record/prepared txt/prepared bak/verified/index/summary/cleanup 注入失败并重新创建服务恢复；断言至少一份字节正确正文与旧备份、唯一目录归属、原 ID、不覆盖预存目标；覆盖冲突/坏记录/坏索引/.tmp/无源/双向移动，运行 `flutter test test/chapter_move_test.dart --reporter expanded`。

### 18.4 Task 3：安全元数据与工作区排他入口

**Files:** 修改 `lib/state/library_controller.dart`、`lib/state/editor_controller.dart`、`lib/state/workspace_controller.dart`、`lib/state/settings_controller.dart`、`lib/core/models.dart`；新增 `test/workspace_revision_test.dart`，扩充既有保存测试。

- [x] RED：新建默认名、折叠默认空/重启记忆、移动当前章绑定、序号溢出拒绝、保存/摘要失败回滚、在途保存与 IME 等待、快速重复操作及删除交错分别写独立测试。
- [x] 将新章/新卷默认名设为未命名章节/未命名卷。视图增加 sidebarCollapsed 和按 bookId 的展开集合，设置存储为唯一缓存；移除选章/新建自动展开。新建前校验编号容量。
- [x] 提供 LibraryController `Future<void> relocateChapter(BookIndex book, String chapterId, String targetId, int insertionIndex)`、`Future<void> reorderVolume(BookIndex book, String volumeId, int insertionIndex)` 及编号设置保存，正常序号归一为 0..n-1。实现用稳定 ID 而非跨异步回调持有旧对象，仍在同书内验证归属。失败以已持久化 book.json 真实状态为准，不在摘要失败后伪造原位置；同卷/卷排序保存失败回滚并恢复连续 order。
- [x] WorkspaceController 提供进入/退出单一移动模式、开始/取消拖动、移动及配置入口；先等待安全 flush，移动/落盘期间锁定编辑及结构操作。当前章跨卷仅重绑定 Volume 不重读/清空 controller；草稿、选择、保存基线保持不变，取消旧 debounce。无法恢复时阻止该章写入并显示原因。
- [x] GREEN：运行 `flutter test test/workspace_revision_test.dart test/editor_save_test.dart test/workspace_test.dart test/library_flow_test.dart --reporter expanded`；原删除不复活与标题/正文安全继续通过。

### 18.5 Task 4：主题与书架真实菜单（主题步骤由 §18.9 修订）

**Files:** 修改 `lib/ui/theme/tokens.dart`、`lib/app.dart`、`lib/ui/shelf_page.dart`、`lib/ui/editor_page.dart`、`lib/ui/settings_page.dart`、`lib/ui/book_details_dialog.dart`；新建共用 `lib/ui/context_menu.dart`；测试 `test/monochrome_test.dart`、`test/ui_revision_test.dart`。

- [x] RED：按 §18.9 验证纯白/纯黑内容底色与 0.2 其他样式；原全控件黑白断言已被作者修订取代。继续验证右键指针附近菜单、键盘菜单、编辑指定 stable ID、不进入正文及删除失败保留卡片。
- [x] 仅替换 paper/ink 内容底色，其余恢复 0.2 token、彩色书脊、按钮、状态、选区、弹窗与提示样式，实施步骤见 §18.9；不得回退目录/编号/事务安全功能。
- [x] 书架卡片使用锚定上下文菜单「打开/编辑信息/删除」，支持 secondaryTap、键盘菜单、长按；复用原表单，取消不写盘，失败留草稿，删除失败恢复原目录/卡片。侧栏移除作品信息入口。
- [x] GREEN：运行 `flutter test test/monochrome_test.dart test/ui_revision_test.dart --reporter expanded`，保留固定卡片、旧长名、50 字字符簇和备注高度回归。

### 18.6 Task 5：手动折叠、内联卷名与卷设置

**Files:** 修改 `lib/ui/chapter_pane.dart`、`lib/ui/editor_page.dart`、`lib/app.dart`、`lib/state/editor_controller.dart`；新建 `lib/ui/volume_settings_dialog.dart`、`test/catalog_revision_test.dart`。现有 `lib/core/storage/export_service.dart` 已接受显示文件名，复用其不覆盖正文的接口而不修改服务。

- [x] RED：宽屏收起/展开、宽窄往返、首次卷折叠、新建/选章不展开；点击 + 不弹输入框、只建一次且默认标题选中；窄浮层不自动关闭或抢焦点。
- [x] 卷标题内联 TextBox，回车/失焦提交、Esc 取消，先检查 composing；失焦等待上屏，不 clearComposing 伪装安全。失败保留文本，空白还原并提示。保留命名单行弹窗使用内容包裹高度。
- [x] 卷设置有启用、前后缀、阿拉伯/中文、宽度、起始、步长及实时含旧章名预览。取消无改、验证失败禁止提交、异步防重入与草稿保留。目录、独立只读标题编号、window title 和导出文件名复用 displayChapterTitle，正文与原名不改。
- [x] GREEN：真实点击/输入/IME 组合 widget 测试，运行 `flutter test test/catalog_revision_test.dart --reporter expanded`。

### 18.7 Task 6：握柄拖放与键盘等价操作

**Files:** 修改 `lib/ui/chapter_pane.dart`、`lib/state/workspace_controller.dart`；新建 `test/catalog_drag_test.dart`。

- [x] RED：先用 tester.startGesture/moveTo/up 从真实握柄拖章/卷；覆盖宽、窄、同卷、双向跨卷、空卷/折叠卷标题追加、章间隙、原位/取消/无效目标。断言目录、真实文件与重启结果，不直接调控制器作为 widget 通过证据。
- [x] 移除上移/下移菜单，只显示移动。模式互斥，所有对应行菜单改握柄；仅握柄 Draggable，DragTarget 显示落点、放下才一次持久化。drag start 到落盘结束禁冲突编辑，失败结束拖态并提示重试；Esc/完成只结束模式、不撤销已提交操作。
- [x] 键盘握柄上下移动及跨卷入口走同一 WorkspaceController 路径；长列表边缘拖动驱动 ScrollController 滚动、不得触发自动展开。普通选章/折叠继续仅手动。
- [x] GREEN：运行 `flutter test test/catalog_drag_test.dart --reporter expanded`；覆盖忙碌与重复 drop、当前章绑定/草稿及不复活源文件。

### 18.8 Task 7：全量门禁与新发布包

**Files:** 修改 `pubspec.yaml`、`windows/runner/Runner.rc`（版本如需要）、`README.md`、`docs/env.md`、根本文；验收脚本及日志只在 `.devdata/section17/`。

- [x] 亲自按 §17.1–17.11 回读本轮差异；通过当前快照对照明确有意变更，不把大量原未跟踪文件报为新增。
- [x] `dart format lib test` 后运行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test --reporter expanded`，保存新日志和测试总数；所有失败先定位再补回归修复。
- [x] 升级为 `0.3.0+3`，执行 `flutter build windows --release`；junction 仅按原工具修复，不清理旧包。完整 release 打包到全新 `build/packages/no-white-writer-0.3.0-windows-x64.zip`，拒绝覆盖已有同名，记录字节数及 SHA-256。
- [x] 解压至工作区外本轮唯一目录，逐文件 hash 对照 release；以 NWW_DATA_ROOT 隔离启动，记录本轮 PID，只关闭该 PID。原生检查恢复 0.2 样式且纯白/纯黑内容底色的宽窄页、右键锚定、+、编号、内联、真实移动、保存/关窗/重启归属及 .bak；不触碰 AppData 作者作品。
- [x] 更新本节勾选、README 与 env 新鲜证据、ZIP hash、外目录验证，保留人工 IME/DPI/其他平台未验证边界；交付新包，目标仅在实现且验证完成后 complete。

### 18.9 续执行修订计划：0.2 样式与纯白/纯黑底色（2026-10-27 09:13）

**Goal:** 继续目录/编号/安全迁移交付；只撤回全控件黑白化，按 §17.2 恢复 0.2 外观。

**Architecture:** `.devdata/pre-17-20261027-0115/` 是本轮实施前的当前 0.2 源码参照，只抽取视觉差异，不覆盖当前目录状态机/文件事务。主题入口回到原 Fluent 配置，内容背景仍由 paperOrInk 统一。当前实现另存于 `.devdata/pre-theme-restore-20261027-0913/`（64 文件及 SHA-256 清单）；旧 0.2 ZIP、作者数据、现有未提交修改保持保护。

**Files:** `lib/ui/theme/tokens.dart`；`lib/ui/shelf_page.dart`、`lib/ui/chapter_pane.dart`、`lib/ui/editor_page.dart`、`lib/ui/context_menu.dart`、`lib/ui/settings_page.dart`、`lib/ui/book_details_dialog.dart`、`lib/ui/volume_settings_dialog.dart`、`lib/app.dart` 的视觉字段；`lib/core/text/indenting_controller.dart` 与各输入控制器；测试 `test/monochrome_test.dart`、`test/selection_contrast_test.dart`、`test/catalog_drag_test.dart`。移除仅用于全黑白化的通知/选字包装，不改变原输入值和组合态安全校验。

- [x] **1. RED — 更新失效的主题验收，而非删除功能回归。** 断言 paper/ink 为纯白/纯黑、朱砂与其他 token 等于 0.2 值、同 coverSeed 的书脊仍为稳定彩色渐变；真实设置/书架/编辑器覆盖内容底色、彩色按钮和保存状态。输入选区改验 0.2 控制器风格，仍验证组合态值不被修改。例如：
  ```dart
  expect(AppColors.paper, const Color(0xFFFFFFFF));
  expect(AppColors.ink, const Color(0xFF000000));
  expect(AppColors.cinnabar, const Color(0xFFA6402B));
  expect(AppColors.textOnPaper, const Color(0xFF2B2A27));
  expect(spineGradient(17).colors, isNot(everyElement(Colors.black)));
  ```
  执行 `flutter test test/monochrome_test.dart test/selection_contrast_test.dart --reporter expanded`，观察当前强制黑白实现因恢复要求而 FAIL，日志为 `.devdata/section17/theme-restore-red.log`。右键 stable ID、CRUD/失败重试/拖动测试不移除。
- [x] **2. GREEN — 最小恢复主题入口及调用处视觉。** 以 0.2 token 实现为准，只有 `static const Color paper = Color(0xFFFFFFFF);`、`static const Color ink = Color(0xFF000000);` 两个底色不同。`buildFluentTheme(Brightness brightness)` 恢复原 brightness/accentColor/scaffoldBackgroundColor 配置；还原默认按钮/焦点/滚动条/提示主题，移除本轮黑白 ResourceDictionary 和反色 TextSpan。书架恢复 coverSeed 渐变、原选中条/边线/阴影；保存恢复原状态颜色；新菜单/握柄采用朱砂/次要色等原 token，安全禁用逻辑不变。运行相同目标测试直到 GREEN。
- [x] **3. 完成暂停中的内联草稿生命周期修复。** 已有 `.devdata/section17/pane-lifetime-red.log` 证明宽/窄隐藏目录会销毁未完成 IME 卷名。完成 ChapterPaneDraft 握手：组合态不关闭/跳转，完成态先提交成功才隐藏；错误保留输入。其余正文联合 flush、拖动锁、删除不复活保护继续有效。执行 `flutter test test/catalog_forms_test.dart test/catalog_revision_test.dart test/catalog_drag_test.dart --reporter expanded`，必须覆盖实际 widget 输入和拖放。
- [x] **4. 重新执行发布门禁。** 此前 102 测试及候选 release 只是修订前的中间证据；已有候选包已存 `.devdata/section17/rejected-before-startup-fix.zip`，不是本次交付。重新 format/analyze/全测/build、全新 ZIP、外目录逐文件核验、隔离原生宽窄与浅深主题/移动/保存/重启；更新本文、README、env 的最终实测值。只关闭本轮自有 PID，不合并、不推送。
- [x] **5. 原生复测发现的发布文案一致性。** 设置页仍保留旧 `0.1.0` 和“暖白纸”标签；先在真实设置 widget 中断言版本 `0.3.0`、浅色“纯白”和深色“纯黑”并观察 RED，再只修改这三处文案。重新执行全部门禁，归档本轮自有中间候选而不覆盖旧发布包；对最终包再次外目录逐文件核验、复测迁移及重启保存。

## 19. 本轮实施与最终验证结果（2026-10-27）

### 19.1 完成范围与计划落点

- 实现 §17 目录、编号、同书握柄拖放及可恢复跨卷事务；主题最终按作者 09:13 修订：恢复 0.2 视觉，只改变纯白/纯黑内容底色，不交付中途强制全黑白控件的候选。
- 已先记录有效功能 RED 再实现编号、控制器、菜单、内联/规则表单、真实拖放、选区/主题修订与面板生命周期保护。编译失败、异步就绪条件不算 RED；恢复 0.2 样式后更换了被修订取代的颜色断言，未删除 CRUD、文件安全或真实拖动回归。
- 关键审查修正：源 `.bak.tmp` 必须在记录/索引前拒绝；删除作品摘要失败补偿恢复卡片及原目录；拖动期间导航拒绝；迁移核验后校准正文/备份时间关系，避免普通恢复误覆盖；应用根窗口标题从实际索引归属取卷，不使用跨卷提交中短暂过期的绑定。上述均有回归。末轮又补充损坏迁移记录阻止 load/rebuild 的既有保护测试，未改生产代码。
- 目录内联名称在隐藏或导航前握手，组合态不强制清空，完成态先提交成功才隐藏，失败留稿；宽窄 widget 输入及真实拖放均已执行。
- 工程落点说明：结构 API 用稳定 ID；普通恢复/启动顺序及通用导出服务无需改动。编号在调用方传入显示文件名；这减少了对原有稳定模块的改动，不改变规格。
- 亲自回读当前源码及故障路径，对照 01:15 当前源码快照，lib 下 **19 个有意差异路径，4 新建、15 修改**；不是把原未跟踪 M1 当成本轮新增。统计见 [最终快照差异](<.devdata/section17/final-review-stat.log>)。旧快照、作者作品与旧发布包均保留；无子代理、无 reset/clean、无合并或推送。

### 19.2 新鲜命令证据

| 门禁 | 最终结果 | 证据 |
| --- | --- | --- |
| 格式检查 | 57 Dart 文件，0 变化，exit 0 | [format](<.devdata/section17/final-format-check.log>) |
| 静态分析 | No issues found，8.0 s，exit 0 | [analyze](<.devdata/section17/final-analyze.log>) |
| 全量测试 | **107 项全部通过，21 s，exit 0** | [全测](<.devdata/section17/final-test.log>) |
| Windows x64 release | 61.9 s 成功；版本 0.3.0+3 | [build](<.devdata/section17/build.log>) |
| 包与运行后校验 | 完整 21 文件逐一 SHA-256 一致，旧包未变，自有 PID 已关闭 | [发布校验](<.devdata/section17/post-native-proof.log>) |

生产代码最后构建后仅补充测试、文档与验收脚本；末轮格式化只改变测试，不改变已构建源码。八阶段故障注入与普通启动恢复联测、宽窄握柄拖放和根应用窗口监听均包含在 107 项内。旧 56 项和早期 102 项不作为最终结果。

### 19.3 交付与原生证据

- [完整 Windows ZIP](<build/packages/no-white-writer-0.3.0-windows-x64.zip>)：**25,465,992 字节**；SHA-256 `1D48C5E95DC80BA1C7FEF71C906BAF1021D5A016C3A6DEA4BB3900A94E270C0C`。旧 0.2.0 ZIP hash 仍为 `4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`。中间候选另行归档，不覆盖旧发布。
- 工作区外解压到 `C:/Users/userSigma/Downloads/no-white-writer-0.3.0-windows-x64-20261027-103743`；完整 21 文件发布与解压副本逐一校验，原生运行后复核仍一致。版本资源为 0.3.0+3，设置页文案也为 0.3.0 / 纯白 / 纯黑。
- 仅在合成数据的独立 `NWW_DATA_ROOT` 运行：最终包宽屏把当前章拖入折叠目标，窄屏拖回折叠源，实际归属、ID、当前章和 txt / bak hash 保持正确；规则使标题即时从无编号变为 `No.002 Raw chapter 0` 再恢复，目标不自动展开。原生落点及字节证据见 [断言](<.devdata/section17/release-native-assertions.log>)、[宽屏](<.devdata/section17/release-wide-dragged.png>)、[窄屏](<.devdata/section17/release-narrow-returned.png>)。
- 最终包 PID 36540 输入 `release-title-030` / `release-body-030` 后关窗，日志显示退出请求、正文保存与接受退出；重启 PID 39884 后两字段正确，原移动章正文与备份字节仍未变。均先核对 exe 路径，仅关闭自有进程，最后无遗留自有进程。见 [重启证据](<.devdata/section17/release-restart.log>)、[重启正文](<.devdata/section17/release-restart-editor.png>)。
- 原生脚本的正常退出后失效 PID、窗口恢复几何导致未命中握柄的尝试不计通过；定位并明确调整窗口尺寸后才记录成功拖放，未用直接调用控制器代替。
- [README](<README.md>) 和 [环境记录 §8](<docs/env.md#8-030-目录编号与安全移动验证2026-10-27>) 已更新。当前分支仍为 `ui/writing-workspace`，HEAD `faa3f88f8080e784eb66f81a691ef159dd171ea1`，仅保留未提交工作树。

### 19.4 未验边界

- 自动 widget 组合态测试不是微软/搜狗候选窗的人工验收；中文长句、失焦/撤销重做、组合态跨响应式断点、多屏与 150% / 200% 仍待作者体验。其他平台未构建。
- 此轮不触碰默认 AppData 作品，也不把隔离根验收说成重新验收默认路径启动。初始化异常 UI 提示仍为既有边界；交互中曾出现 Flutter AXTree 警告，未宣称无障碍读屏已完整验收。
- 完成的是已批准功能、自动化和本机隔离发布门禁；上述人工体验事项明确保留，不能据此伪称其他平台或所有 IME 场景都已通过。

---

## 20. 无边框目录、弹出设置与三级导出规格（2026-10-27，作者已确认）

### 20.1 依据、优先级与范围

- 作者本轮要求：右键菜单及书内卷章列表无边框；返回位于侧栏左下、设置位于右下；章名和卷名允许空；设置改用下拉／上拉选单；章／卷／书菜单分别提供相应导出；侧栏展开收起有过渡动画。参考作者提供的菜单、目录、返回和设置截图。
- 对照稿与对话已确认：采用 **B 完全隐藏侧栏**，不留窄栏；空标题使用仅显示的灰色占位；设置采用 **菜单＋子选单**；导出本书放在 **书架卡片右键／⋯菜单**，不增加书内书名菜单。作者已分段确认界面方案、TXT 格式及保存保护。
- 本节是这一轮的新规格，覆盖 §17.5 的“空卷名保留旧名”、旧章节非空校验、旧设置页面与顶栏导出入口，以及 §17.11 排除整书导出的限制；也覆盖早期章节关于这些交互的冲突条目。其他 §17 安全、编号、手动折叠及拖动规则继续有效。旧章节与 §19 的结果保留为历史，不代表本轮已实现或验证。
- 选择局部升级：沿用 Flutter／Fluent UI、现有编辑／存储框架和文件布局，定点调整目录外观、标题校验、弹出选单与导出协调。未采用重写工作区导航和菜单体系的方案，因为会扩大焦点、IME、保存与恢复的回归面；不引入第三方菜单／树控件或数据库。
- 保留 0.2 风格的文字、朱砂、书脊、字体和状态表达，内容底色仍为纯白／纯黑；本轮不是再次全控件黑白化。保留固定 220×300 书架卡片、现有编号规则、同书安全拖放、5 秒联合保存、备份及回收站。
- 不扩展到跨书移动、富文本、其他导出格式、搜索、云同步、其他平台构建或系统原生窗口改色。根本文仍是唯一设计／计划事实来源，不另建规格文件。

### 20.2 无边框菜单和目录

- 书架、卷、章的右键及 ⋯ 入口使用同一无边框菜单语义：弹出容器不画轮廓线，菜单项不再带默认按钮矩形描边；保留适量圆角、浮层阴影、悬停／按下／禁用状态。无边框不等于移除键盘焦点提示。
- 书内侧栏取消每卷外围矩形边框和每章按钮的常态边框。卷头为紧凑平面行，章节左对齐排列，以层级缩进、留白和卷头底色区分；当前章使用既有浅选中底色与朱砂文字，不使用整行矩形描边。
- 卷折叠箭头、章／卷菜单、字数、新建章 +、移动握柄和落点仍可辨识。临时拖放落点、输入框与焦点提示不属于被取消的常态卡片边框。
- 指针右键锚定点击位置，⋯ 菜单锚定触发按钮；边缘自动避让，长菜单可滚动。保留 Escape、方向键、Enter、Tab 等键盘可达能力，关闭后焦点回触发入口；不得把右键菜单改回居中操作对话框。
- 所有动作按稳定 book／volume／chapter ID 定位；菜单打开后排序变化不得导致编辑、删除或导出错误对象。删除二次确认与失败留稿规则不取消。

### 20.3 完全隐藏侧栏、底部按钮和动画

- 宽屏展开时，返回位于侧栏左下、设置位于右下，固定在目录滚动区之外；从写作顶栏移除这两个旧入口。收起时侧栏宽度降为 0，目录及两个底部按钮全部隐藏，正文利用释放空间，但仍遵守最大内容宽 760。
- 顶栏保留始终可达的侧栏展开／收起入口。B 方案明确不在收起状态额外保留返回／设置快捷窄栏；需要时先展开。
- 展开与收起约 200ms，使用平滑宽度／位移动画并适当淡入淡出；快速连续操作从当前位置反向，不创建重复面板、控制器或重复保存任务。系统要求减少动画时改为立即切换。
- 动画开始前完成既有草稿握手；IME 组合中或提交失败时不强制关闭／跳转。关闭过程中不允许不可见内容继续接受指针、焦点、拖动或辅助功能操作；不能仅把透明度设为 0 而留下可操作的隐藏目录。
- 窄屏继续由目录按钮打开同一内容的受约束浮层，返回／设置在该浮层底部左右两端，打开／关闭也有过渡；不另造与宽屏不一致的目录。显式关闭、Escape 和其他关闭路径都经过相同草稿保护。
- 保留 §17.6 的状态策略：宽屏收起偏好全局持久化；窄屏打开状态仅当前会话，重启不自动弹出，也不覆盖宽屏偏好；每本书各卷展开状态独立保存。切章、新建、拖放和悬停仍不得自动展开卷或收起目录。宽窄往返不重置这些偏好。

### 20.4 真正的空标题和显示占位

- 章名与卷名允许清空，沿用首尾空白修剪；纯空白规范化为空字符串并真实保存。不能因空串恢复旧名、取消提交、改成默认名，或在重启／JSON 读取／编辑基线同步时把空串当缺字段。
- 新建章、首章和新建卷仍沿用现有“未命名章节／未命名卷”默认名称，作者可清空。这一轮不批量清空或改写旧作品名称。
- 空卷名显示灰色“未命名卷”；空章名未启用编号时显示灰色“未命名章节”，启用时只显示格式化编号，不额外拼接空格或占位名称。占位是显示提示，不写回索引、输入框值或保存基线。
- 标题输入框编辑原始值，空值可显示弱化的输入提示；卷名仍内联编辑。非组合态回车／失焦提交空名，Escape 仍取消并还原原值；组合回车／Escape 不提交或取消改名，失败保持草稿和错误。
- 目录、窗口标题、只读编号区及导出名称使用同一显示规则。空标题不改变 ID、文件路径、正文、字数、排序或编号规则；不剥除作者自行写入的历史章号。
- 文件名／路径需要非空名称时使用显示编号或安全的未命名后备名称，继续清理非法文件名字符并避免同名覆盖；这是导出显示规则，不向原作品写入占位。

### 20.5 设置菜单及子选单

- 设置不是独立页面，也不是把整个旧设置表单塞入一个浮层。右下设置按钮打开无边框主菜单，主题、字号、行距等通过就近子选单调整；带选中状态、当前值或勾选提示。
- 保留现有设置：跟随系统／浅色纯白／深色纯黑；字号 14–28；行距 1.4–2.4；回车自动缩进及自动空行；导出目录设置、恢复默认和打开；数据与日志目录的查看／打开；关于与当前版本。具体数值范围不因换入口而缩减。
- 子选单可按需使用主题选项、滑块、开关及紧凑路径输入／保存等控件；仍属于菜单层级，不导航到设置页面。路径长时可横向编辑或滚动，不撑出屏幕。
- 位于底部时主菜单向上打开；其他入口按上下剩余空间选择方向，子选单左右避让，整体受窗口约束且可滚动。窄窗、大字号和高 DPI 不把操作裁到屏幕外。
- 子选单内操作不误触后方目录或正文。Escape 先退当前子级，再关闭主菜单；点击外部可关闭，但不得无提示丢弃进行中的路径输入／IME 草稿。显式路径保存失败保留输入并允许重试，不提示已保存。
- 设置变更更新现有设置控制器并按原策略持久化；持久化失败明确提示并允许重试，不能把只更新内存当作落盘成功。打开文件管理器失败也要报告。
- 书架原有设置入口同样弹出选单，不为书架增加侧栏。所有正常入口与遗留调试入口同步处理，不保留仍可访问的旧设置页面；卷编号的“卷设置”保留为独立的原有规则编辑，不与全局设置混淆。

### 20.6 章、卷、书三级 TXT 导出

- 章菜单添加“导出本章”，对菜单指定章有效，包括非当前章；写作顶栏移除原单章导出按钮。卷菜单添加“导出本卷”。书架卡片右键／⋯菜单添加“导出本书”，与打开、编辑信息、删除同级；不添加书内书名菜单，也不混入全局设置。
- 单章只导出正文，保留既有末尾换行约定；文件名称使用当前显示章名。整卷按该卷当前章节顺序，整书按当前卷顺序及各卷章顺序导出，不按创建时间或旧 order 间隙排序。
- 沿用已有 TXT 分隔格式：卷头 `──── 卷：显示卷名 ────`，章头 `──── 章：显示章名 ────`，各头后两个换行；正文使用既有末尾换行约定。章头包含所属卷当前规则生成的独立编号；空卷／空章按 §20.4 显示规则取名。书名用于文件名，不额外插入书头或修改原正文。
- 目录布局沿用现有服务：单章为“导出根／书名／卷名／章名.txt”，整卷为“导出根／书名／卷名.txt”，整书为“导出根／书名.txt”。使用用户导出根或默认根，同名自动另取唯一名称，不覆盖旧导出。应用内重复点击与不同导出入口排他协调，避免选取同一目标名称。
- 目标卷／书没有任何章节时提示“暂无章节可导出”，不生成文件；真实存在但正文为空的章节仍可导出。整书若含空卷但其他卷有章，保留空卷的卷头。
- 先安全提交当前章标题／正文及内联卷名草稿，等在途保存完成，再获取稳定目标索引和全部目标正文；非当前章从存储读取，不通过选择／打开章节来收集内容，不改动当前绑定、选择、展开状态或最后打开章节。
- 全部内容读取成功后才写目标文件；任一正文缺失、解码／读取失败、临时文件未解决或迁移记录未完成时停止，明确指出问题，不以空字符串冒充缺稿，不以导出触发目录重建或静默恢复。
- 写入继续采用临时文件和原子提交；失败不报告成功，不把部分内容留下当作最终导出；清理仅限本次自有临时产物，不能删除已有导出或作品文件。成功显示实际路径，打开目录遵守平台能力并处理失败。
- 导出不修改索引、原正文或 `.bak`，不把编号／占位写回作品，不创建新的章节 ID。导出前必须完成的正常草稿保存属于既有编辑保存，不是批量重写未编辑正文。

### 20.7 保存、失败与互斥保护

- 沿用 EditorController、WorkspaceController 及 ChapterPaneDraft 的组合态／联合 flush 门禁。菜单入口不以强制清空 composing、切换绑定或销毁输入控件的方式结束输入法；组词中不开始有冲突的导出、折叠、导航或结构动作。
- 内联卷名、标题和正文保存失败都留稿；只在安全提交完成后才执行后续动作。菜单／动画改变载体时仍必须保持相同语义，失焦与关闭不会重复保存同一个草稿。
- 导出等待／执行期间禁止同一目标的删除、改名、重排、跨卷移动及重复导出，并防止与自动保存取到混合快照。锁的成功、失败、取消和页面销毁路径均释放，失败后可重试。
- 本轮不改 §17.9 的跨卷提交判据、恢复日志、正文／备份字节转移和删除不复活保证；新菜单不能绕过现有排他入口。原子写、摘要失败补偿、绑定更新、在途保存及重启恢复继续回归。
- 菜单关闭、取消设置或动画反向本身不算业务成功；通知只依据实际持久化／导出结果。不得把文件读取失败记作成功的空章或部分导出。

### 20.8 模块边界与状态流

- [共享菜单](<lib/ui/context_menu.dart>) 负责无边框外观、定位、焦点、层级及关闭规则，不直接读写作品；可复用同一菜单基础承载全局设置子级，避免三套视觉和键盘行为。
- [目录面板](<lib/ui/chapter_pane.dart>) 负责平面卷章行、内联编辑、目标 ID 菜单与原握柄交互；[写作页](<lib/ui/editor_page.dart>) 负责侧栏承载、底部入口和过渡，不把导出文件 IO 放进 widget。
- 设置选单复用现有设置控制器／持久化能力并独立管理路径草稿；旧 [设置页（实施前快照）](<.devdata/pre-20-20261027-143823/lib/ui/settings_page.dart>) 的用户导航入口被替代，而不是保留两种并存界面。
- 标题控制器和元数据协调仅放开空值并保持失败基线；纯显示格式化统一编号／占位，JSON 缺字段兼容与显式空字符串分开处理。
- 导出协调层负责“门禁与锁 → 当前草稿提交 → 固定目标快照 → 严格读取全部正文 → 调用 [导出服务](<lib/core/storage/export_service.dart>) → 结果通知／释放”。存储服务负责安全读取和原子写；书架只传稳定 book ID，卷章菜单只传稳定目标 ID。
- 不用全局重建、切章遍历或旧 M1 快照替换当前实现。自动化可注入读取／写入／保存失败，便于验证不产残缺文件、不切绑定、锁释放和重试。

### 20.9 验收矩阵与交付边界

1. **视觉与菜单交互：** 浅／深色下书架右键、卷章菜单、全局设置及子级均无常态边框；宽窄目录卷章无框、左对齐，选中／禁用／键盘焦点可辨。实际指针右键、⋯、键盘、边缘避让和外部关闭均验证，不只检查 widget 配置。
2. **侧栏与动画：** 完全隐藏后无剩余窄栏，返回／设置只在展开的底部左右；展开入口始终可达。验证动画中间帧、最终宽度、反向、减少动画、隐藏内容不接收点击／焦点；宽窄切换及重启偏好不回退，失败／组词中不丢草稿。
3. **空标题：** 卷／章清空、纯空白、回车／失焦、Escape、组合态、保存失败重试、重启回读均验证；占位不落盘，编号开／关与跨卷后显示一致；新建默认名称不变，正文／备份／ID 无意外改写。
4. **设置子选单：** 由真实点击从写作底部与书架入口打开，正常入口不导航旧页面；逐项调整原设置、重启持久化、路径草稿与错误重试、Escape 层级、窄窗边界及失败后可操作均覆盖。
5. **三级导出：** 实际点击各目标菜单，验证当前／非当前章、单卷、整书、当前顺序及各卷不同编号、空名／空正文／空目录、同名不覆盖、自定义目录；导出时绑定和展开状态不变，原正文／`.bak` hash 不变。
6. **导出故障：** 在途保存、组合态、读取缺失／失败、写入失败、快速双击、导出与删除／移动竞争、未完成迁移及遗留临时文件均拒绝或串行，不能导出旧稿／残稿；失败无误报，重试可成功。
7. **既有功能回归：** 保留实际 widget 握柄双向跨卷拖放、折叠目标、编号、文本／备份字节、删除不复活、摘要失败与恢复故障注入。不能把调用控制器冒充新的 widget 菜单或拖动验收。
8. **发布：** 先 TDD 的有效 RED，再最小实现与回归；运行 fresh format、analyze、全测及 Windows x64 release，提供新版本完整 ZIP，不覆盖旧 0.2／0.3 包。外目录解压逐文件核验，以全新 NWW_DATA_ROOT 合成数据验收真实菜单、设置、宽窄动画、三级导出、保存／重启；只关闭本轮自有进程。
9. **记录与保护：** 实施前为当前源码做新的不覆盖快照并记录 git status／分支；不把原未跟踪 M1 当本轮新增，不覆盖旧快照／发布包／作者作品或实例。更新本文、[README](<README.md>) 和 [环境记录](<docs/env.md>) 的新结果与 hash；107 项和旧 release 只作历史。继续禁止子智能体／队友／并行代理、reset／clean、合并与推送。
10. **未验边界：** widget 注入 composing 不等于真实微软／搜狗候选窗；中文长句、撤销重做、组合态跨响应式断点、150%／200%／多屏及其他平台仍须如实标明人工边界，不能因为测试通过宣称全部 IME／DPI 已验。

### 20.10 当前阶段与下一步

- 已完成源码和历史规格核对、浏览器 B 方案选择、四项歧义确认，以及界面／数据保护的分段确认。浏览器原型不读写作品，不属于已交付的 Flutter 实现。
- 已在本会话亲自回读本节，逐项核对原请求、四项选择、界面／数据确认与设置实际范围；检查了旧非空／整书排除规则的覆盖关系、窄屏偏好、显示与保存的区分、无残缺导出及 IME 草稿边界。未调用代理审查，也未将原型通过当作 Flutter 回归通过。
- 作者已在本会话书面复核问题中明确选择“确认，开始实施”。本节转为本轮已批准规格，接续 §21 实施计划；不再重复索取同一设计批准。开始计划时尚未修改本轮产品代码，新的 107 项基线不是本轮完成证据；发布仍须执行 §21 的全部新门禁。
- 只沿用当前新任务目标；§19 已完成的 0.3.0 交付不重做，不将本轮确认当作本轮功能已完成。

---

## 21. 无边框写作工作区与安全三级导出 Implementation Plan

> **执行方式：** REQUIRED SUB-SKILL：`executing-plans`，本会话逐任务亲自执行；作者明确禁止子智能体／队友／并行代理，因此不使用 subagent-driven-development，也不另建 worktree 或计划文件。每批结束检查 diff 和测试并记录结果，继续既定实施，不再重复申请设计批准。步骤中的复核不等于完成声明。

**Goal：** 实现已批准 §20 的平面菜单目录、真实空标题、菜单式设置、侧栏底部入口与过渡，以及保持作者原稿安全的章／卷／书 TXT 导出。

**Architecture：** 保留现有 EditorController 导航／保存队列及 §17 迁移事务；新增严格只读导出快照与全应用导出协调器，不借导出打开章节或重建索引。外观复用共享无边框形状和 Fluent UI 自带 Flyout 子选单；目录保持单一长期存活实例，宽窄只改变承载位置及可见性，避免动画或响应式切换销毁内联输入。设置仍写现有 settings.json，失败可观测且可重试。

**Tech Stack：** Flutter 3.47.7／Dart 3.13.5、fluent_ui 4.17.0、material_ui 1.8.0、既有 dart:io JSON／TXT／原子写，不加运行时依赖。命令通过本机 PowerShell 调用现有 SDK。

### 21.1 起点、保护与执行约定

- 分支 `ui/writing-workspace`，HEAD `faa3f88f8080e784eb66f81a691ef159dd171ea1`；不是 main。开始时已有修改的本文／README 及大批未跟踪 M1 源码均保留，不据 git untracked 统计本轮新增。
- 新快照 `.devdata/pre-20-20261027-143823`：87 个当前可编辑源文件／资产／配置逐文件 SHA256 一致；排除生成的 windows/flutter/ephemeral、缓存、build 和 .devdata，不是较早 ui-baseline。清单在快照内 snapshot-manifest.json，定位记录 `.devdata/section20/source-snapshot.json`。旧 0.2／0.3 ZIP hash 已记录 `.devdata/section20/protected-packages.json`。
- 新鲜起点证据 `.devdata/section20/toolchain.log` 和 `.devdata/section20/baseline-tests.log`：Flutter 3.47.7／Dart 3.13.5，`00:24 +107: All tests passed!`，退出码 0。这是改动前基线，不是本轮完工回归。开始时未发现正在运行的 no_white_writer.exe；仍不触碰旧外目录或随后出现的作者实例。
- 只使用 read／edit／write 及本机可用 PowerShell。现有主机脚本签名策略需按既有方式对子进程使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`；不改系统策略、不设 sandbox_permissions，不绕过 DSH 沙箱拒绝。
- 每个功能先写行为测试，确认有效断言 RED，再最小实现、GREEN、局部回归。编译错误、测试辅助代码错误、错误坐标不计功能 RED。新类型先按所列接口建立可编译边界，继续以具体缺失行为断言取得 RED，不把空实现交付。
- 本轮不执行 git add／commit／merge／push／reset／clean；以保护快照、定点 diff 和任务记录代替技能默认的频繁提交。所有新增测试使用独立临时目录，不写真实作品。
- 计划中的文件名／类型／签名为实施契约；若实际代码需要调整，先在本节更新原因和相应测试，而非悄悄改变规格。以下每个勾选步骤为一个小检查点；一个测试族按列出的 case 逐个 RED→GREEN，不将全部实现后补测试。

### 21.2 文件职责与依赖顺序

| 路径 | 责任与改动边界 |
| --- | --- |
| lib/core/chapter_numbering.dart | 保留编号规则，只统一卷／章空值显示；编号空章不加尾空格。 |
| lib/state/editor_controller.dart | 放开修剪后的空章名；新增只读导出的保存／导航门禁；退出故障逃生与常规导出分名。 |
| lib/state/library_controller.dart | 放开空卷／章名；新增导出保留锁和结构写入计数，不改跨卷提交判据。 |
| lib/core/storage/export_snapshot_store.dart（新） | 严格读取现有索引和正文，拒绝缺失／坏 UTF8／未完成迁移／临时文件，不恢复或重建。 |
| lib/state/export_controller.dart（新） | 稳定 ID 请求、排他、等待 flush、固定快照、全部读取后写、释放与重试。 |
| lib/core/storage/export_service.dart | 保留 TXT 格式和布局；唯一名称也避开已有临时文件，失败只清本次新建临时物。 |
| lib/app_context.dart、lib/app.dart | 装配唯一导出协调器、UI 离开草稿守卫；窗口标题统一空值显示，退出不截断正在执行的导出。 |
| lib/ui/menu_surface.dart（新）、lib/ui/context_menu.dart | 共享无边框形状／行样式，保留焦点提示、键盘、定位、返回触发焦点。 |
| lib/ui/settings_menu.dart（新）、lib/state/settings_controller.dart | 菜单＋子选单、路径草稿及关闭门禁；设置串行快照保存和可见错误／重试。 |
| lib/ui/sidebar_transition.dart（新）、lib/ui/editor_page.dart | 约 200ms 可反向过渡、减少动画、隐藏输入隔离；单一目录载体和固定底部按钮。 |
| lib/ui/chapter_pane.dart、lib/ui/shelf_page.dart | 平面行、空标题、稳定 ID 的三级导出菜单、书架设置弹出入口。 |
| lib/ui/settings_page.dart、lib/main.dart | 去掉正常与调试的旧设置页导航；调试入口改为书架上打开同一设置菜单。 |
| test/empty_titles_test.dart、test/export_snapshot_test.dart、test/export_flow_test.dart（新） | 纯显示／持久化／严格读取／互斥和故障测试。 |
| test/menu_revision_test.dart、test/settings_menu_test.dart、test/sidebar_transition_test.dart、test/export_menu_test.dart（新） | 实际点击、右键、键盘、动画帧、子级、菜单导出；不以控制器代替交互。 |
| test/support/app_harness.dart、test/support/widget_harness.dart | 仅增加注入 seam 和清理新协调器，保留真实 IO 与资源回收。 |
| test/catalog_forms_test.dart、test/numbering_surfaces_test.dart、test/monochrome_test.dart | 将已被 §20 明确替代的“空名保留／设置页／旧导出入口”断言改为新行为，其余回归不删。 |
| pubspec.yaml、README.md、docs/env.md、本文 | 0.4.0+4 新版本、fresh 证据、ZIP hash、人工边界。 |

执行依赖：任务 A → B → C → D → E → F → G → H。A/B/C 为第一批数据与导出边界；D/E 为第二批菜单及设置；F/G 为第三批承载和真实动作；H 为发布。每批保留具体 RED／GREEN 日志，不以上一批或 0.3 结果代替。

### 21.3 任务 A：真实空标题与统一显示（§20.4）

**Files：** 修改 lib/core/chapter_numbering.dart、lib/state/editor_controller.dart、lib/state/library_controller.dart、lib/ui/chapter_pane.dart、lib/app.dart；新增 test/empty_titles_test.dart；修改 test/catalog_forms_test.dart、test/numbering_surfaces_test.dart。

- [x] A1 写可编译的显示 RED：空章无编号显示占位，有编号只显示编号；旧实现会得到空串或尾空格。测试主体：

```dart
test('空章显示不污染原名且编号后没有多余空格', () {
  final c = ChapterMeta(id: 'c', title: '', order: 0);
  final v = Volume(id: 'v', title: '', order: 0, chapters: [c]);
  expect(displayChapterTitle(v, c), '未命名章节');
  v.numbering = const ChapterNumbering(enabled: true);
  expect(displayChapterTitle(v, c), '第1章');
  expect(c.title, '');
  expect(v.title, '');
});
```

运行 `& 'C:/Users/userSigma/develop/flutter/bin/flutter.bat' test test/empty_titles_test.dart --reporter expanded`，预期上述 expect 失败而非编译失败；保存 A-red.log。

- [x] A2 用以下完整显示函数替换旧拼接，所有目录／窗口／拖动反馈／导出调用同一来源；占位着色由 UI 根据原串空值判断，不写模型。

```dart
String displayVolumeTitle(Volume volume) =>
    volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim();

String displayChapterTitle(Volume volume, ChapterMeta chapter,
    {String? rawTitle}) {
  final title = (rawTitle ?? chapter.title).trim();
  if (!volume.numbering.enabled) {
    return title.isEmpty ? '未命名章节' : title;
  }
  final index = volume.chapters.indexWhere((c) => c.id == chapter.id);
  final label = volume.numbering.label(index);
  return title.isEmpty ? label : '$label $title';
}
```

- [x] A3 先扩充现有内联／编辑测试为 RED，再删除非空拦截：EditorController.saveNow 只在 `normalized != _title.text` 时修剪，`restored = normalized`，不以 `_savedTitle` 复原空串；LibraryController.renameVolume／renameChapter 只在 `name == oldTitle` 时跳过；ChapterPane._commitName 删除空值取消分支；章名对话框仅 `name != null` 才提交，不能用 isNotEmpty。保留取消为 null、组合态门禁、失败草稿和原事务。个人自检补充：现有章名对话框先 pop 再异步改名会丢失非当前章失败草稿；先新增该真实点击故障测试，再将 `_NameDialog` 改为可 await 的保存回调，只有成功才 pop，失败保留空输入与错误，取消仍不写盘。

```dart
test('清空章名能落盘并原样回读', () async {
  final h = await createHarness();
  addTearDown(h.dispose);
  final s = await h.app.library.createBook('空名');
  final b = await h.app.library.openBook(s);
  final v = b.volumes.first;
  await h.app.editor.open(inBook: b, inVolume: v,
      inChapter: v.chapters.first);
  h.app.editor.title.text = '   ';
  expect(await h.app.editor.flush(), isTrue);
  expect(h.app.editor.title.text, '');
  final disk = await h.app.bookStore.load(s);
  expect(disk.volumes.first.chapters.first.title, '');
  await h.app.library.renameVolume(b, v, '   ');
  expect((await h.app.bookStore.load(s)).volumes.first.title, '');
});
```

测试导入 flutter_test、models、chapter_numbering 及 support/app_harness.dart；widget 文件复用 support/widget_harness.dart，不复制业务实现。

- [x] A4 在真实 TextBox／TextField 上覆盖：回车空值、失焦空值、Escape 保留原名、composing 不提交、故障 writer 保留空草稿且重试成功、JSON 显式空值与缺字段分开、新建默认名不变。复核正文／备份原字节及 ID 不变，不能删除这些断言。
- [x] A5 定向运行 `flutter.bat test test/empty_titles_test.dart test/catalog_forms_test.dart test/numbering_surfaces_test.dart`，预期全部 PASS；人工 diff 仅非空门禁和显示改变，保存 A-green.log。已取到有效 RED 才勾完成。

A 实际证据（2026-10-27）：`A-display-red.log` 2 项显示断言 RED；`A-persistence-red.log` 5 项持久化／内联 RED；`A-menu-red.log` 4 项真实菜单／占位／失败草稿 RED。补充真实输入动作后，`A-ime-done-red.log` 证明 Flutter 默认 onEditingComplete 会在 onSubmitted 前清掉 composing；已显式保留组合态。FluentDialogRoute 默认 Escape 的直接 pop 另由草稿内部 DismissIntent 接管，未完成组词／在途保存不能绕过守卫。`A-final-green.log` 为本次格式化后的 33 项 PASS（额外包含 editor_save_test.dart），覆盖当前及非当前空名失败重试、回车／Escape／取消、JSON 显式空与缺字段、新建默认名、原正文／备份字节。`A-menu-green.log` 的编译接线失败与早期未成功的 Escape 诊断日志不计为有效 RED／GREEN。A2 的显示函数、目录／窗口／拖动反馈已接入；新的导出调用点在 C／G 集成后再勾选全调用面。

### 21.4 任务 B：严格只读导出快照与失败原子清理（§20.6）

**Files：** 新增 lib/core/storage/export_snapshot_store.dart、test/export_snapshot_test.dart；修改 lib/core/storage/export_service.dart。不要改变 ChapterStore.readText 的旧恢复语义来冒充严格读取。

- [x] B1 先针对现有 ExportService 写“writer 创建本次 .tmp 后抛错，失败不残留临时物／最终物，已有导出不变”的有效 RED；故障 writer 的行为如下，测试确认原实现留下 `.tmp` 后再修。

```dart
class PartialExportWriter extends AtomicFileWriter {
  @override
  Future<void> writeAtomically(File target, String content) async {
    await target.parent.create(recursive: true);
    await File('${target.path}.tmp').writeAsString('partial', flush: true);
    throw const FileSystemException('export injected write failure');
  }
}
```

运行 `flutter.bat test test/export_snapshot_test.dart --reporter expanded`，只有预期的残留断言失败才计 B-red。

- [x] B2 定义严格快照读取器，接口固定为 `ExportSnapshotStore(AppPaths paths, {Future<List<int>> Function(File)? readBytes})`、`Future<BookIndex> readBook(String bookId)`、`Future<String> readChapter(String bookId, String volumeId, String chapterId)`。readBytes 默认 File.readAsBytes，可注入延迟／读取失败；不通过 ChapterStore.readText 的 null 或 allowMalformed 路径。核心读取实现：

```dart
Future<String> readChapter(String bookId, String volumeId,
    String chapterId) async {
  checkId(bookId);
  checkId(volumeId);
  checkId(chapterId);
  await checkBookConflicts(bookId);
  final file = paths.chapterFile(bookId, volumeId, chapterId);
  for (final suffix in ['.tmp', '.bak.tmp']) {
    if (await FileSystemEntity.type('${file.path}$suffix',
        followLinks: false) != FileSystemEntityType.notFound) {
      throw FileSystemException('正文存在未解决临时文件', '${file.path}$suffix');
    }
  }
  if (!await file.exists()) {
    throw FileSystemException('正文缺失，已停止导出', file.path);
  }
  final backup = File('${file.path}.bak');
  if (await backup.exists() &&
      (await backup.lastModified()).isAfter(await file.lastModified())) {
    throw FileSystemException('备份较新，请先完成恢复再导出', backup.path);
  }
  var text = utf8.decode(await readBytes(file), allowMalformed: false);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

void checkId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
    throw const FormatException('作品目录 ID 无效，已停止导出');
  }
}
```

`paths` 与 `readBytes` 是构造器注入字段。`checkBookConflicts(String bookId)` 检查书目录内 `.chapter-move.json`、`.chapter-move.json.tmp` 和 `book.json.tmp`，任一存在均抛带路径的 FileSystemException；不删除／恢复。`readBook` 先检查这些冲突，严格 UTF8 + jsonDecode，要求顶层 Map、id 等于请求、volumes 为 List、各卷 chapters 为 List，卷 ID／书内章 ID 唯一且安全；再 BookIndex.fromJson，按数组顺序返回，不排序、不写盘。缺标题仍按既有模型兼容规则，显式空串不得填默认值。编号启用时验证规则及章数。

- [x] B3 对该接口逐个新增行为测试：缺正文、坏 UTF8、读取异常、临时正文、较新备份、损坏迁移记录、索引临时物、坏 JSON、ID 不符／重复／路径穿越均抛错；合法空正文返回空字符串，BOM／CRLF 规范化仅发生在导出副本。每个拒绝 case 前后比较原索引／正文／备份／日志字节，确认没有恢复或重建调用。
- [x] B4 修改 ExportService 的唯一名称查找同时避开 `<candidate>.tmp`。写前记录目标与临时物均不存在，写失败只删除本次可确认新建的 tmp；绝不清理预先存在文件或源作品。仍用 AtomicFileWriter 完成写／flush／rename。若故障发生于提交后，先核实目标完整字节等于本次 UTF8 预期再认定已提交；不能把部分文件当成功。一次应用内并发在任务 C 排他，不增跨进程协议。
- [x] B5 导出章节／卷／书服务测试保留既有分隔符、目录布局、末尾换行和自定义根；增加已有最终／已有 tmp／非法文件名与空名后备／失败清理／再次成功。运行 `flutter.bat test test/export_snapshot_test.dart test/storage_test.dart`；若实际既有存储测试文件名不同，先 glob 确认并在本节记录替换，不执行不存在路径。预期 PASS，记录 B-green。

B 实际证据（2026-10-27）：`B-service-contract-red.log` 4 项有效 RED（本次 tmp 残留、预存 tmp 冲突、提交后异常、伪成功残片）；`B-snapshot-red-confirmed.log` 20 项有效行为 RED（已排除早期两个测试夹具类型错误）。严格读取不经恢复／重建、无源文件／日志写入，按数组顺序验证 ID／重复所有权／启用规则并严格解码；拒绝迁移／临时物／较新备份及非普通节点。`B-final-green.log` 为格式化后 51 项 PASS，包含既有存储回归、原字节不变、实际卷／书 TXT 分隔符与空卷头、文件名清洗／空名后备／唯一命名、三种范围失败清理及重试。应用内排他和菜单入口仍由 C／G 接入，尚不视为整轮验收。

### 21.5 任务 C：全应用导出协调与保存保护（§20.6–20.7）

**Files：** 新增 lib/state/export_controller.dart、test/export_flow_test.dart；修改 lib/app_context.dart、lib/state/editor_controller.dart、lib/state/library_controller.dart、lib/state/workspace_controller.dart、lib/app.dart、test/support/app_harness.dart。

- [x] C1 明确新请求类型，UI 只传 ID，不传会被排序改变的数组下标：

```dart
enum ExportScope { chapter, volume, book }

class ExportTarget {
  const ExportTarget.chapter(this.bookId, this.volumeId, this.chapterId)
      : scope = ExportScope.chapter;
  const ExportTarget.volume(this.bookId, this.volumeId)
      : scope = ExportScope.volume, chapterId = null;
  const ExportTarget.book(this.bookId)
      : scope = ExportScope.book, volumeId = null, chapterId = null;
  final ExportScope scope;
  final String bookId;
  final String? volumeId;
  final String? chapterId;
}
```

新增 ExportController，构造器显式接受 ExportSnapshotStore reader、EditorController editor、LibraryController library、SettingsController settings、ExportService service；公开 `bool get busy`、`Future<File?> export(ExportTarget target)`。AppContext 以惰性 getter `exporter` 装配唯一实例，测试可注入 reader／service，不增加全局单例。

- [x] C2 先用现有编辑／IO 门禁写有效 RED：body／title composing 时不能开始新常规导出；保存失败不能把内存逃生导出当常规成功。新增 `EditorController.runExport(Future<void> Function() action)` 复用 `_navigate`，组合态／blocked 拒绝，设置 structuralBusy 后 await flush，再执行 action，finally 解锁；不在结束时重绑或清理当前章。

```dart
Future<bool> runExport(Future<void> Function() action) => _navigate(() async {
  if (structuralBusy || _isComposing) {
    noticeMessage = '请先完成输入法组词，再导出。';
    _notify();
    return false;
  }
  structuralBusy = true;
  _notify();
  try {
    if (!await flush()) return false;
    await action();
    return true;
  } finally {
    structuralBusy = false;
    _notify();
  }
});
```

现有退出保存失败的内存逃生单独保留为 `exportEmergencyDraft()`，仅由 app.dart 的“导出到文档后退出”调用；不得通过三个正常菜单触发或作为常规导出通过证据。旧 exportCurrentChapter 调用的普通测试迁往 exporter；不删除故障逃生。紧急导出也用统一空名显示，不把旧 savedTitle 填回作者空标题。

- [x] C3 先注入延迟结构写／导出读，证明没有混合快照，再实现 LibraryController 的导出保留锁：`bool get exporting`、`Future<void> beginExport()`、`void endExport()`。新增 `_mutate<T>(Future<T> Function() action)`，在入口拒绝 exporting，跟踪活动结构写入数，finally 归零时唤醒等待者。beginExport 先保留锁以拒绝后来结构请求，再 await 已进入的结构写结束。createBook、openBook（可能恢复）、updateBookDetails、saveBook、deleteBook、appendChapter、appendVolume、setNumbering、relocateChapter、reorderVolume、deleteChapter、deleteVolume、renameVolume、renameChapter 的最外层实际 IO 用 `_mutate` 包住，不改变方法主体事务；moveChapter／moveVolume 不重复包其内部委托，renameBook 的读取阶段和 updateBookDetails 分段走同一边界。noteChapterSaved 仍允许既有 flush 更新摘要，防止锁内保存死锁。
- [x] C4 固定锁顺序为 **Editor 导航／flush → Library 导出保留锁 → 只读快照 → 输出**，不能反向先占 Library 再等待 Editor。export() 同步设 busy 拒绝双击，await editor.runExport，action 内 beginExport，校验 blockedBooks，严格 readBook；按目标 ID 找卷／章，先读全部目标正文，最后只调用一次 service 对应方法。空目标返回 null 并由 UI 提示；finally 对实际持有的锁 endExport、清 busy、通知，异常保持原错误和可重试。页面卸载不取消半截写入，也不向已卸载 widget 通知。
- [x] C5 新接口具备后逐例补测试取得缺失行为 RED：非当前章不调用 editor.open；卷／书按数组当前顺序、各自编号；空卷保留卷头，所有无章则 null；空名／空正文／自定义根／同名唯一；全部读完前 service 调用数为 0。保存延迟／失败、第二次导出、删除／改名／移动竞争、读／写异常、迁移／临时物拒绝后锁均释放，重试正确；前后 current IDs、展开偏好、lastOpenedChapterId、源正文与 .bak bytes 相等。
- [x] C6 WorkspaceController.editingLocked 和 `_exclusive` 纳入 library.exporting；Shelf 入口纳入 exporter.busy。AppContext 增加按 token 注册的 UI 草稿离开守卫（`Object registerUiGuard(Future<bool> Function() guard)`／`void removeUiGuard(Object token)`／`Future<bool> flushUiGuards()`）；app.dart 退出先执行这些守卫，导出未结束时取消本次关闭并提示，不能留下半截操作。EditorPage 注册内联 draft.flush，设置路径守卫在任务 E 注册；不强清 composing。
- [x] C7 运行 `flutter.bat test test/export_flow_test.dart test/export_snapshot_test.dart test/editor_save_test.dart test/workspace_test.dart`，预期 PASS；已通过 glob 核对现有文件名，编辑保存回归实际为 test/editor_save_test.dart。记录 C-green 及“正常菜单／故障逃生”分别验证结果，亲自检查没有改 chapter_move_store.dart 的提交／恢复判据。

C 实际证据：保存／组合态 4 项、结构竞争 19 项及后补 load／展开写 2 项、卷／书范围 3 项、退出／工作区 4 项、书架忙碌 3 项和退出 IME 2 项均有行为 RED 后 GREEN。C-exit-notice-red.log 的缺失提示已用不依赖 Navigator Overlay 的可关闭 InfoBar action 修正；旧 onClose Tooltip 导致的失败尝试不算通过。新增三种范围写失败、blocked／journal／临时物重试、全部源文件 bytes 比较。C-complete-final-tests.log：`00:25 +207: All tests passed!`，覆盖原生退出请求和实际故障逃生对话框；这是 C 阶段新鲜结果，不是最终交付门禁。chapter_move_store.dart 对本轮保护快照 SHA256 均为 `57C8AE5FE0B62A0BF307BEE48994200A04E85B431EFDC44B29A7DE021CB2627B`，未改提交／恢复判据。设置路径守卫仍在 E 接入。

### 21.6 任务 D：共享无边框外观与平面目录（§20.2）

**Files：** 新增 lib/ui/menu_surface.dart、test/menu_revision_test.dart；修改 lib/ui/context_menu.dart、lib/ui/chapter_pane.dart。

- [x] D1 真实右键打开书架卡片菜单，检查容器与菜单行默认、悬停、禁用、焦点各状态；原 container.border 和默认 Button shape 描边取得 RED。实际 pointer kind mouse 的 `tester.startGesture(..., buttons: kSecondaryMouseButton)` 松开后等待菜单，不直接调用 showContextMenu 冒充业务入口。
- [x] D2 新共享形状和行样式采用 Fluent UI 已核对的 ButtonStyle.shape 字段；不设置虚构 border 属性。实现如下，焦点由既有 FocusBorder 保留：

```dart
const borderlessMenuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(4)),
  side: BorderSide.none,
);

ButtonStyle borderlessRowStyle({Color? background, Color? foreground}) =>
    ButtonStyle(
      shape: const WidgetStatePropertyAll(borderlessMenuShape),
      backgroundColor: background == null
          ? null : WidgetStatePropertyAll(background),
      foregroundColor: foreground == null
          ? null : WidgetStatePropertyAll(foreground),
    );
```

共享菜单浮层保留原阴影／颜色但外框不画线；ContextMenu 继续已有指针定位与可滚动约束。显式跳过禁用项、空 actions 安全退出、关闭后恢复调用前焦点；键盘 Tab 不穿到背景，Enter／Esc／方向键可用。

- [x] D3 用真实卷章 UI 增加外观 RED，再移除 `_volume` 的常态 Border.all，章节 Button 用 borderlessRowStyle；卷头浅底紧凑行、章名左对齐、缩进和字数保留；当前章仍朱砂＋浅底。空原名用 mutedTextColor，编号空章只显示编号。拖动临时边界、握柄、落点、输入框和焦点不是常态卡片边框，不能一并删。
- [x] D4 浅／深、1280／900 分别验证正常／选中／禁用／焦点；真实 ⋯、右键、Shift+F10、方向键跳禁用、Enter、Esc、Tab、长菜单滚动和四角避让。菜单打开后改变排序仍按原 ID 操作；移除外框不能导致点击穿透。运行 `flutter.bat test test/menu_revision_test.dart test/catalog_drag_test.dart` 取得 D-green，回归必须继续是真实拖动。

D 实际证据（2026-10-27）：`D-red.log` 为 10 项真实外观 RED（书架右键与卷／章菜单容器、项目描边、按钮默认 shape 在 1280／900 浅深下均有可见边框）。`lib/ui/menu_surface.dart` 导出 `borderlessMenuShape`（`RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)), side: BorderSide.none)`）与 `borderlessRowStyle({Color? background, Color? foreground})`（只用已核对的 `ButtonStyle.shape`／`backgroundColor`／`foregroundColor`，焦点仍由 Fluent 既有 `FocusBorder` 呈现）；`lib/ui/context_menu.dart` 与 `lib/ui/chapter_pane.dart` 的卷容器、章行、菜单行改用共享形状，拖动临时边界／握柄／落点／输入框边框未删。`D-format.log` 格式化 4 文件；`D-final-green.log` 为 `menu_revision_test.dart`＋真实 `catalog_drag_test.dart` 的 37 项 PASS（含 Tab 可达握柄、方向键排序、Ctrl+方向键跨卷），证明移除外框未造成点击穿透且拖动回归仍是真实手势。

### 21.7 任务 E：设置菜单层级、路径草稿和可观测保存（§20.5）

**Files：** 新增 lib/ui/settings_menu.dart、test/settings_menu_test.dart；修改 lib/state/settings_controller.dart、lib/ui/shelf_page.dart、lib/ui/editor_page.dart、lib/main.dart、lib/ui/settings_page.dart、test/monochrome_test.dart。

- [x] E1 从真实旧设置按钮点击后断言 `settings-menu` 存在且不出现旧设置页面，先取得行为 RED；不先替换导航再补测试。菜单使用现有 fluent_ui MenuFlyout／MenuFlyoutSubItem／MenuFlyoutItemBuilder，不新增菜单依赖。主菜单 shape 为 borderlessMenuShape，子级继承形状；主题选项的完整构造模式：

```dart
MenuFlyoutSubItem themeSubmenu(AppContext app) => MenuFlyoutSubItem(
  text: const Text('主题'),
  items: (_) => [
    for (final option in const [
      ('system', '跟随系统'), ('light', '浅色（纯白）'), ('dark', '深色（纯黑）')
    ])
      RadioMenuFlyoutItem<String>(
        text: Text(option.$2), value: option.$1,
        groupValue: app.settings.themeMode,
        closeAfterClick: false,
        onChanged: app.settings.setThemeMode,
      ),
  ],
);
```

已对照 fluent_ui 4.17.0 的 menu_flyout.dart:436–460、524–546：RadioMenuFlyoutItem 泛型及 String 回调有效，MenuFlyoutSubItem.items 必须是构造子项的回调而非 List。主题、字号 Slider 14–28／14 divisions、行距 1.4–2.4／10 divisions、autoIndent／blankLineBetween、导出目录／默认／打开、数据／日志／关于均有子项或紧凑面板。

- [x] E2 SettingsController 先加注入 writer 失败测试 RED：400ms 防抖出错不能成为未处理异步异常，flush 必须仍抛错并保留可见 saveError，重试真正写盘后才清除。flush 采用深拷贝 settings 快照和失败不毒化的串行 Future 尾链；相同在途 JSON 共用 Future，避免 timer＋显式保存重复写同一快照；新设置排在旧快照后，旧写不能覆盖新值。dispose 取消 timer 且不对 disposed notifier 通知。

```dart
void _changed() {
  notifyListeners();
  _timer?.cancel();
  _timer = Timer(const Duration(milliseconds: 400), () {
    unawaited(flush().catchError((Object _) {}));
  });
}
```

此 catch 只防 timer 未处理异常；flush 自身必须记录 saveError、通知 UI 并向显式调用者 rethrow。保存成功判据是 await SettingsStore.save 完成，不是 setThemeMode 已更新内存。

- [x] E3 设置会话持有单一 TextEditingController／FocusNode 和原始路径基线；子级返回可保留未提交草稿，IME 未结束不得卸载输入。根菜单外点、Esc、显式关闭与 AppContext 退出守卫经过同一检查：组合中拒绝并保留；有未保存路径则确认放弃或继续编辑，不能无提示丢弃。路径 save trim 后空值传 null；失败保持输入和错误，成功 await settings.flush 才更新基线。目录打开 try／catch 显示失败，不把返回 void 当成功布尔。
- [x] E4 FlyoutController.showFlyout 使用 `placementMode:auto`／底部向上、root bounds 和 margin；root 的 dismissWithEsc=false，barrierRecognizer 走草稿检查；子级 Escape 先关闭子级。捕获原焦点并关闭后恢复；必要的 PopScope 防止根 route 默认 maybePop 绕过路径 guard。路径输入横向滚动，所有子级受视口约束。设置只管理设置，不直接修改作品。
- [x] E5 书架和写作设置按钮均改为 FlyoutTarget 触发同一 SettingsMenu；main.dart 原 NWW_DEBUG_SETTINGS 路径改为 ShelfPage 上自动弹同一菜单。删除 SettingsPage 产品路由与实现或只保留不可导航兼容导出，正常／调试不得仍有旧页面。原 monochrome 测试改为真正设置菜单并保留字体、颜色和纯底断言，不删除关于版本和范围断言。
- [x] E6 测试逐项点击子级调整、原数值范围、selected 提示、主题即时更新、重建／重启读回；根／子级 Escape、外部点击不穿透、路径输入／组合态／失败／重试／放弃确认、打开目录失败、900 窄窗及放大文本边界。运行 `flutter.bat test test/settings_menu_test.dart test/monochrome_test.dart` 记录 E-green。

E 实际证据（2026-10-27）：`E-red-confirmed.log` 为 4 项有效 RED（书架／编辑器真实设置入口仍进入旧页面、无 `settings-menu`、旧页面无主题子选单）。`lib/ui/settings_menu.dart` 用既有 `FlyoutTarget`＋`FlyoutController.showFlyout`＋`MenuFlyout`／`MenuFlyoutSubItem`／`RadioMenuFlyoutItem`／`ToggleMenuFlyoutItem` 承载全部原设置（系统／浅色（纯白）／深色（纯黑）、字号 14–28、行距 1.4–2.4、自动首行缩进、段间空行、导出目录、打开数据／日志目录、关于 0.3.0），主菜单与子选单共用 `borderlessMenuShape` 且保留 FocusBorder；root `dismissWithEsc=false`、barrier 走草稿检查、子级 Esc 先关子级，`AppContext.registerUiGuard`／`flushUiGuards` 与编辑器 `_paneDraft.flush()` 在打开前完成提交；路径输入 `onEditingComplete: () {}` 保留组合态。`lib/ui/settings_page.dart` 已删除，`lib/main.dart` 的 `NWW_DEV_PAGE=settings` 分支改为书架自动弹同一菜单；`monochrome_test.dart` 迁移到真实菜单并保留纯底／字体／关于版本断言。`E-analyze-4.log` 为 `No issues found! (ran in 9.3s)`，`E-format-5.log` 0 文件变化；`E-green-7.log` 为 `settings_menu_test.dart`＋`monochrome_test.dart` 的 21 项 PASS，`E-full-green-3.log` 为全量 `00:43 +237: All tests passed!`。过程中曾用 `Get-Content` 默认 ANSI 解码重写 `lib/ui/settings_menu.dart` 造成中文乱码，已用 GBK 逆变换恢复并逐串修复（`format` 0 变化、`analyze` 0 问题、上述测试全绿），此后源码文本一律经 read／edit／write 或 .NET UTF-8 API 读写。

### 21.8 任务 F：单一目录载体、底部按钮与可反向动画（§20.3）

**Files：** 新增 lib/ui/sidebar_transition.dart、test/sidebar_transition_test.dart；修改 lib/ui/editor_page.dart、lib/ui/chapter_pane.dart、test/catalog_revision_test.dart、test/catalog_forms_test.dart。

- [x] F1 先写真实折叠按钮测试 RED：点击后 pump 100ms，宽度须严格位于 0 与原宽之间；当前无动画会立即成为 0。再测展开中反向、不留 84px、最终宽度、减少动画立即到位。测试不能只读 animation 属性。
- [x] F2 实现独立过渡 widget，不持有业务或 IO；完整最小构造如下：

```dart
class SidebarTransition extends StatelessWidget {
  const SidebarTransition({super.key, required this.expanded,
      required this.width, required this.child});
  final bool expanded;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: expanded ? 1 : 0, end: expanded ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 200),
    curve: Curves.easeInOutCubic,
    child: child,
    builder: (context, value, child) => ClipRect(
      child: SizedBox(
        width: width * value,
        child: OverflowBox(
          alignment: Alignment.centerLeft, minWidth: width, maxWidth: width,
          child: Offstage(
            offstage: value == 0,
            child: TickerMode(
              enabled: value != 0,
              child: IgnorePointer(
                ignoring: !expanded,
                child: ExcludeFocus(
                  excluding: !expanded,
                  child: ExcludeSemantics(
                    excluding: !expanded,
                    child: Opacity(opacity: value, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
```

每次 build 给新 Tween，Flutter 从当前值 retarget；不创建重复目录。若布局需要正文同步腾挪，使用同一 value 驱动正文 left inset，不启用两个独立时钟。初始值按持久化 expanded 直接取位，不在启动时无故播放。

- [x] F3 写作页改为同一 Stack 中长期存活的有 key 目录 host：宽屏占左侧 240／280；窄屏为受约束浮层，宽高不超视口、背景 barrier 隔离。ChapterPane／滚动与内联输入只保留一个实例，不在宽屏 Row 与新 Dialog 间复制或反复 dispose；模式切换只改位置／尺寸／可见性。组合态响应式切换不得销毁输入；若切换需要关闭浮层，先 await 同一草稿 guard，失败保持可编辑载体。
- [x] F4 固定 footer 在滚动区外，左 back-to-shelf、右 workspace-settings；移除顶栏同名按钮及旧导出按钮，顶栏保留 toggle-sidebar／窄屏 open-chapter-pane。点击折叠、返回、设置、窄屏关闭或 Escape 前检查 editor.isComposing、paneDraft.value 和工作区锁；await paneDraft.flush 与所需 editor.flush，失败不换载体。隐藏之初即隔离指针／焦点／语义，已聚焦 footer／目录的焦点移回可见展开按钮。
- [x] F5 宽屏全局 sidebarCollapsed 仍只由手动 toggle 更新；窄屏 _paneOpen 仅会话，不写宽屏偏好，选章／新建／拖放不自动关闭／展开。保留新章创建后“显式关目录才聚焦标题”的行为。全局设置菜单不能通过路径 dirty 关闭隐藏自己；窄屏返回真正回书架，普通 Escape 只关闭目录。
- [x] F6 真实 widget 测试覆盖 1280／1100／900、80／100／200ms 帧、快速反向、Tab 隐藏不可达、点击不穿透、减少动画、宽窄往返／重启偏好、滚动与正在输入内联草稿不重复实例／不丢失、三个 composing 区域、写盘失败重试。运行 `flutter.bat test test/sidebar_transition_test.dart test/catalog_revision_test.dart test/catalog_forms_test.dart test/catalog_drag_test.dart` 记录 F-green；拖放坐标由当前 widget geometry 得出。

#
**F 实际证据（2026-10-27）**

- RED：`.devdata/section20/F-red.log` 5 项行为失败（缺 sidebar-frame／键、顶栏仍导出本章、无过渡）。
- 实现：`lib/ui/sidebar_transition.dart`（`sidebarTransitionLength=200ms`、`SidebarValueBuilder`、`SidebarTransition`）与 `lib/ui/editor_page.dart` 单一 keyed 目录 host；`_carrierBlocked` 统一拒绝组词／内联草稿／工作区锁下的折叠、浮层开关、Escape 与返回。
- GREEN：`F-green-8.log` `00:14 +12: All tests passed!`（sidebar_transition 12 项）；`F6-green-2.log` `+25`（含 catalog_revision／catalog_forms／catalog_drag）；`F-full-green-3.log` `00:39 +249: All tests passed!`；`F-analyze-5.log` `No issues found!`；`F-format-7.log` 2 个文件格式化。
- 覆盖：1280／1100／900、80／100／200ms 帧、快速反向、终态 0／280、减少动画立即到位、隐藏目录 Offstage 不可 Tab 且点击穿透到正文、宽窄往返单一实例与内联草稿保留、折叠偏好落盘重读与初始帧直接取位、标题组词中拒绝折叠、内联草稿写盘失败拒绝折叠且草稿保留、修好后提交再折叠成功。
- 旧 `关闭目录` 对话框文案已随浮层改造移除；`catalog_revision_test.dart`／`catalog_drag_test.dart`／`catalog_forms_test.dart`／`ui_revision_test.dart` 改用真实 Escape／遮罩点击关闭，未放宽断言。
## 21.9 任务 G：稳定 ID 菜单导出与完整交互／故障回归（§20.9）

**Files：** 新增 test/export_menu_test.dart；修改 lib/ui/chapter_pane.dart、lib/ui/shelf_page.dart、lib/ui/editor_page.dart；必要时在 lib/ui 新增仅呈现结果的 export_notice.dart，不能在那里放文件 IO。

- [x] G1 点击真实章／卷／书 ⋯，先断言目标导出项存在取得 RED；分别加入 `MenuAction('export', '导出本章')`／`导出本卷`／`导出本书`。卷章先 await inline draft 提交，再以打开菜单时捕获的稳定 ID 创建 ExportTarget；书架捕获 book ID，不用 `_selected` 或排序后的下标。目标删除／移动后重新验证归属，不导出另一个对象。**状态注：菜单功能及回归已完成，但最初缺项先红缺证；过程偏差见 §22.1，不将勾选解释为历史先红已达成。**
- [x] G2 菜单调用 app.exporter.export；返回 null 只提示“暂无章节可导出”，异常显示具体问题并允许重试，File 结果才展示实际路径及打开文件夹动作。打开失败单独提示，不否认已经完成的导出。UI 回调检查 mounted，导出锁范围覆盖全部快照与输出。
- [x] G3 真实点击验证当前／非当前章、不同卷编号、空名、空正文、无章、混含空卷整书、用户目录、两次同名；对 TXT 解码逐字断言分隔／顺序／显示名称／末尾换行，不只判断存在。验证当前 editor 绑定、展开偏好、最后打开 ID 不变及原 TXT／BAK 字节不变；有待保存内容时先验证其正常 flush，再记录导出前基线，不能把正常保存误判为导出改原稿。
- [x] G4 在真实菜单路径触发 reader 延迟／失败、writer 部分 tmp／失败、快速双击、导出后立刻尝试删除／移动、IME 与在途保存，验证禁用或正确串行且锁释放。保留原真实跨卷拖放双向／折叠目标／长目录滚动／键盘握柄、迁移 8 阶段故障／重启恢复、摘要失败、删除不复活测试。
- [x] G5 对比保护快照逐文件 review lib 与测试差异，只算本轮真实新增／修改；grep 产品源码中的 SettingsPage／旧 exportCurrentChapter／顶栏导出／非空提示，逐项确认没有残留可达路径。运行所有新增测试和原完整测试，所有功能断言 PASS 后进入发布；记录缺陷与修复原因，不能把 harness 错误作产品通过或跳过测试。

### 21.10 任务 H：版本、fresh 全门禁、外目录发布与交付（§20.9.8–20.9.10）

**Files：** 修改 pubspec.yaml（0.4.0+4）、README.md、docs/env.md、本文；新产物 build/packages/no-white-writer-0.4.0-windows-x64.zip；仅本轮 .devdata/section20 辅助脚本和日志。

- [x] H1 将版本改为 `0.4.0+4` 并同步菜单关于；先加版本 widget 断言 RED 再修改，不沿用 0.3 字符串。只修复现有工程 junction 所需项；若构建确需修复，先读 tool/fix_plugin_symlinks.ps1 并按其既有安全方式调用，不改作者运行目录。
- [x] H2 依次执行 fresh 门禁，任一非零先诊断修复并重跑对应及全门禁；命令和目标结果：

```powershell
& 'C:/Users/userSigma/develop/flutter/bin/dart.bat' format lib test
& 'C:/Users/userSigma/develop/flutter/bin/dart.bat' format --output=none --set-exit-if-changed lib test
& 'C:/Users/userSigma/develop/flutter/bin/flutter.bat' analyze
& 'C:/Users/userSigma/develop/flutter/bin/flutter.bat' test --reporter expanded
& 'C:/Users/userSigma/develop/flutter/bin/flutter.bat' build windows --release
```

预期依次退出 0、format 检查 0 changed、No issues found、全测 All tests passed、release 成功；分别留 final-format、final-format-check、final-analyze、final-test、final-build 日志。测试数依据本轮实际输出，不预填数字。发布后如再改 production，重建重打包；只改测试也重跑相关门禁并解释产物对应关系。

- [x] H3 检查 release EXE FileVersion／ProductVersion 为 0.4.0+4；将完整 Release 目录全部相对文件（含 data／DLL／资源）打新 ZIP，目标已存在则停止或另建候选归档，不覆盖任何旧 ZIP。记录每个文件 SHA256、ZIP bytes／SHA256 与所有受保护旧 ZIP hash。
- [x] H4 解压到新的仓库外 Downloads 子目录，创建新的 NWW_DATA_ROOT 合成数据根；逐文件比较 release、ZIP 解压目录和清单，无遗漏／多余文件。启动前记录旧 PID，启动后只记录本轮 PID 与精确 EXE 路径；输入／关闭前复核所有权，绝不操作作者后来启动的实例。
- [x] H5 真正原生鼠标／键盘验证浅深无框右键／卷章菜单、底部返回／设置、菜单子级与持久化、空章／卷回读、宽窄展开／关闭动画、章／卷／书导出及顺序、保存／重启。导出前后 hash 校验 TXT／BAK，验证实际输出路径与所有文件；单独隔离根中的故障演练不污染作者数据。未能用原生观测证明的动画帧／候选窗／DPI 项不能声称实测通过。
- [x] H6 只以 WM_CLOSE 正常关闭本轮自有实例，验证保存完成／重启内容，最终核对拥有 PID 状态、旧 ZIP hash 和新产物逐文件 hash。所有后台 job 均收取终态；不对仍有用的任务重复启动。
- [x] H7 回写本文完成记录及 README／docs/env 新证据、hash、真实差异范围、故障／恢复结果；明确原生中文 IME 长句、撤销重做、候选窗跨响应式、150%／200%／多屏和其他平台未验边界。逐项检查 §20.9 覆盖后才把本节实际完成项勾选，present 新 ZIP，最后才能更新本轮 goal complete。

### 21.11 计划自检与执行记录

- 规格覆盖：20.2→D/G，20.3→F/H，20.4→A/G，20.5→E/H，20.6→B/C/G，20.7→A/C/E/F/G，20.8→21.2 的模块分工，20.9→A–H；旧迁移事务不在本轮重写。
- 个人自检约束：不留占位任务；类型以 ExportTarget／ExportController／ExportSnapshotStore／SidebarTransition 和现有模型为准；常规导出与旧关闭故障逃生不能混用；锁顺序一致；实际手势和文件断言不以直接控制器调用取代。计划的命令文件名与框架构造器在执行前据当前源码核对，发现偏差先修本文，不把编译错误当 RED。
- 开始记录（历史）：作者书面确认已取得；新快照与 107 基线完成；当时尚未修改本轮产品代码。依 A–H 执行，批内检查点如实追加，不自动把计划勾成已完成。
- H 原生验收追加（2026-10-27 21:10）：首轮 278 全测／analyze／release 与外目录三级导出、临时记录拒绝后重试、18 份原 TXT／BAK hash 检查已通过，但发现窄目录失去快捷键焦点时 Escape 可落到平台返回，原 PopScope 直接退出作品。`H-platform-back-red.log` 真实平台返回事件得到 EditorPage 数量 0（期望 1）；修复为浮层开启时先走同一 `_closePane` guard，显式左下返回仍回书架。`H-platform-back-green.log` 8 项通过，含加号新建后 Escape／标题焦点、平台返回、三个真实 IME 控件。此为 §21.8 F5 已确认行为的补漏，不改设计。首轮 ZIP（SHA256 `FFE96D220282DCCFBC9B18C5CF0E32166E6DFFF96FAECD121DCFDFF066B49515`）不交付，正常关闭自有 PID 后归档；重新全门禁、构建打包并重复最终原生验收。

## 22. §20／21 完成记录：0.4.0+4（2026-10-27）

### 22.1 实际覆盖与自审纠正

- 已落实作者确认的 B 完全隐藏侧栏（无窄轨）、目录内固定左下返回／右下设置、200ms 可逆动画及减少动画；保留单一 keyed 目录载体。卷头、章行、菜单去掉常态边框，保留悬停、选中和可访问键盘焦点轮廓。设置改为就地菜单＋子选单，移除旧设置页路由和顶栏导出。
- 卷章原名可为真正空字符串；灰色兜底不写回，开编号的空章只显示编号，新建默认名仍保留。章／卷／书菜单捕获稳定 ID，常规导出统一走保存排他协调及严格只读快照；单章只有正文，卷／书按当前数组顺序加卷章分隔，全部读完才创建输出。无章提示不产出，空正文有效，重复名称不覆盖。
- 审计不是沿用早期绿灯：修复真实焦点下打开菜单会先清除 IME composing、生命周期强制保存会提交候选、设置“重试”只刷旧内存而未保存路径草稿、footer 实际位于全页而非目录，以及平台返回降级误离开作品。有效 RED 分别见 [真实 IME](<.devdata/section20/G-focused-ime-confirmed-red.log>)、[生命周期](<.devdata/section20/G-lifecycle-ime-red.log>)、[设置重试](<.devdata/section20/E-path-audit-red-confirmed.log>)、[底栏矩形](<.devdata/section20/F-footer-focused-red.log>)、[平台返回](<.devdata/section20/H-platform-back-red.log>)；最终统一回归通过。旧 F 测试曾错误期待 footer 收起后仍显示，现已改成与侧栏一起隐藏并增加 1280／1100／900 实际矩形检查。
- 过程偏差如实保留：G1 最初没有取得“仅缺少导出菜单项”的有效先红记录；初期编译、夹具和过早等待失败不补称 TDD RED。后续真实菜单用例与上述新增缺陷均经行为失败／修复／回归，不能把这解释为补做了历史上的先红。删除用例必须实际确认删除并等待完整工作区事务；在途保存、失败清理、源字节、当前绑定、编号与输出逐字比较均已加强。
- 最终新增测试仍保留原真实跨卷握柄拖放、8 个迁移故障阶段／重启恢复、摘要失败和删除不复活覆盖。产品检索只在目录菜单发现“导出本章”，无旧 SettingsPage、exportCurrentChapter 或卷章非空提示可达路径。

### 22.2 新鲜全门禁与最终产物

- [格式检查](<.devdata/section20/final-format-check.log>)：71 个 Dart 文件、0 changed；[analyze](<.devdata/section20/final-analyze.log>)：No issues found，7.0s；[全测](<.devdata/section20/final-test.log#L301>)：280 项全部通过，45s；[Windows x64 release](<.devdata/section20/final-build.log>)：60.8s。最后一次生产修改为平台返回修复，此后未改产品源码，文档与验收脚本不进入 AOT。
- [完整 0.4.0 ZIP](<build/packages/no-white-writer-0.4.0-windows-x64.zip>)：25,474,636 字节，SHA256 `2E6A26154126BEBD3E8046C92D757FC679E098E131BEE152B8461EB4A92B725E`；EXE FileVersion／ProductVersion 均为 0.4.0+4。首候选已归档，不交付。
- 外目录为 `C:/Users/userSigma/Downloads/no-white-writer-0.4.0-windows-x64-20261027-211719`；Release、解压副本及 [21 文件清单](<.devdata/section20/package-manifest.json>) 逐一 SHA256 相等，运行后再次核对。旧 0.2.0 ZIP hash `4BEB0FDE4571A180A84AE5529FF8EAAC54B53F071E707491E09F74FE6D741064`、旧 0.3.0 ZIP hash `1D48C5E95DC80BA1C7FEF71C906BAF1021D5A016C3A6DEA4BB3900A94E270C0C` 不变。见 [运行后核验](<.devdata/section20/post-native-proof.log>)。

### 22.3 最终包原生隔离验证

- 新数据根 `C:/Users/userSigma/AppData/Local/Temp/nww-section20-040-791d4dc72b4a48abab8fdd3d33a735f3`，仅三本合成作品；不读取或写入默认 AppData 作品。实际清空卷／章标题后回读仍为空，原 18 份 TXT／BAK SHA256 均不变。
- PID 18476 完成真实章／卷／书菜单导出；自有 `.txt.tmp` 故障明确拒绝，核验归属及字节后仅删除本轮注入文件，再点击“重试”成功。逐字核对三种输出、顺序、空名／空卷分隔与末尾换行，未遗留输出 tmp。见 [导出验收](<.devdata/section20/final-native-exports.log>)、[输出文件清单](<.devdata/section20/native-exports.json>)。
- 浅色菜单与扁平目录、完整收起／展开、向上设置与主题子选单、纯黑主题、窄窗新建均由实际 UI 输入验证。新章 `d5f08110-857d-4126-89af-7fde3a33b0a7` 输入 release-title-040／release-body-040，21:21:16.890 请求关窗，21:21:16.915 保存 words 16，21:21:16.927 接受退出，未靠等待 5 秒冒充关窗保存。
- 重启 PID 11664 后实际点击书卡，界面回显 [保存标题与正文](<.devdata/section20/final-restart-open-click.png>)，深色偏好及当前章绑定保留；实际打开 [深色章节菜单](<.devdata/section20/final-chapter-menu-dark.png>)，点击遮罩 [关闭窄目录](<.devdata/section20/final-narrow-barrier-closed.png>)。只向核验 EXE 路径的自有进程发 WM_CLOSE，最终 owned PID=0；见 [重启验收](<.devdata/section20/final-native-restart-verified.log>)。
- 主路径 DPI120／125%（1280×820→1600×1025；900×700→1125×875）；重启窗口返回 DPI144／150%，补充观察 1920×1230 与 1350×1050 的回读／菜单／遮罩关闭。早期重启脚本立即检查异步激活、零时长鼠标按压及 SendKeys 未命中的尝试不算通过；等待同一自有窗口激活、核对指针下 PID 并给真实按压间隔后才取得上述结果。

### 22.4 差异范围与未验边界

- 对照本轮 14:38 的 87 文件保护快照，lib 实际差异为 20 条路径（6 新建、13 修改、1 删除；2084 增／808 删），不是把原来未跟踪的 M1 源码全部当新增。见 [逐路径清单](<.devdata/section20/final-scope.json>)、[最终 diff](<.devdata/section20/final-review-lib.diff>)。分支 ui/writing-workspace、HEAD faa3f88f8080e784eb66f81a691ef159dd171ea1；无子代理、提交、合并、推送、reset／clean。
- 原生中文长句／候选窗、撤销重做、组词跨响应式／多屏、150% 完整矩阵及 200%、系统文字缩放仍待人工；DPI144 的少量截图不代表全面通过。动画中间帧／快速反向由 widget 测试证明，未宣称原生逐帧录像；本轮未构建其他平台，未复测默认 AppData 普通启动，未扩大修复既有启动异常提示缺口。
- [README](<README.md>)、[环境记录](<docs/env.md>) 同步本轮功能与证据；旧规格与旧发布证据保留历史身份。

