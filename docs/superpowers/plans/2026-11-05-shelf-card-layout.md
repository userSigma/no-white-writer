# Shelf Card Layout and Caption Divider Implementation Plan

> **For agentic workers:** Use executing-plans inline. User prohibits subagents and Git commits; preserve the existing worktree. The complete proposed layout and dimension interpretation were explicitly approved in chat.

**Goal:** Correct shelf action placement, preserve equal 3:4 book/creation outlines with internal metadata, and keep the caption divider continuous beneath window controls.

**Architecture:** Keep shelf-specific layout in ShelfPage and its private card widgets. Reuse existing callbacks, HoverAction and theme tokens. Fix the shared WindowControls paint layer rather than moving or duplicating native buttons.

**Tech Stack:** Flutter, fluent_ui 4.17, existing platform boundary; no new dependencies.

---

### Task 1: Failing geometry and raster regressions

Files: test/custom_titlebar_test.dart; test/ui_polish_test.dart; test/ui_revision_test.dart; new test/shelf_layout_feedback_test.dart.

- [x] Add actual rectangle assertions that sort/settings/create are not descendants of window-title-bar, share the 全部作品 content row and sit to its right at 900px and 1280px. Preserve brand/window-button caption assertions and all editor/close safety tests.
- [x] Create a temporary book and assert its rounded outline is Size(220, 220 * 4 / 3); its statistics, relative timestamp and 28px menu rectangles are contained inside that outline; no decorative 不白写作 remains inside it.
- [x] Assert the creation button/painted outline rectangle equals the book outline, including empty-shelf behavior; mouse hover changes its background/accent state and reveals 创建新作品 without changing geometry. Keep click, keyboard and disabled-export behavior.
- [x] Rasterize a RepaintBoundary around the real app using tester.runAsync, sample the bottom caption pixel band at the drag area and beneath all three buttons, and compare to hairlineColor. Cover light/dark/custom themes, 1/1.25/1.5 raster scaling and close hover/press; use actual pixel samples so an opaque overlay cannot falsely pass.
- [x] Run `flutter test --no-pub --concurrency=1 test/shelf_layout_feedback_test.dart test/custom_titlebar_test.dart --reporter expanded`; capture missing layout/paint behavior RED, not compile failures.

### Task 2: Shelf actions and equal card outlines

File: lib/ui/shelf_page.dart.

- [x] Move the existing sort ComboBox, SettingsMenuButton and FilledButton from WindowTitleBar.actions into a shelf content-header Row. Use Expanded for title/counts and keep search/view controls in a separate row; preserve callbacks and exporter.busy guards.
- [x] Remove the book's external footer and imprint. Keep `AspectRatio(aspectRatio: 3 / 4)` and the existing title/spine/shadow/selection behavior; use a bottom Row with Expanded statistics/timestamp on the left and the original HoverAction menu on the right, all inside the cover padding.
- [x] Set grid occupancy height to `math.min(220, width) * 4 / 3` while keeping 20px/26px gaps. Update the obsolete 220x350 occupancy expectation to 220x293⅓, explicitly preserving the original visible cover dimensions.
- [x] Replace the creation helper's permanently transparent style with a private stateful tile: MouseRegion and non-requestable Focus observe hover/descendant focus, disabled state remains guarded, AnimatedContainer supplies subtle theme tint, _DashedBorderPainter uses accent when active, and Tooltip supplies 创建新作品. Keep the same button key and create callback; reuse the widget in the 76px list row.
- [x] Run shelf geometry/hover, existing UI revision, filtering, menu and exporter-busy suites; no assertion removal or missed-hit suppression.

### Task 3: Foreground caption divider

File: lib/ui/window_title_bar.dart.

- [x] Preserve hosted controls/Overlay, WindowTitleBar bottom rule, button actions, semantics and sizes. Wrap the shared controls' current opaque ColoredBox with foreground decoration:

```dart
DecoratedBox(
  position: DecorationPosition.foreground,
  decoration: BoxDecoration(
    border: Border(bottom: BorderSide(color: hairlineColor(context))),
  ),
  child: ColoredBox(color: paperOrInk(context), child: existingButtonRow),
)
```

