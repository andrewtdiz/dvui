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
│   ├── widgets.zig      # DVUI widget entry point (interactive only)
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
                → updatePaintCache (render/cache, hydrates visual.bg from class when missing)
                → render (render/mod)
                    ├─ direct.zig for all non-interactive nodes (background + children)
                    └─ DVUI widgets for interactive nodes only
```

Dirty region tracking flows through `render/cache.zig` and reused paint geometry when possible.

## Principles

- Single source of truth under `src/solid/`.
- Separation of concerns: core data, layout math, style parsing, rendering, JS bridge.
- Explicit init/deinit and allocator ownership on all structs (see `core/types.zig`).
- Non-interactive elements are always drawn directly; DVUI is reserved for interactive paths so backgrounds are never skipped.
- Class-derived backgrounds are copied into `visual.background` before caching/drawing, ensuring consistent fills even when the DVUI path does not set one.
- Event ring buffer is available for Zig→JS input dispatch; mutation op path covers create/remove/move/set/listen.
