# Solid Logic & DOM Incremental Rendering Architecture

## Current Structure (Unified)

```
src/solid/
├── mod.zig              # Public API: init/render + NodeStore accessors
│
├── core/                # Data + lifecycle
│   ├── types.zig        # SolidNode, NodeStore, Rect, VisualProps, Transform
│   └── dirty.zig        # Version tracking
│
├── layout/              # Geometry only
│   ├── mod.zig          # updateLayouts entry point
│   ├── flex.zig         # Flex child positioning
│   └── measure.zig      # Intrinsic size measurement
│
├── style/               # Tailwind/CSS-ish interpretation
│   ├── tailwind.zig     # Class parsing
│   ├── colors.zig       # Palette
│   └── apply.zig        # Map specs → dvui.Options / VisualProps
│
├── render/              # Drawing subsystem
│   ├── mod.zig          # Render dispatch + dirty-region orchestration
│   ├── direct.zig       # Direct triangle/text draws (non-interactive)
│   ├── widgets.zig      # DVUI widget entry point
│   └── cache.zig        # Paint cache + DirtyRegionTracker
│
└── bridge/              # JS runtime integration
    └── jsc.zig          # QuickJS/Bun bridge stub
```

Other touchpoints:
- `src/jsruntime/solid/mod.zig` now delegates to `solid/mod.zig`.
- Legacy wrappers (`src/solid_renderer.zig`, `src/solid_layout.zig`) and the old `src/jsruntime/solid/*` files are removed.

## Render Pipeline

```
JS DOM mutations → NodeStore (core)
                → updateLayouts (layout)
                → updatePaintCache (render/cache)
                → render (render/mod) → direct (non-interactive) or DVUI widgets
```

Dirty region tracking flows through `render/cache.zig` and reused paint geometry when possible.

## Principles

- Single source of truth under `src/solid/`.
- Separation of concerns: core data, layout math, style parsing, rendering, JS bridge.
- Explicit init/deinit and allocator ownership on all structs (see `core/types.zig`).
