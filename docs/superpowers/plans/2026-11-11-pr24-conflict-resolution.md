# PR #24 冲突整合记录（2026-11-11）

## 目标与边界

将 `feature/ui-review-p1-navigation` 合并到 `develop`。保留 develop 的 P2 显式依赖、导出组合根、设置分区和编号投影拆分；保留 feature 的标题栏、书架、目录选择器、系统字体、SVG 图标和 Inno Setup 支持。

- 整合起点：feature `d5f94f9f1e90cf4c55a7b015132894ca96deeaa0`，develop `99fc466d8ddc637f529a96ebe58d84bc8080b76d`。
- 保留 develop 已提交的 `version: 0.5.0`，并非将其降回 feature 的 `0.4.1+5`。
- 采用合并提交，不改写已有分支历史；不修改 main、标签、仓库保护规则或用户作品数据。

## 冲突处理

普通预检的 23 个冲突受 LF/CRLF 差异影响；使用 `-Xignore-space-at-eol` 后，需人工整合的内容冲突为 5 个：

1. [env.md](../../env.md)：保留两边历史验收记录，新增记录顺延至第 15 节。
2. [editor_page.dart](../../../lib/ui/editor_page.dart)：保留自绘合并标题栏，同时使用 P2 显式依赖。
3. [shelf_page.dart](../../../lib/ui/shelf_page.dart)：保留单一网格、同排居中搜索与 3:4 作品框，使用显式依赖和恢复章节数量。
4. [settings_menu.dart](../../../lib/ui/settings_menu.dart)：保持 P2 分区，仅负责入口与浮窗编排；将 560px 响应式布局、原生只读目录选择及紧凑主题管理移入对应组件。
5. [settings_menu_test.dart](../../../test/settings_menu_test.dart)：保留目录选择器、布局、保存失败及退出守卫断言，测试装配改用 P2 组合根辅助函数。

相关测试改用 `chapter_display`、`uiGuards` 和页面装配辅助函数；独立目录分区测试覆盖选择取消、立即保存、失败重试、在途关闭保护与恢复默认。保留 P2 架构边界、紧凑重命名及恢复数量测试。

## 本地验证

- [x] 重点回归：79 项通过，包含双方布局、P2 边界、目录分区、标题栏关闭、字体和编号测试。
- [x] 全量串行测试：`flutter test --no-pub --concurrency=1`，451 项通过，0 失败，用时 6 分 19 秒。
- [x] 最终格式检查：`dart format --output=none --set-exit-if-changed lib test tool`，124 个文件，0 改动。
- [x] 最终静态分析：`dart analyze`，No issues found。
- [x] Windows Release 与 Inno Setup 构建：Release 89.8 秒，Inno 6.7.3 编译 27.765 秒。
- [x] 只读资源核验：应用与安装器均为 `0.5.0.0`，SHA-256 sidecar 一致。安装器 20,927,842 字节，SHA-256 `6fbc05b4ef3dbb4b1176f011592710ff5518f17c016133a8b5ddd9f92c956630`。
- [x] 冲突标记扫描与 CRLF-aware `git diff --check` 通过。

## 远端执行门禁

本记录随整合提交保存，本地验证先于推送和远端合并。远端执行时核对：PR 的 head 必须等于该已验证提交，base 仍为上述 develop 提交；检查项目不存在失败或在途状态，再使用带 head SHA 前提的 GitHub 合并请求。最终远端提交与合并时间以 [PR #24](https://github.com/userSigma/no-white-writer/pull/24) 为准；未出现的 CI 运行不记为通过。

本记录中的历史原生验收不代表本次重新执行；本次未启动应用或安装器，也未访问作者作品目录。
