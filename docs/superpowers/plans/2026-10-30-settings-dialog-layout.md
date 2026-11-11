# Settings Dialog Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. User explicitly requires inline execution without subagents; preserve all existing uncommitted work and do not create Git commits for this delivery.

**Goal:** Implement the recommended settings-dialog layout approved on 2026-10-30: about 560 logical pixels wide, 24-pixel horizontal padding, reference-image grouping and responsive controls.

**Architecture:** Keep the existing ContentDialog, settings controller, native folder-picker flow and guarded requestClose method. Override the outer dialog constraints (the default Fluent cap is 368), not only the inner content width. Rearrange presentation only; use the same persistence, theme-editing and close guards.

**Tech Stack:** Flutter 3.47.7, Dart 3.13.5, fluent_ui 4.17.0, existing widget test harness.

---

## File responsibilities

- Modify `lib/ui/settings_menu.dart`: responsive dialog bounds/padding, close icon, same-row theme/export controls, theme management panel, separators and Done action.
- Modify `lib/core/i18n/builtin_packs.dart`: add settings-only localized Done and compact Manage labels; leave common.close and existing labels unchanged elsewhere.
- Modify `test/settings_menu_test.dart`: real geometry, narrow viewport, theme management, save/close protection tests.
- Reuse ignored `build/package-and-verify-ui-review.py`: rebuild, ZIP/extract ordinary-folder delivery and verify startup without changing user books or terminating existing processes.

### Task 1: Test desktop geometry and responsive behavior

- [x] Add desktop regression to `test/settings_menu_test.dart` using the real settings entry:

```dart
final dialog = find.descendant(
  of: find.byKey(const ValueKey('settings-menu')),
  matching: find.byType(Container),
).first;
expect(tester.getSize(dialog).width, closeTo(560, 1));
expect(tester.getTopLeft(find.text('语言')).dx -
    tester.getTopLeft(dialog).dx, closeTo(24, 1));
final theme = tester.getRect(find.byKey(const ValueKey('settings-theme')));
final manage = tester.getRect(find.byKey(const ValueKey('settings-theme-manage')));
expect(manage.top, closeTo(theme.top, 1));
expect(manage.left - theme.right, closeTo(8, 1));
final path = tester.getRect(find.byKey(const ValueKey('settings-export-path')));
final change = tester.getRect(find.byKey(const ValueKey('settings-change-export-path')));
expect(change.top, closeTo(path.top, 1));
expect(change.left - path.right, closeTo(8, 1));
```

- [x] Add management regression: no standalone creation button before Manage is expanded; expand, create a real theme, then rename and delete via guarded existing flows. Verify the management panel is inside the theme group.
- [x] Add close/Done regression: both controls call the same close guard, pending picker disables both, save failure keeps the dialog open, successful retry can close it.
- [x] Add viewport regression at 360×640 and 600×480 using the actual SettingsMenuButton on a minimal Fluent ScaffoldPage (avoid unrelated shelf responsiveness). Verify the dialog stays inside the viewport, has no layout exceptions and bottom Done/top close stay hit-testable while the content scrolls.
- [x] Run `flutter test --no-pub test/settings_menu_test.dart --reporter expanded > build/settings-layout-red.log 2>&1`. Expect failures caused by the current 368-pixel dialog and missing same-row/manage/Done controls.

### Task 2: Implement only the approved presentation changes

- [x] Override outer ContentDialog bounds and symmetric padding:

```dart
constraints: const BoxConstraints(maxWidth: 560, maxHeight: 756),
style: const ContentDialogThemeData(
  padding: EdgeInsetsDirectional.fromSTEB(24, 20, 24, 20),
  actionsPadding: EdgeInsetsDirectional.fromSTEB(24, 16, 24, 16),
),
```

Keep the inner requested width large enough to fill this cap. Existing dialog route constrains smaller windows. In `_row`, use LayoutBuilder to switch label/control into a vertical group when its available content width is below 400; otherwise keep the current 96-pixel label and 12-pixel gap with top alignment.

- [x] Replace the title Text with a Row: Expanded existing title and Tooltip/IconButton keyed `settings-close`. Its enabled state is `!_working && !_confirming`; its action remains `() => unawaited(requestClose())`. Add a keyed `settings-done` FilledButton with exactly the same guard and localized `settings.done` label.
- [x] Put the theme ComboBox in Expanded beside an 8-pixel gap and keyed `settings-theme-manage` Button. The button toggles `_manageOpen` even with no custom themes. Use localized compact Manage text with full existing label in a tooltip.
- [x] Move the unchanged theme-creation Button inside `_manageOpen`, key it `settings-theme-create`, and keep existing rename/delete rows below it. Keep theme limit, confirmation guards and all helper calls unchanged.
- [x] Put readonly export TextBox in Expanded beside an 8-pixel gap and existing Change Button, top aligned. Keep Open export and Reset in a Wrap below with 8-pixel gaps, in that order. Keep native picker, cancellation, errors and persistence unchanged.
- [x] Retain thin separators between language/theme, writing options, export, system directories and about. Keep all content in SingleChildScrollView; keep title and Done outside the scroller.
- [x] Add translations without changing global close text:

