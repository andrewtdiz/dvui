# Critical Frontend Tasking (before next feature work)

Sources reviewed: `SOLID_ARCHITECTURE.md`, `FRONTEND_FEATURES.md`, `FEATURE_ROADMAP.md`, `FEATURE_PRIORITY.md`, `GAP_ANALYSIS.md`, `DEBUG_FINDINGS.md`, `SOLID_TS_REARCHITECTURE.md`, `docs/NATIVE_RENDERER_REARCHITECTURE.md`, key Solid host/runtime/native files under `frontend/solid/`, and the Zig render/layout/event pipeline in `src/solid/`.

## Itemized Critical Tasks & Implementation Guidance
- **Unblock reliable input events (click/focus/input/hover)**  
  - Emit ring-buffer events for every registered listener, not just clicks: extend `render/mod.zig` button/input/render paths to call the appropriate `EventRing.push*` helpers and include detail payloads (e.g., input text, key info) for JS handlers.  
  - Align JS polling with Zig ring layout: keep `EventEntry` size (16 bytes) and header copy contract in sync between `src/native_renderer/exports.zig`/`src/solid/events/ring.zig` and `frontend/solid/native/adapter.ts`; add a regression test around `NativeRenderer.pollEvents` using the current header copy API.  
  - Ensure runtime listener registration survives prop updates: `frontend/solid/host/index.ts` already emits `listen` ops on create; add a branch in `setProperty` to emit `listen` when `on*` handlers are added after creation, and keep `flush.ts` listener re-sync path intact after snapshots.

- **Close Tailwind/layout gaps for foundational geometry**  
  - Extend `src/solid/style/tailwind.zig` to cover the critical classes called out in `FEATURE_ROADMAP.md`: fractional widths (`w-1/2`, `w-1/3`, etc.), min/max constraints (`min-h-screen`, `max-w-*`, `min-w-full`), and `space-x-*`/`space-y-*` spacing tokens. Wire spacing into `layout/flex.zig` so gaps render identically to Tailwind expectations.  
  - Verify flex alignment and fill-direction handling with real nodes: add focused tests/demos in `frontend/solid/solid-entry.tsx` that exercise justify/align/gap plus per-side padding to confirm `layout/mod.zig` respects the new size tokens.  
  - Keep class → visual propagation consistent: `render/mod.zig` calls `applyClassSpecToVisual`—expand the class spec to include z-index and overflow flags once parsed (see below).

- **Implement z-order and clipping (blocked today)**  
  - Parse z-index classes and store on `SolidNode.visual.z_index`; sort siblings by z before painting in `render/mod.zig`, and ensure `DirtyRegionTracker` respects the sorted order.  
  - Honor `clip_children`/overflow-hidden: when a node sets `clipChildren` (via `set_visual` or Tailwind `overflow-hidden`), wrap child rendering in a dvui clip rect (`dvui.pushClipRect` or Options clip) so scrollable/overlay layouts cannot bleed.  
  - Add tests/demos: layered modals/tooltips to confirm z-order; clipped scrollable panel with children exceeding bounds.

- **Stabilize text/input handling**  
  - Fix the input buffer length bug noted in `DEBUG_FINDINGS.md`: in `renderInput`/`InputState`, never set `text_len` to capacity; track the actual input length and push `input` events with the correct detail slice.  
  - Ensure text alignment/color remain in sync with class parsing: keep `text-*` alignment and color tokens mapping through `tailwind.zig` → `render/mod.zig` paragraph/text paths, and verify wrapping works with the current `drawTextDirect` logic.  
  - Add minimal snapshots for `<Show>/<For>/<Switch>` to catch ordering/keyed list regressions (from `FEATURE_ROADMAP.md` critical conditional rendering validation).

- **Ship minimum viable scroll containers**  
  - Parse `overflow-hidden/scroll/auto` plus axis variants in `tailwind.zig`; map to a scroll container flag on the node.  
  - Introduce a scroll viewport path in `render/mod.zig`: measure child content, clamp by viewport, apply clip, and dispatch scroll input events (`wheel`/drag) back through the event ring. Start with vertical scroll, one axis only, to keep scope contained.  
  - Provide a demo panel in `frontend/solid/solid-entry.tsx` that overflows and uses mouse wheel to validate Zig↔JS event plumbing.

- **Animation/tween readiness for transform/alpha**  
  - Confirm end-to-end support for `set_transform`/`set_visual` from JS: host already emits the ops; ensure `solid_sync.zig` fields map into `SolidNode.transform`/`visual` and that `direct.zig` uses scale/rotation/translation consistently for quads/text.  
  - Add a tiny tween helper on the JS side (e.g., frame-based lerp using `util/frame-scheduler.ts`) to animate position/scale/opacity, and keep `flush` cadence predictable (avoid spamming full snapshots—mutations only).  
  - Create a visual smoke test: spinning/tweening icon plus fade-in/out text to validate anchor/pivot + alpha paths.

- **Prep for deeper renderer split and maintainability**  
  - Follow `docs/NATIVE_RENDERER_REARCHITECTURE.md` to move the monolithic `src/native_renderer.zig` into the `src/native_renderer/` modules; this keeps FFI exports stable while isolating solid sync/render/event code for future feature work.  
  - After the split, update `build.zig` import (`native_renderer/mod.zig`) and keep the comptime export block to preserve the DLL surface.
