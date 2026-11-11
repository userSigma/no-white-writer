# 界面字体改为调用系统默认字体

## 需求（用户 m04919）

把应用界面字体（不含编辑区正文）改为调用系统默认字体。

## 审计结论（改动前）

- 全仓只有一处显式字体族：`lib/ui/editor_page.dart:595`（`chapter-body` 正文输入框）与 `:609`（其占位文本）使用 `LXGWWenKaiGB`；`pubspec.yaml:33-35` 注册该字体族。其余界面文本都没有声明字体族。
- `fluent_ui 4.17.0` 的 `Typography.fromBrightness` 生成的字号样式不含 `fontFamily`，`buildFluentTheme` 也没有设置字体，因此界面此前只是「没有指定字体」，靠 Flutter 引擎的隐式默认族渲染。
- 实测（`build/capture-ui-font.py` 用 `PrintWindow` 抓真实 Release 窗口）：界面文字本就是雅黑风格的哥特体，不是文楷——即「看起来接近系统字体」，但并未显式调用系统界面字体。

## 实现

- 新增 `lib/ui/theme/app_font.dart`：
  - `kSystemUiFontFamily = 'Segoe UI Variable Text'`（Windows 11 界面正文字体）；
  - `kSystemUiFontFallback = ['Segoe UI', 'Microsoft YaHei UI']`——Windows 10 没有变量字体时退到 Segoe UI，中文一律落到系统界面的「Microsoft YaHei UI」，而不是引擎隐式挑选的「Microsoft YaHei」；
  - `kSystemUiTextStyle`：只声明字体族与回退链，字号/颜色仍由各处样式决定。
- `lib/app.dart`：`FluentApp.builder` 返回的最外层包一层 `DefaultTextStyle.merge(style: kSystemUiTextStyle, ...)`，覆盖 Navigator 页面与 overlay（菜单、浮层、提示条）在内的整个界面；`Text` 的合并顺序是「默认.merge(自身样式)」，所以编辑区正文显式声明的 `LXGWWenKaiGB` 仍然优先，正文排版不受影响。

## 测试

- 新增 `test/ui_font_test.dart`：
  1. 界面文本（`全部作品`、统计行、`新建` 按钮）实际渲染样式的 `fontFamily` / `fontFamilyFallback` 等于系统字体常量；
  2. 打开作品后 `chapter-body` 仍是 `LXGWWenKaiGB`，`chapter-title` 不再是文楷（跟随界面默认）；
  3. 单元断言 `TextStyle.merge` 的方向：`kSystemUiTextStyle.merge(正文样式)` 得到文楷，证明界面默认不会覆盖编辑区。
- 首次运行即为 RED（`fontFamily` 为 null、`kSystemUiTextStyle` 尚不存在），实现后转 GREEN。

## 验证记录（2026-11-10）

- `flutter test --no-pub test/ui_font_test.dart --concurrency=1` → 3 passed（`build/ui-font-test.log`）。
- 系统中确实存在 `Segoe UI Variable Text`、`Microsoft YaHei UI` 两个字体族（`System.Drawing.FontFamily` 枚举结果）。
- Release 实测抓图：`build/ui-font-before.png`（改动前）与 `build/ui-font-capture.png`（改动后）对比，`build/ui-font-compare.png`、`build/ui-font-digits.png` 显示字形与字宽发生变化（变量字体 + 雅黑界面字），无豆腐块、无裁切、无溢出。
- `dart analyze` → No issues found!；`dart format lib test` → 107 files，0 changed。
- 未提交、未推送；用户数据、ACL、锁文件、历史进程均未改动。

## 交付

- 全量 `flutter test --no-pub --concurrency=1` → **431 passed / 0 failed**，5:05（`build/ui-font-full-tests.log`）。
- 构建：`dart run tool/build_windows_installer.dart --output-dir build/packages/ui-font-20261110`，Inno 6.7.3 编译 17.563s。
- 校验脚本 `build/verify-ui-font-delivery.py`（忽略目录）：SVG 源与 `assets/branding/app_icon.png`、ICO 七帧逐字节一致；app EXE 与 setup 的 RT_GROUP_ICON/RT_ICON 仍与七帧相同；上一版 installer（`d309f8d4…`）未被覆盖；产物写入普通 Downloads 目录且无 Low 完整性标签。
- 产物：`C:/Users/userSigma/Downloads/no-white-writer-0.4.1-ui-font-20261110-234518/no-white-writer-0.4.1-windows-x64-setup.exe`，20,927,026 字节，SHA-256 `0d48fcf4dc04e775aa38238c7b4e93613df4ec916aeef423ca9341abead14139`，同目录 `.sha256` 一致；FileVersion 0.4.1.5 / ProductVersion 0.4.1+5 / FileDescription 不白写作 Setup。证据 `build/ui-font-verification-20261110-234518/result.json`。
- `git -c core.whitespace=cr-at-eol diff --check` 干净，HEAD 仍为 `0fa6a4a`，未提交、未推送。