```dart
'settings.done': '完成',
'settings.theme.manage.short': '管理',
```

English values are `Done` and `Manage`.

- [x] Run `dart format lib/ui/settings_menu.dart lib/core/i18n/builtin_packs.dart test/settings_menu_test.dart` then `flutter test --no-pub test/settings_menu_test.dart test/monochrome_test.dart --reporter expanded > build/settings-layout-green.log 2>&1`. Expect all tests pass.

### Task 3: Verify, build and deliver

- [x] Run `flutter test --no-pub --reporter expanded > build/settings-layout-full-tests.log 2>&1`; collect the job and verify its exit status and test count.
- [x] Run `dart analyze`, `git diff --check` and `dart format --output=none --set-exit-if-changed lib/ui/settings_menu.dart lib/core/i18n/builtin_packs.dart test/settings_menu_test.dart`. Expect no errors or formatting changes.
- [x] Run `flutter build windows --debug`, collect successful build output, then reuse the existing packaging/startup verification script only after reading it. Never deliver the Low-integrity executable under build directly.
- [x] Verify complete ordinary-folder bundle hashes and normal Medium-integrity startup, close only the test-owned process, compare user-book hashes, and document evidence and any native interaction limitations. If an already-running user app prevents startup verification, do not terminate it; report the limitation.
- [x] Report a concise change summary, fresh test/build results and a link to the ordinary-folder executable. Do not change data ACLs, delete lock files, terminate old processes or commit unrelated work.

## Self-review

All approved requirements map to Task 2; Task 1 verifies actual rendered widths and control positions rather than widget configuration only. Existing save, picker, theme, Escape, error and IME tests remain authoritative. No new dependency, business-state rewrite, P2/P3 work or application color redesign is included.

## Verification record — 2026-10-31

- Regression tests first failed against the previous 368-pixel dialog, then passed with the approved layout. The desktop test measures the dialog's local logical coordinates because Fluent's existing route transition scales its rendered surface; this preserves the framework transition without weakening the 560-pixel width, 24-pixel padding or 8-pixel control-gap assertions.
- Full suite: **345 tests passed**, exit 0; [test log](<../../../build/settings-layout-full-tests.log>). Theme creation/rename/delete, both guarded close controls, save failure/retry, pending folder picker, desktop geometry and 360×640 / 600×480 viewport behavior are covered.
- `dart analyze`: no issues. `git diff --check`: exit 0. Formatting verification: no changes. Existing CRLF normalization notices are informational.
- `flutter build windows --debug`: successful. The complete extracted delivery contains **23 files**, all SHA-256 equal to the current build. [Launch result](<../../../build/ui-review-normal-startup-20261031-002155/result.json>) confirms Medium integrity (RID 8192), a visible normal app window and exit code 0. [Lifecycle log](<../../../build/ui-review-normal-startup-20261031-002155/lifecycle-log.txt>) confirms default-AppData instance acquisition and normal close.
- Default user-book files: **8 unchanged**. Only the verification-owned process was closed; no existing processes, lock files or data ACLs were altered.
- [Desktop light preview](<../../../build/settings-layout-preview/desktop-light.png>), [desktop dark preview](<../../../build/settings-layout-preview/desktop-dark.png>) and [narrow preview](<../../../build/settings-layout-preview/narrow.png>) were rendered and visually checked. The ignored preview harness loads icons and explicitly applies Microsoft YaHei only to its test theme to replace Flutter test's Ahem font; production typography is unchanged. These are widget-rendered previews, not native-window screenshots.
- Native folder-dialog interaction and a complete Chinese IME / multi-monitor / accessibility matrix were not manually exercised. Existing widget regressions cover picker selection/cancellation/errors and the retained guards; ordinary native startup was separately verified.
- Delivery: [ordinary-folder executable](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261031-002155/no_white_writer.exe>) and [complete ZIP](<../../../build/packages/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261031-002155.zip>). Keep the executable with its DLLs and data folder; do not run or deliver the Low-integrity build-directory entry directly. No subagents or Git commits were used.
