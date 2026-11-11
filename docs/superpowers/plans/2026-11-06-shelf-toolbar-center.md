# Centered Shelf Search Toolbar Implementation Plan

> Execute inline without subagents or Git commits. Preserve all earlier worktree changes.

**Approved requirement:** The 2026-11-06 user correction explicitly places search and grid/list controls together at the horizontal center, not the right edge. Sort/settings/new remain on the right of the separate 全部作品 row. No new visual design or data behavior is introduced.

**Implementation:** In [ShelfPage](<C:/Users/userSigma/no-white-writer/lib/ui/shelf_page.dart>), center the existing second-row children with `mainAxisAlignment: MainAxisAlignment.center`. Replace the full-width `Expanded/Align(centerRight)` wrapper with `Flexible(child: SizedBox(width: 320, child: existingSearch))`. This centers the entire search-plus-view group while still allowing the search to shrink if constrained. Preserve the 12px gap, existing buttons, callbacks and first-row positions.

- [x] Add actual rectangle tests at 900/1280/1600 logical px: the union of search/grid/list bounds has center x equal to half the viewport, the search is 320px, all centers share y, and the group remains centered after switching to list mode. Keep existing toolbar positioning/filtering/keyboard tests.
- [x] Run the new geometry cases before implementation and observe right-alignment failures, not compilation errors.
- [x] Apply only the layout-wrapper change; remove the obsolete upper-right wording from the existing test description, not its adjacency assertion.
- [x] Run focused regressions, previews, the serial full suite, analysis/format/diff checks and a fresh Windows Debug build.
- [x] Package into an ordinary Downloads directory, verify normal owned-process startup/exit and unchanged bundle/book hashes, and deliver the complete bundle. Record the additional foreground-window automation timeout explicitly rather than counting its unexecuted interaction checks as passing.

**Non-regressions:** Existing caption divider, 3:4 book/new-card outlines, metadata placement, right-side shelf actions, hover/keyboard handling and save/IME/export guards remain unchanged. No dependencies, settings or persistence logic changes.

## Fresh verification — 2026-11-06

- Focused regressions: **27 passed**, including actual centered-group geometry at 900/1280/1600 logical px before and after switching view modes. The three new geometry cases first failed on the old right-aligned layout.
- Full serial suite: **386 passed** in 6:08; see the [full-suite log](<C:/Users/userSigma/no-white-writer/build/shelf-center-full-tests.log>). Six preview cases also passed; the [desktop preview](<C:/Users/userSigma/no-white-writer/build/shelf-center-preview/shelf-light.png>) and [900px custom-theme preview](<C:/Users/userSigma/no-white-writer/build/shelf-center-preview/shelf-custom.png>) show the centered group with other layout unchanged.
- `dart analyze`: **No issues found**; 52 changed/new Dart files had zero formatting changes; `git diff --check` passed (existing LF/CRLF warnings only).
- Fresh Windows Debug build succeeded in **31.0s**; see the [build log](<C:/Users/userSigma/no-white-writer/build/shelf-center-windows-build.log>).
- Ordinary-directory packaging and normal default-AppData startup/exit passed: **23 bundle files matched SHA256**, the owned process had **Medium integrity RID 8192**, and exit code was **0**. See the [startup result](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261106-191309/result.json>).
- **Additional native interaction limitation:** the separate foreground-window automation phase timed out at `focus(hwnd)` before any caption/button checks ran. It is not counted as passing. The test window subsequently closed; a process scan confirmed no writer processes remained. No app code was changed to work around this diagnostic failure. A separate [post-cleanup integrity check](<C:/Users/userSigma/no-white-writer/build/ui-review-normal-startup-20261106-191309/post-cleanup-integrity.json>) again verified all **23 bundle files** and all **8 book files** unchanged.
- Delivery: [ordinary-folder executable](<C:/Users/userSigma/Downloads/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261106-191309/no_white_writer.exe>) and [complete ZIP](<C:/Users/userSigma/no-white-writer/build/packages/no-white-writer-0.4.1-ui-review-debug-windows-x64-20261106-191309.zip>). Keep the executable together with its DLL/data files; do not launch the Low-integrity build-tree copy or move the executable alone.
- No subagents, Git commits, ACL changes, lock deletion, or termination of preexisting processes. Earlier worktree changes remain intact.
