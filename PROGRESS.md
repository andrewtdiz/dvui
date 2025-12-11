# Solid Rendering Debug Progress

## What We Fixed
- Solid runtime now uses the host bridge for all create/insert/set operations, emitting mutation ops promptly (`frontend/solid/runtime/index.ts`, `frontend/solid/host/index.ts`).
- Removed periodic full snapshots; snapshots occur only for initial sync or recovery, with incremental ops preferred (`frontend/solid/host/flush.ts`).
- Text-only elements render with a transparent background fallback, so `<p class="text-white">…</p>` shows correctly (`src/integrations/solid/render/mod.zig`).
- Button rendering now respects the layout rect and stays inside the container (`src/integrations/solid/render/mod.zig`).

## Current Focus
- Validate button placement and caption rendering. Latest debug logs show the button rect `{ x=384, y=257, w=84.8, h=32 }` matching its layout and rendering inside the red container.

## Helpful Debug Info
- Button debug logs (first few buttons) print: node id, class, caption, layout rect, parent rect, options rect, fill/text colors. See `renderButton` in `src/integrations/solid/render/mod.zig`.
- Paragraph logs (first few) confirm text rects, colors, and content, also in `render/mod.zig`.

## Files to Watch
- Rendering: `src/integrations/solid/render/mod.zig`
- Layout: `src/integrations/solid/layout/mod.zig`
- Flush/mutations: `frontend/solid/host/flush.ts`
- Runtime bridge: `frontend/solid/runtime/index.ts`, `frontend/solid/runtime/bridge.ts`
