# Production Milestones Context (Solid + Bun FFI + Native Renderer)

This context is for “productionizing” the SolidJS → Bun FFI → Zig native renderer stack, using `frontend/solid/App.tsx` (component harness) as the acceptance surface. The current architecture renders a retained node tree in Zig (`solid.NodeStore`) and bridges events back to JS via a shared-memory ring buffer.

## Current State (What Exists)

- **JS Host Tree**
  - Solid universal runtime (no DOM) produces `HostNode` tree and flushes:
    - full snapshots (`setSolidTree`) and/or
    - mutation batches (`applyOps`) into Zig.
  - Key paths: `frontend/solid/host/*`, `frontend/solid/native/*`, `frontend/index.ts`.
- **Zig Native Renderer**
  - Dynamic lib: `src/integrations/native_renderer/*`
  - Creates a raylib window, owns a DVUI `Window`, and either:
    - renders Solid retained tree (`solid.render(...)`), or
    - falls back to simple command-buffer rendering (`renderCommandsDvui`).
- **Retained Solid Engine (Zig)**
  - State: `src/integrations/solid/core/types.zig` (`NodeStore`, `SolidNode`)
  - Layout: `src/integrations/solid/layout/*` (custom flex + tailwind subset)
  - Render: `src/integrations/solid/render/mod.zig` (mix of direct draws + DVUI widgets for interactivity)
  - Events: `src/integrations/solid/events/mod.zig` (ring buffer, polled from JS)

## Production Readiness Definition (Minimum Viable)

1. **Crash-free lifecycle**
   - Closing the window exits cleanly without Bun panics/segfaults.
   - No re-entrant/unsafe FFI calls during callbacks.
   - No memory leaks during resync/error loops.
2. **Correct window sizing + DPI**
   - Logical size vs framebuffer size handled explicitly.
   - Resizing does not “fight” user drag or jump sizes.
   - Text and geometry remain crisp on HiDPI and after resize.
3. **Layout correctness for the harness**
   - Cards (`w-96`), flex column/row, gaps, padding, and `w-full` behave as expected.
   - No “fixes itself after resize” layout bugs.
4. **Rendering correctness**
   - `overflow-hidden` (clipChildren) and scroll view clipping work reliably.
   - Text baselines/line heights are consistent (no vertical clipping).
5. **Interaction correctness**
   - Click, focus/blur, keyboard events, pointer/drag/drop, and scroll events dispatch reliably.
   - Focus trap / roving focus behaviors work for harness components.
6. **Foundation for accessibility**
   - ARIA props are captured and can be mapped to AccessKit (even if partial at first).

## Known Pain Points (Observed / Reported)

- **Bun segfault on close**: likely caused by re-entrant FFI teardown (calling `destroyRenderer` from inside a native→JS callback) or unsafe lifetime ordering of JSCallbacks/native resources.
- **Resize/DPI issues**: pixel scaling “gets messed up” and window jumps size; indicates logical-vs-physical size confusion and/or a resize feedback loop between `window_resize` events and `resizeRenderer`.
- **Overflow/clipping/render bugs**: visible bleed and incorrect constraints indicate layout inaccuracies, coordinate-space mismatches (direct draws vs DVUI widget scopes), and/or incorrect bounds used for scissor decisions.
- **Inline `style` props are effectively ignored**:
  - Harness components rely on `style` for key visuals (e.g. Progress bar width %, virtual list translateY offset).
  - Current host serialization only understands class-driven Tailwind + explicit numeric props (`translateX`, etc), not `style={{ ... }}`.
- **Portal/modal semantics missing**:
  - `portal` is treated as a pass-through node in JS flush (`frontend/solid/host/flush.ts`), so it never reaches the Zig store and cannot provide layering or modal focus trapping.
- **Flex gaps present, but `justify-between/around` and flex-grow/shrink are incomplete**:
  - Tailwind parses these tokens, but the flex layout implementation currently only handles start/center/end positioning and fixed-size items.

## Reference Acceptance Surface (Harness)

- `frontend/solid/App.tsx` exercises:
  - focus trapping + roving tabIndex
  - scroll region + virtual list
  - drag/drop + pointer events
  - overlays/portal-style layering
  - general flexbox layout + spacing + clipping

## Notes for Agents

- Prefer fixing root coordinate model and DPI semantics before patching per-component rendering.
- Avoid introducing “magic offsets”; aim for a single, consistent coordinate space contract:
  - what units `layout.rect` uses,
  - what units DVUI widget `options.rect` expects in each render path,
  - what units clipping/scissor expects.
- Treat `frontend/solid/App.tsx` as the “golden” acceptance surface: implement only what the harness needs first (style width/transform, portal layering, justify-between), then expand coverage.
