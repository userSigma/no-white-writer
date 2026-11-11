# Merged Custom Titlebar Implementation Plan

> **For agentic workers:** Use executing-plans inline, task by task. User explicitly prohibits subagents and Git commits; preserve all existing uncommitted work.

**Goal:** Replace the system caption with one page-integrated custom titlebar, following the approved merged-titlebar specification.

**Architecture:** Extend the existing platform boundary with desktop capability, observable native window state and four window commands. Shared WindowTitleBar renders page-specific leading/actions/drag space; a WindowFrame hosts the window buttons above Navigator overlays, while page titlebars reserve their space. This keeps window controls available during dialogs without moving guarded editor navigation out of EditorPage. Hidden native caption retains system resize edges.

**Tech Stack:** Flutter, fluent_ui 4.17, window_manager 0.5.2; no new dependency.

---

### Task 1: Regression tests and platform contract

Files: test/custom_titlebar_test.dart, test/platform_window_test.dart; lib/core/platform/platform_services.dart; lib/core/platform/platform_services_io.dart; lib/core/platform/platform_services_stub.dart; test/support/fake_platform.dart.

- [x] Add failing widget tests for single merged header, shelf branding/actions, editor navigation/status and window controls. Add MethodChannel test proving native initialization sends setTitleBarStyle(hidden, windowButtonVisibility:false).
- [x] Run `flutter test --no-pub test/custom_titlebar_test.dart test/platform_window_test.dart --reporter expanded`; inspect expected missing-caption failure before implementation.
- [x] Add `DesktopWindowState(maximized:false, fullScreen:false)`, `supportsCustomTitleBar`, `ValueListenable<DesktopWindowState> windowState`, `minimizeWindow()`, `toggleWindowMaximized()`, `startWindowDrag()`, `requestWindowClose()` to the platform boundary; stub no-op, fake records calls and emits state.
- [x] Initialize hidden titlebar before showing, listen to native maximize/unmaximize/fullscreen changes. Close calls `windowManager.close()`, never destroy; current quit retains its separate meaning.

### Task 2: Shared chrome and merged page layout

Files: lib/ui/window_title_bar.dart; lib/app.dart; lib/main.dart; lib/ui/shelf_page.dart; lib/ui/editor_page.dart.

- [x] Implement shared 36px WindowTitleBar with draggable title/blank space, double-tap maximize, non-draggable action children, and 46×36 buttons with labels/tooltips and focus/hover states.
- [x] Implement WindowFrame around the Navigator in FluentApp.builder; host only one set of window buttons above modal overlays. Page bars reserve 138px when hosted and render their own controls only when tested/used without WindowFrame. Unsupported platforms render no window chrome.
- [x] Shelf titlebar: brand/title left, original sort/settings/create right, window buttons last. Move 全部作品/counts beside the existing search/view toolbar, with narrow layout protection. Preserve filtering, keyboard and dialogs.
- [x] Editor titlebar: existing guarded collapse/back controls left; save/count right; remove old floating nav and duplicate writing status row/side-pane top spacer. Keep one ChapterPane and existing overlay/IME/draft/animation behavior.
- [x] Give the duplicate-instance screen the same custom chrome using the existing platform object; never acquire the lock or write works there.
- [x] Run new tests and existing sidebar/footer/settings/export-exit/UI suites. Adapt geometric expectations only where the approved header intentionally moved; retain all behavior assertions.

### Task 3: Close-safety and native state verification

Files: test/custom_titlebar_test.dart, test/platform_window_test.dart; lib/app.dart only for any proven shared-exit reentrancy issue.

- [x] Bridge fake requestWindowClose to `tester.binding.handleRequestAppExit()` so actual custom close goes through NoWhiteWriterApp exit guards. Verify body/title composing, registered unfinished draft, busy export, failed save cancel/retry, successful save and no quit bypass.
- [x] Verify drag sends exactly one startWindowDrag per gesture; double-tap toggles maximize, clicking page/window actions never drags, external state events switch restore icon; dialogs do not hide window buttons.
- [x] Inspect light/dark/custom and 900px/wide previews; verify native resize/maximize/minimize/restore/close on only newly owned processes. Verify fullscreen-state hiding/restoration through widget and MethodChannel tests; native fullscreen interaction is not claimed.

### Task 4: Verification and delivery

Files: PLAN.md Q18; this plan and approved spec.

