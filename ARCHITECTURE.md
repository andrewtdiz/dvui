# DVUI Architecture

## Start Here
- Retained UI API surface (Luau + tags + props + classes): `docs/RETAINED_API.md`
- Retained module map: `src/retained/ARCHITECTURE.md`
- Native renderer runtime (window + frame loop + Lua bridge): `src/native_renderer/ARCHITECTURE.md`
- Cross-cutting contracts (rect spaces, dirtying/versions, events): `docs/ARCHITECTURE_CONTRACTS.md`

## Doc Conventions
- Module docs live next to code as `src/**/ARCHITECTURE.md` and should stay short and contract-focused.
- Cross-module invariants live in `docs/ARCHITECTURE_CONTRACTS.md`.
- Public retained API is documented in `docs/RETAINED_API.md`.

## End-to-End Call Flow (Zig -> Luau -> retained)
- Renderer lifecycle loads Luau (optional) and installs a global `ui` table that maps to retained `NodeStore` mutations.
- Each frame drains retained events into Luau `on_event`, calls Luau `update(dt, input_table)` (if present), then renders the retained tree via `retained.render(...)`.
- If retained is not enabled/ready, the native renderer can render an immediate-mode command buffer instead.

## Module Map
- `src/native_renderer/ARCHITECTURE.md`: FFI-facing runtime (Raylib backend + WebGPU + DVUI window), per-frame loop, command-buffer rendering, Luau bridge.
- `src/retained/ARCHITECTURE.md`: retained-mode façade (init/deinit/render/layout/picking).
- `src/retained/core/ARCHITECTURE.md`: retained node graph (`NodeStore`, `SolidNode`) and change tracking.
- `src/retained/style/ARCHITECTURE.md`: Tailwind-like class parsing, color resolution, and applying derived visuals.
- `src/retained/layout/ARCHITECTURE.md`: layout engine (rect computation, flex, intrinsic measurement, anchoring).
- `src/retained/render/ARCHITECTURE.md`: per-frame retained renderer orchestration (layout, hover/hit-test, render traversal).
- `src/retained/render/internal/ARCHITECTURE.md`: internal pipeline (render context, ordering, hover/overlay/interaction).
- `src/retained/events/ARCHITECTURE.md`: event transport (`EventRing`) and retained interaction state machines.
- `src/retained/loaders/ARCHITECTURE.md`: snapshot loaders into a `NodeStore` (currently `ui.json`).

## Deep Dives / Debugging
- `docs/RETAINED.md`: retained architecture notes and call flow details.
- `docs/LAYOUT_TREE_DUMP.md`: debugging dumps for layout tree state.

## Review Notes / Findings
- `docs/luau-findings/`: focused writeups for specific bridge and API hazards.
- `RELEASE_ARCHITECTURE_REVIEW.md`: higher-level release review notes.
- `PERFORMANCE_AUDIT.md` and `MEMORY_AUDIT.md`: targeted audit summaries and followups.
