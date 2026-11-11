# 书架顶栏：搜索并入标题行、只保留一种书架样式

## 需求（用户 m04454）

1. 把「搜索作品」从独立一行移到「全部作品」这一行，与排序、设置、新建同排，并保持自身居中。
2. 删除搜索框右侧的视图样式按钮（网格 / 列表），主界面有且仅有书架一种样式。

## 实现

- `lib/ui/shelf_page.dart`
  - 删除 `_listView` 状态、`_bookListRow(...)` 列表行构建器、`shelf-grid-view` / `shelf-list-view` 两个切换按钮，以及原先独立的居中搜索行。
  - 顶栏改为 `Padding(28,20,28,12)` → `LayoutBuilder` → `Stack(alignment: center)`：
    - 左侧 `SizedBox(width: side)` 内是「全部作品 + 统计」，宽度受限（`Flexible(3)/Flexible(2)`），窗口收窄时只截断文字，不会滑到搜索框下方；
    - 右侧 `_shelfActions` 保持右对齐（排序 124 + 8 + 设置 36 + 8 + 新建）；
    - 搜索框 `SizedBox(width: searchWidth)` 由 `Stack` 居中，`searchWidth = min(320, max(120, 可用宽度 - 2*side))`，`side = max(0, (可用宽度 - 320)/2 - 16)`。
  - 主体只保留网格，并加 `ValueKey('shelf-book-grid')` 便于断言「唯一视图」。
- 键盘路径不变：`_focus` 上的 `_key` 处理方向键 / 菜单键 / 回车；排序下拉的 `onChanged` 会 `_focus.requestFocus()` 把焦点交回书架。

## 测试

- `test/shelf_layout_feedback_test.dart`
  - 900 / 1280 / 1600 三档：搜索宽 320、自身居中（中心 = 窗口宽/2）、与标题/右侧按钮同一行且垂直居中偏差 ≤2px、互不重叠，两个切换按钮不存在，`shelf-book-grid` 存在，无溢出异常。
  - 新增：两本书过滤 `alp` 后只剩 Alpha，排序下拉交回焦点后回车打开 Alpha 编辑器。
- `test/ui_polish_test.dart`：原「窄屏切换列表」用例改为「窄屏书架保留可见 28px 作品菜单」。
- `test/ui_review_test.dart`：`shelf keeps one view and search filters the visible grid`。

## 验证记录（2026-11-10）

- 执行器一度整体不可用（`dsh-ops` 私有 exec 树建硬链接失败，所有命令 `effects: none`），期间未做任何声称；恢复后重跑。
- 首次聚焦运行失败 2 例：`Expected 'Alpha' / Actual null` —— 点击「全部作品」并不能把焦点交回书架（Windows 上 tap-outside 只做 unfocus，未必落回 `_focus`）。测试改为走产品既有的焦点回归路径（排序下拉 `onChanged` → `_focus.requestFocus()`），不是放松断言。
- `flutter test --no-pub test/shelf_layout_feedback_test.dart test/ui_review_test.dart --concurrency=1` → 21 passed（`build/shelf-row-tests.log`）。
- 全量 `flutter test --no-pub --concurrency=1` → **428 passed / 0 failed**，5:05（`build/full-suite-shelf-row.log`）。
- `dart analyze` → No issues found!；`dart format lib test` → 105 files（2 changed，均为本次改动的测试）；`git -c core.whitespace=cr-at-eol diff --check` 干净。
- 未提交、未推送；用户数据、ACL、锁文件、历史进程均未改动。

## 交付

- 构建：`dart run tool/build_windows_installer.dart --output-dir build/packages/shelf-row-20261110`，Inno 6.7.3 编译 27.437s。
- 校验脚本 `build/verify-shelf-row-delivery.py`（忽略目录）：SVG 源与 `assets/branding/app_icon.png`、ICO 七帧仍逐字节一致；app EXE 与 setup 的 RT_GROUP_ICON/RT_ICON 仍与 7 帧相同；上一版 installer（7ff590ca…）未被覆盖。
- 产物：`C:/Users/userSigma/Downloads/no-white-writer-0.4.1-shelf-row-20261110-232231/no-white-writer-0.4.1-windows-x64-setup.exe`，20,927,547 字节，SHA-256 `d309f8d4a1db70afadee754ddd42e90dba2ccd23bf7ad22f7064f5c053181562`，同目录 `.sha256` 一致；普通 Downloads 目录、无 Low 完整性标签。证据 `build/shelf-row-verification-20261110-232231/result.json`。
- 主窗口最小尺寸为 900×600（`platform_services_io.dart:18`），即测试覆盖的最窄档；更窄布局在运行时不出现。
- 本次未启动 app/安装器做人工点击验证（沿用既有启动脚本会抢占前台窗口的环境限制），布局由三档几何断言覆盖。
