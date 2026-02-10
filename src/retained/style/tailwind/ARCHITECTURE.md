# Tailwind Parser (`style/tailwind/`)

## Responsibility
Parses Tailwind-like class strings into a structured `Spec` that drives both retained layout and retained rendering. This directory holds the parser and the `Spec` type definitions.

## Public Surface
- `Spec` (`types.zig`) is the parsed contract consumed by layout and render.
- Parser entrypoints are called via `src/retained/style/tailwind.zig` (this directory is the implementation).

## High-Level Architecture
- `types.zig` defines `Spec` and its supporting enums/unions (color references, sizing/insets, typography, transitions, flex config, hover fields).
- `parse.zig` tokenizes the class string (whitespace-separated), handles `hover:` prefixes, and dispatches to specialized parsers.
- `parse_layout.zig` parses layout-related tokens (spacing, sizing, insets, borders, radius, flex, z-index, opacity, cursor, scale, transitions).
- `parse_color_typography.zig` parses color and typography tokens (theme roles, palette names, font selection, render mode, wrapping/alignment).

## Core Data Model
- `Spec` (in `types.zig`) is the single contract: layout (position/insets/size/margins/padding/border/radius/gap/scale/hidden/scroll/clip), flex, colors (`ColorRef`), typography, interaction (`cursor`, `opacity`, `z_index`), transitions, and `hover_*` variants.

## Critical Assumptions
- Theme tokens come from `dvui.Theme.Tokens` (spacing/dimensions/radii/z-layers/color roles/typography).
- Palette colors come from `src/retained/style/colors.zig`.
- Unrecognized tokens are ignored.
- Hover variants are stored in `Spec` and only applied by `tailwind.applyHover(...)` when a node is hovered.
