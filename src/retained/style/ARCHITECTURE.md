# Retained Style (`style/`)

## Responsibility
Bridges the Tailwind-like class contract and retained node style inputs into the derived visuals used by rendering. Also provides shared color helpers and a palette table.

## Public Surface
- Tailwind-like contract: `tailwind.parse(...)`, `tailwind.applyHover(...)`, `tailwind.resolveColor(...)`, and `tailwind.applyToOptions(...)`.
- Retained adapters: `apply.applyClassSpecToVisual(...)` and `apply.applyVisualPropsToOptions(...)`.

## High-Level Architecture
- `mod.zig` is a small re-export hub.
- `apply.zig`: converts between `dvui.Color` and retained `PackedColor`, applies resolved `tailwind.Spec` onto `SolidNode.visual`, applies `VisualProps` onto `dvui.Options`, and delegates full option filling to `tailwind.applyToOptions(...)` when using DVUI widgets.
- `tailwind.zig` is the public Tailwind-like API: parses class strings into `Spec`, caches parsed specs, resolves theme/palette colors, and applies hover variants.
- `colors.zig` is a static palette table used by Tailwind parsing.

## Core Data Model
- `tailwind.Spec`: the style contract parsed from `SolidNode.class_name`.
- `types.VisualProps`: style fields that exist on each node as inputs (`visual_props`) and as derived/effective values (`visual`).
- `types.PackedColor`: packed RGBA used throughout retained rendering and caching.

## Critical Assumptions
- `applyClassSpecToVisual` always writes `visual.z_index` so removing a class resets z-index to its default.
- Opacity is applied by multiplying alpha in `packedColorToDvui(...)` and clamping to valid ranges.
- `colors.zig` is treated as generated/static data.