- [x] Run raster tests in normal/hover/press states, then custom_titlebar/platform_window/titlebar_close suites. Confirm one caption and one window-button set remain.

### Task 4: Verification and ordinary-folder delivery

- [x] Inspect fresh shelf light/dark/custom previews at 900px/wide and confirm outline/hover positions, no clipped metadata and continuous divider. Preserve existing editor layout.
- [x] Run the complete suite with `flutter test --no-pub --concurrency=1 --reporter expanded`, `dart analyze`, changed/untracked Dart read-only format check and `git diff --check`. Record actual counts; do not hide the existing default-concurrency I/O limitation.
- [x] Build `flutter build windows --debug`, then use the existing ignored ordinary-folder packaging/native-window verifier with bundled Python. Check bundle hashes, Medium-integrity startup, own-process-only window operations/close and unchanged book hashes. Never terminate prior processes or change locks/ACLs.
- [x] Record evidence and deliver the newly extracted executable with its DLL/data bundle. No Git commit or subagent; complete the goal only after collecting every relevant job.

## Self-review

All three user corrections map to geometry/hover or raster tests and minimal edits in two production files. Existing visible book size, callbacks, keyboard/menu/close behavior and editor caption remain in scope as non-regression constraints. No settings, serialization or theme policy changes are planned.

## Verified results — 2026-11-05

- Initial feature RED: 14 expected layout/raster failures, with no compilation failure; targeted GREEN: 34 tests. Additional keyboard and dark-card contrast regressions were observed failing before their fixes and passed in the final suite.
- Creation keyboard activation now locally handles Enter/numpad Enter instead of allowing the shelf's ancestor shortcut to open an existing book. The paused-export regression also checks that tile creation remains disabled. Selected dark-card statistics blend the current accent toward the current foreground for readable contrast; theme storage/policy is unchanged.
- Fresh previews: 6 cases covering shelf light/dark/custom at wide/900px, creation hover, and unchanged editor layouts. Test-only Chinese font overrides are not shipped. See [preview log](<C:/Users/userSigma/no-white-writer/build/shelf-feedback-previews-final.log>) and [light shelf](<C:/Users/userSigma/no-white-writer/build/shelf-feedback-preview/shelf-light.png>).
- Full suite: **383 tests passed** with `flutter test --no-pub --concurrency=1 --reporter expanded` (5:14). See [full-suite log](<C:/Users/userSigma/no-white-writer/build/shelf-feedback-full-tests.log>). Serial execution retains the documented earlier default-concurrency asynchronous-I/O/temporary-cleanup limitation; no assertion or timeout was weakened.
- `dart analyze`: **No issues found**. Read-only formatting: **52 Dart files, 0 changed**. `git diff --check`: clean apart from existing LF/CRLF conversion warnings.
- Fresh Windows Debug build: **passed, 31.2s**. See [build log](<C:/Users/userSigma/no-white-writer/build/shelf-feedback-windows-build.log>).
- Ordinary-folder delivery: **23/23 files match SHA256**, executable runs at **Medium integrity (RID 8192)** with the normal default AppData root, visible title 不白写作 and exit code 0; **8/8 existing book files unchanged**. See [startup result](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-223420/result.json>).
- Native verification at **120 DPI / 125%**: caption top inset 1 physical pixel, native edge resize, custom minimize/maximize/restore, double-click, dragging, duplicate-instance close and normal custom close passed. Caption-divider samples beneath all three buttons equal the drag-area reference **RGB (227, 218, 203)** in normal, hover and pressed states. See [native checks](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-223420/native-titlebar-checks.json>) and [native screenshot](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261105-223420/native-caption-divider.png>).
- Only owned verification processes were closed. No user works, existing processes, locks or ACLs were modified. Native folder-picker/full IME manual matrices were not repeated; existing save/IME/export/close widget regressions passed in the full suite.
- Delivered [ordinary-folder executable](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261105-223420/no_white_writer.exe>) and [complete ZIP](<C:/Users/userSigma/no-white-writer/build/packages/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261105-223420.zip>). Keep its DLL/data bundle together; never use the Low-integrity build-tree executable as the entry point. No subagents or Git commits.
