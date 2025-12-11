# Solid Button Placement Debug – Quick Context

## Issue
- Solid-rendered button appears outside its parent until the window is resized. First paint uses wrong coordinates; resize triggers correct placement.
- Button caption now renders correctly; remaining problem is positional.

## Data Path (JSX → Zig → DVUI)
- Source: `frontend/solid/App.tsx` (nested divs, paragraphs, button).
- Build: `frontend/scripts/solid-plugin.ts` (Solid universal mode) → host ops.
- Runtime: `frontend/solid/runtime/index.ts` + `frontend/solid/runtime/bridge.ts` build HostNodes and schedule flush.
- Flush/serialize: `frontend/solid/host/index.ts` + `frontend/solid/host/flush.ts` emit snapshots/ops and listener ops; `CommandEncoder` builds quad/text commands.
- FFI: `frontend/solid/native/ffi.ts` ↔ `src/integrations/native_renderer/exports.zig` (`setRendererSolidTree` / `applyRendererSolidOps`).
- Store rebuild: `src/integrations/native_renderer/solid_sync.zig` parses JSON/ops into `solid.NodeStore` (`src/integrations/solid/core/types.zig`).
- Layout: `src/integrations/solid/layout/mod.zig` computes flex/layout; nodes keep absolute rects.
- Render: `src/integrations/solid/render/mod.zig`
  - `renderContainer`: draws background (direct) + `dvui.box` with `options.rect` from `node.layout.rect` (parent-relative adjustment).
  - `renderButton`: builds options (padding, zero margin), applies class/visuals, sets `options.rect` from layout rect minus parent rect; uses `dvui.ButtonWidget` and `dvui.labelNoFmt` for caption; pushes click to ring.
- Events: `src/integrations/solid/events/ring.zig` + `frontend/solid/native/adapter.ts` poll/dispatch; `frontend/index.ts` main loop flushes/presents/polls.

## Key Files to Inspect
- JS: `frontend/solid/host/flush.ts`, `frontend/solid/host/index.ts`, `frontend/solid/runtime/index.ts`, `frontend/solid/App.tsx`.
- Zig layout/render: `src/integrations/solid/layout/mod.zig`; `src/integrations/solid/render/mod.zig` (rect → DVUI options in `renderContainer`/`renderButton`); `src/integrations/native_renderer/solid_sync.zig` (snapshot/ops to NodeStore); `src/integrations/solid/core/types.zig` (layout/visual state).
- Support: `src/integrations/solid/render/cache.zig` (paint caching); `frontend/solid/native/adapter.ts` (event polling).

## Current Hypothesis
- Coordinate space mismatch at first paint: DVUI expects rects relative to parent content; initial frame may still feed absolute coords while resize forces a full invalidation. Parent rects might be missing/null on first render or need padding/margin offsets (content rect) rather than raw parent layout. Inspect initial layout timing and how `options.rect` is derived before resize.*** End Patch