- [x] Update Q18 narrowly to merged custom titlebar, retaining native resize behavior and current theme decision.
- [x] `flutter test --no-pub --concurrency=1 --reporter expanded`, `dart analyze`, changed-Dart `dart format --output=none --set-exit-if-changed`, `git diff --check` pass with fresh evidence. The serial run retains every test and assertion; parallel-I/O instability is recorded below.
- [x] `flutter build windows --debug` succeeds; do not start a replacement web server.
- [x] Reuse the existing ignored package-and-verify-ui-review.py procedure with bundled Python: package full Debug bundle, extract to a unique ordinary Downloads folder, verify hashes/Medium-integrity/visible normal startup/own-process close/book hashes. Extend native evidence for hidden caption and window operations without touching existing processes or user books.
- [x] Record real test counts, native evidence, delivery path and any manual-test limitations, then complete goal. Never link the Low-integrity build exe as the user entry.

## Self-review

Approved shelf/editor positions, a single merged row, overlay-safe controls, native caption hiding, geometry/DPI, duplicate instance, close guards and unsupported-platform behavior all map to tasks above. No new dependencies, unrelated refactors, subagents or commits were introduced.

## Verification — 2026-11-05

### Automated regression and build

- Initial RED: missing merged header/native hidden-caption calls. Additional RED tests reproduced concurrent close requests opening duplicate save-failure dialogs and the debug banner covering window buttons. The fixes share the pending exit decision and disable that banner; existing save/IME/export guards remain intact.
- Full unchanged suite, `flutter test --no-pub --concurrency=1 --reporter expanded`: **367 passed**, 5:03. [Full log](<C:/Users/userSigma/no-white-writer/build/titlebar-full-tests-serial.log>).
- `dart analyze`: **No issues found**. Changed and untracked Dart formatting: **51 files, 0 changed**. `git diff --check`: passed; existing LF/CRLF normalization warnings only.
- Fresh `flutter build windows --debug`: **success**, 24.8 seconds. [Build log](<C:/Users/userSigma/no-white-writer/build/titlebar-windows-build-final.log>).
- Five readable widget previews cover light/dark/custom themes, shelf/editor and 900px/wide layouts. [Dark shelf](<C:/Users/userSigma/no-white-writer/build/titlebar-preview/shelf-dark.png>), [light editor](<C:/Users/userSigma/no-white-writer/build/titlebar-preview/editor-light.png>), [custom shelf](<C:/Users/userSigma/no-white-writer/build/titlebar-preview/shelf-custom.png>). Preview-only font overrides were not shipped.
- Parallel-I/O limitation: one default-concurrency run produced six asynchronous-write/temporary-directory cleanup failures. The same five affected files passed all **35 tests** unchanged at concurrency 1, then the complete **367-test** serial run passed. No assertion was removed or timeout increased. This verifies the serial suite, not default-concurrency stability. [Diagnostic log](<C:/Users/userSigma/no-white-writer/build/titlebar-io-diagnostic.log>).

### Native Windows verification and delivery

- Full Debug bundle packaged and extracted into a new ordinary Downloads directory: **23 files**, all SHA-256 hashes match; actual process integrity **Medium (RID 8192)**, visible normal application window, normal exit 0.
- Only newly created test windows were exercised, at native **144 DPI / 150% scaling**. Native caption top inset **1 physical pixel**, resize-edge hit test **11**; real edge drag increased width from **1920 to 1980 physical pixels**. Custom minimize, maximize/restore, blank-area double-click maximize/restore and real blank-area dragging all passed.
- A separately owned duplicate instance displayed the custom caption and closed through its custom close button, exit 0. The owned main process also closed through the custom button, exit 0. All **8 existing book files remained hash-identical**, and the source/extracted bundles stayed unchanged. Existing processes, instance locks and ACLs were not altered.
- [Native interaction results](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-012242/native-titlebar-checks.json>), [ordinary-startup result](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-012242/result.json>), [maximized native capture](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-012242/native-maximized.png>), [duplicate-instance capture](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-012242/native-duplicate-instance.png>).
- User entry: [ordinary-folder executable](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261105-012242/no_white_writer.exe>). [Complete ZIP](<C:/Users/userSigma/no-white-writer/build/packages/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261105-012242.zip>). Keep the executable, DLLs and data together; do not use the Low-integrity build output directly.

### Scope and limitations

- Main page has brand/title at the left and existing actions at the right; editor has collapse then back at the left and save/count at the right. Both use a single 36px merged header, with one set of window buttons above dialog barriers.
- Fullscreen hide/restore is covered by widget and native MethodChannel state tests, not a real native fullscreen interaction. Native checks cover the current Windows machine and 150% DPI, not every OS/monitor configuration. Windows 11 native Snap-layout hover flyout is not promised. Full manual IME and native directory-picker matrices were not repeated.
- Current user theme/settings and existing window-geometry behavior were retained. No Git commit or subagent was used.
