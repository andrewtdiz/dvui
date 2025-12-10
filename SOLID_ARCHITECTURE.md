# Solid → Zig (DVUI) Rendering — Current State

## Data Flow
- **JS/Bun layer** (`frontend/solid/solid-host.tsx`, `frontend/solid/native-renderer.ts`):
  - First frame: JSON snapshot via `setSolidTree`.
  - Incremental: `applyRendererSolidOps` batches (`create`/`move`/`remove`/`set_text`/`set_class` plus new `set_transform`/`set_visual`).
  - Fallback: `commitCommands` binary path (rare).
- **FFI / Native ingress** (`src/native_renderer.zig`):
  - Snapshot rebuild: `rebuildSolidStoreFromJson`.
  - Ops apply: `applySolidOps` → `applySolidOp` with helpers `applyTransformFields`/`applyVisualFields`.
  - Frame loop: `presentRenderer` → `renderFrame` → `solid_renderer.render`; falls back to command buffer if no store.

## Core Structures
- `src/jsruntime/solid/types.zig`
  - `SolidNode` holds `LayoutCache`, `Transform`, `VisualProps`, `class_spec` cache, listeners, and `isInteractive()`.
  - `NodeStore` retained tree (id→node, parent/children), versioning, input state.
- `src/jsruntime/solid/tailwind.zig` / `dvui_tailwind.zig`
  - Tailwind subset parsing (bg/text colors, width/height, padding/margin, flex/justify/align, radius) into `Spec` and DVUI options.

## Rendering Paths (`src/solid_renderer.zig`)
- **Layout pass** (`updateLayouts`, `layoutNode`, `layoutFlexChildren`, `measureNodeSize`, `measureText`):
  - Applies margins/padding, explicit w/h, intrinsic text sizing (measures text children), minimal flex (direction, justify/align, gap). Stores rects in `node.layout.rect`.
- **Direct draw for non-interactive** (`renderNonInteractiveElement`, `drawRectDirect`, `drawTextDirect`, `renderParagraphDirect`):
  - Uses cached rects, transform (scale/translate), optional clip. Colors/radius from `VisualProps` with Tailwind fallback.
- **DVUI path for interactive** (`renderInteractiveElement`, `renderElementBody`):
  - Buttons/inputs/images/text via DVUI widgets to preserve focus/IME/hover state.

## Ops / State Ingest
- `src/native_renderer.zig`
  - `SolidOp` supports `set_transform` (rotation/scale/anchor/translation) and `set_visual` (opacity/corner/background/text color/clip).
  - `applyTransformFields`, `applyVisualFields` write into `SolidNode` state.

## Key Entry Points
- `solid_renderer.render(runtime, store)` — per-frame render.
- `updateLayouts` / `layoutNode` — computes rects before rendering.
- `renderNode` → `renderInteractiveElement` or `renderNonInteractiveElement`.

## Known Gaps / Next Work
- Intrinsic sizing/layout still being tuned: ensure explicit/measured sizes are applied to `div`/`p` so Tailwind backgrounds and flex centering match DOM (outer `w-full h-full`, inner fixed-size box).
- Temporary debug logs in `layoutNode` and `drawRectDirect` trace rects/backgrounds; clean up once layout stabilizes.
