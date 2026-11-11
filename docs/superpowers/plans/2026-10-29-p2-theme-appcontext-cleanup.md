# P2 自定义主题与 AppContext 收敛实施计划

> 在当前会话内分步实施并验证；不执行 Git 提交。

**目标：** 将自定义主题 CRUD 与管理界面从设置浮窗提取为独立分区，并把 `AppContext` 的恢复记录依赖收窄为恢复章节数量。

**架构：** `SettingsMenu` 继续负责浮窗生命周期、关闭守卫和统一消息，只通过回调协调主题分区；新的 `CustomThemeSection` 自有管理状态与主题 CRUD。`AppContext` 只提供页面真正需要的计数，不暴露恢复记录集合。主题持久化、现有 Key、即时预览、IME 和关闭确认行为保持不变。

**涉及文件：**

- 新建 `lib/ui/settings/custom_theme_section.dart`
- 修改 `lib/ui/settings_menu.dart`
- 修改 `lib/app_context.dart`
- 修改 `lib/main.dart`
- 修改 `lib/app.dart`
- 修改 `test/support/page_harness.dart`
- 新建 `test/custom_theme_section_test.dart`
- 修改 `test/p2_boundaries_test.dart`
- 更新 `docs/重构清单.md`

---

## Task 1：建立失败测试

1. 在 `test/custom_theme_section_test.dart` 使用真实 `CustomThemeSection` 和 `SettingsController`，记录模态回调；打开创建主题对话框应上报 `true`，创建并应用后应恢复 `false`，自定义主题数量为 1，且当前主题切换为新主题。
2. 在 `test/p2_boundaries_test.dart` 增加源码边界断言：主题 CRUD 不再位于 `settings_menu.dart`，`AppContext` 不再暴露 `recovered` 列表。
3. 运行新增测试并确认因类型尚不存在、旧接口仍存在而失败。

## Task 2：提取主题管理分区

1. 新建 `CustomThemeSection`，移入主题选择、创建、重命名、删除、数量限制和管理列表。
2. 分区接收 `SettingsController`、关闭/组合输入阻塞状态、模态变化回调和消息回调；内部持有 `_manageOpen` 与主题 CRUD。
3. 从 `SettingsMenu` 删除已迁移状态和函数，保留 `_confirming` 供目录确认及关闭守卫共用。
4. 运行主题分区、主题对话框和设置浮窗相关测试，再运行静态分析。

## Task 3：收窄 AppContext

1. 将 `AppContext.recovered` 改为默认值为 0 的 `recoveredChapterCount` 整数。
2. 在恢复入口传 `restored.length`，在开发入口与两个页面路由处读取新字段。
3. 更新测试支撑代码中的两处计数字段引用，保留路由和恢复行为不变。
4. 运行 AppContext、页面依赖及路由相关测试。

## Task 4：文档与完整验证

1. 在 `docs/重构清单.md` 记录两项收敛结果，不提前改变其他批次的验收状态。
2. 运行 `dart format lib test`、`flutter analyze --no-pub`、完整 `flutter test --no-pub --reporter expanded` 和 `git diff --check`。
3. 检查最终差异，确认没有触碰 Store 字段迁移、`EditorController`、磁盘格式或无关文件。
