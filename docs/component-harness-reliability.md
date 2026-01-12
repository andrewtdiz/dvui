# Component Harness Reliability Review

## Scope
This document summarizes visible UI issues in the component harness screenshot, then ties them to likely causes in the Solid + native renderer pipeline. It focuses on interaction reliability, event delivery, and visual correctness so the harness can be trusted for validation work.

## Observed UI Issues (Screenshot)
- Scroll region items render outside the scroll container and appear un-clipped.
- Drag + Drop card contents overflow to the right, breaking the card boundary.
- Long horizontal lines extend outside their cards (looks like separators or borders bleeding across columns).
- Several headings and labels look vertically clipped or misaligned (ex: “Focus + Keyboard”, “Inputs + Toggles”, “Tabs”).
- Small stray text fragments appear near some controls (looks like partially-rendered labels).
- Overall text sharpness appears inconsistent, and blur worsens after resize.

## Functional Breakdowns

### 1) Click/state updates are not firing
Components such as Switch, Tabs, Toggle, Pagination, and Stepper rely on click events to update their internal state. The click events are not making it back into Solid, so the UI stays static.

**Primary cause**
- `NativeRenderer.pollEvents` expects a 24-byte event ring header that includes dropped-event counters.
- `getEventRingHeader` in the native renderer exports a 16-byte header (no dropped counters).
- Because `pollEvents` compares sizes and returns early, the event ring is never consumed and no handlers run.

**Files to review**
- `frontend/solid/native/adapter.ts`
- `src/integrations/native_renderer/exports.zig`
- `src/integrations/solid/events/mod.zig`

**Resolution direction**
- Align the event ring header size across JS and Zig (either expand the Zig header to include dropped counts, or make JS tolerant of the smaller header).
- Add a guard log on header-size mismatch to surface the problem immediately.

### 2) Event kind coverage mismatch (scroll/drag/pointer)
The harness uses drag-and-drop and scroll events, but the Solid event ring does not currently emit these kinds.

**Evidence**
- JS mapping includes `scroll` but not drag or pointer events.
- Zig’s Solid `EventKind` enum does not define scroll or drag events at all.
- The retained event ring *does* define scroll/drag/pointer events, which suggests the Solid integration is behind.

**Files to review**
- `frontend/solid/native/adapter.ts`
- `src/integrations/solid/events/mod.zig`
- `src/retained/events/mod.zig`

**Resolution direction**
- Expand Solid’s `EventKind` enum and event ring to include drag, drop, scroll, and pointer events.
- Update JS `EVENT_KIND_TO_NAME` to map the new kinds.
- Ensure `solid.render` pushes the relevant events for nodes that register listeners.

### 3) Listener registration + snapshots
Listeners are sent as `listen` ops via `applyRendererSolidOps`, but snapshots don’t contain listener information. Any failure of `applyOps` leaves the UI without listeners until the next mutation flush.

**Resolution direction**
- Add logging for listener ops on snapshot + mutation sync.
- Consider re-sending listener ops after a snapshot even if no mutations are pending.
- Add a `listen` coverage test that asserts every handler registered in JS exists in the native NodeStore.

## Resize / DPI Blurriness
The renderer is initialized with a fixed size and doesn’t respond to runtime resize or DPI scale changes, so the native window scales the content and blurs text.

**Evidence**
- `frontend/index.ts` calls `renderer.resize` once and never updates it.
- The native renderer does not observe window-size changes and reflow the DVUI window.

**Resolution direction**
- Add per-frame detection of `getScreenWidth`, `getScreenHeight`, and `getWindowScaleDPI` in the native window loop.
- Emit a `window_resize` event and call `renderer.resize` from JS, or update the renderer size directly on the native side.
- Maintain a distinction between logical size and physical pixel size so layout uses logical units while render targets use physical resolution.

## Visual Clipping + Layout Reliability
The screenshot suggests that clipping and width constraints are not being enforced consistently.

**Likely contributors**
- `overflow-hidden` is expressed via class names but is not converted into `clipChildren` in the Solid host props.
- `Separator` uses `w-full`, but the layout system may treat it as full window width rather than parent width.
- Some tailwind-derived layout rules (flex gaps, width constraints) may be partially implemented or missing.

**Resolution direction**
- Map `overflow-hidden` class to `clipChildren` on nodes that should clip (Scrollables, cards).
- Add a targeted style map for `w-full` and constrained width behavior inside flex containers.
- Add a layout sanity check for each card in the harness (snapshot positions against expected bounds).

## Suggested Fix Plan (High Level)
1. **Event ring alignment**: unify header format between JS + Zig and ensure `pollEvents` always consumes the ring.
2. **Event coverage**: port scroll/drag/pointer events into the Solid event ring and JS mapping.
3. **Listener validation**: add debug telemetry to confirm `listen` ops are applied and active.
4. **Resize/DPI handling**: propagate window size + DPI changes to the renderer each frame.
5. **Clipping/layout polish**: map `overflow-hidden` → `clipChildren`, and validate width constraints for separators and list content.

## Key Files Reviewed
- `frontend/index.ts`
- `frontend/solid/App.tsx`
- `frontend/solid/native/adapter.ts`
- `frontend/solid/host/index.ts`
- `frontend/solid/components/switch.tsx`
- `frontend/solid/components/tabs.tsx`
- `frontend/solid/components/list.tsx`
- `src/integrations/native_renderer/exports.zig`
- `src/integrations/native_renderer/window.zig`
- `src/integrations/solid/events/mod.zig`
- `src/retained/events/mod.zig`
