# Shelf Card Layout and Caption Divider Design

Approved in the 2026-11-05 confirmation: preserve the existing rounded 3:4 book outline, not the former outline-plus-external-metadata occupancy. Implement inline without subagents or Git commits; preserve all prior uncommitted changes.

## Layout

- The 36px custom titlebar retains brand/title, blank drag area and window controls only. Editor navigation/status are unchanged.
- The shelf's content header places 全部作品/counts on the left and the existing sort/settings/new actions on the right. Search and grid/list controls form the next row, remaining usable at the 900px native minimum width.
- Existing book outlines stay 220px wide with a 3:4 ratio (293⅓ logical px high). Move statistics and relative update time inside the lower-left content area; place the existing 28px hover/focus-aware menu inside the lower-right area. Remove the decorative 不白写作 imprint, but keep the titlebar brand.
- Make the dashed creation outline exactly match the book outline. Grid occupancy now matches this visible outline rather than reserving the obsolete external metadata footer; preserve 20px column and 26px row gaps. List view remains 76px high.
- Creation hover/keyboard focus shows a subtle theme-derived background, accent dashed border/add symbol and a 创建新作品 tooltip. Keep creation/export guards and the existing dialog callback.

## Divider root cause and fix

The page-local titlebar paints a bottom border, but WindowFrame paints an opaque WindowControls layer above it. This clears the line in the rightmost 138px. Draw the same bottom rule in the shared controls' foreground, after their backgrounds and hover/press fills. Keep the 36px bar, 46px buttons, hit areas and native commands unchanged. Do not add another titlebar or hard-coded positional compensation.

## Verification and boundaries

Test actual rectangles and raster pixels, not only widget presence: controls outside the caption and beside 全部作品; metadata/menu inside the book outline; book and creation outlines equal before/after hover; divider continuous under all three window buttons at rest/hover/press in light/dark/custom themes and scaled rasterization. Preserve keyboard/right-click, menu opacity, filtering, native close/IME/save/export guards. Run targeted RED/GREEN, full serial suite, analysis/format/diff checks, Windows build and ordinary-folder native startup/window checks. Do not change user works, existing processes, locks or ACLs; do not use Low-integrity build output as the user entry.
