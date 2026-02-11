# Tailwind JSON (DVUI)

Minimal, editor-friendly JSON encoding for the core DVUI Tailwind-style class subset, designed for:

- Figma-like editing (structured fields)
- `class` string generation/parsing
- Sparse JSON output (defaults omitted; only overrides stored)

This is not full TailwindCSS. It targets the token set documented in `DVUI_DOCS.md`.

## Node Shape (Recommended)

This spec defines a set of optional styling fields that live directly on the node object.

```json
{
  "tag": "div",
  "key": "StartMenu",
  "classExtra": [],
  "children": []
}
```

## Core Fields

All fields are optional. If a field is missing, it does not emit any class tokens.

### Sparse Example (Overrides Only)

```json
{
  "tag": "div",
  "key": "StartMenu",
  "layout": {
    "abs": true,
    "anchor": "center",
    "inset": { "left": { "pct": 0.5 }, "top": { "pct": 0.5 } },
    "size": { "w": 420, "h": 320 }
  },
  "flex": { "dir": "col", "items": "center" },
  "bg": "neutral-950",
  "border": { "color": "neutral-700" },
  "rounded": "xl"
}
```

### Full Example (All Core Fields)

```json
{
  "tag": "div",
  "key": "StartMenu",
  "layout": {
    "abs": true,
    "anchor": "center",
    "inset": { "left": { "pct": 0.5 }, "top": { "pct": 0.5 } },
    "size": { "w": 420, "h": 320 }
  },
  "flex": { "dir": "col", "items": "center", "justify": "center", "gap": 2 },
  "margin": { "t": 2 },
  "pad": { "x": 6, "y": 3 },
  "bg": "neutral-950",
  "border": { "color": "neutral-700", "w": 2 },
  "rounded": "xl",
  "opacity": 60,
  "z": 10,
  "text": {
    "color": "neutral-300",
    "size": "lg",
    "align": "center",
    "wrap": "nowrap",
    "font": { "family": "ui", "weight": "medium", "slant": "italic", "render": "auto" },
    "outline": { "w": 2, "color": "black" }
  },
  "hidden": true,
  "clip": true,
  "classExtra": []
}
```

### Value Conventions

Sizing:

- `layout.size.w` / `layout.size.h`
  - number: raw pixels (emits `w-[N]` / `h-[N]`)
  - `"full"`: emits `w-full` / `h-full`
  - `{ "tw": number }`: Tailwind-style dimension scale (emits `w-N` / `h-N`)

Insets:

- `layout.inset.*`
  - number: raw pixels (emits `left-[N]` etc)
  - `{ "pct": 0.0..1.0 }`: percent of parent axis (emits `left-[N%]` etc)

Spacing:

- `margin`, `pad`, and `flex.gap` are Tailwind-style scale numbers (emits `mt-N`, `px-N`, `gap-N`, etc).
  - These are scaled by DVUI `spacing_unit` at parse time (see `DVUI_DOCS.md`).
- `margin`
  - `margin.all`: emits `m-N`
  - `margin.x` / `margin.y`: emits `mx-N` / `my-N`
  - `margin.t` / `margin.r` / `margin.b` / `margin.l`: emits `mt-N` / `mr-N` / `mb-N` / `ml-N`

Border:

- `border.color`: a DVUI `<colorToken>` (emits `border-<colorToken>`)
- `border.w`: raw pixels (emits `border-N`)
  - If `border.color` is present and `border.w` is missing, `toClass` should still emit `border` to enable the border with default width.

Opacity:

- `opacity`: integer `0..100` (emits `opacity-N`)

Z-index:

- `z`: integer (emits `z-N` or `-z-N`)
- `z`: `"base" | "dropdown" | "overlay" | "modal" | "popover" | "tooltip"` (emits `z-<layer>`)

Typography:

- `text.size`: `xs|sm|base|lg|xl|2xl|3xl` (emits `text-*`)
- `text.align`: `left|center|right` (emits `text-left|text-center|text-right`)
- `text.wrap`: `"normal" | "nowrap" | "break-words"` (emits `text-nowrap` or `break-words`; `normal` emits nothing)
- `text.font.family`: `ui|mono|game|dyslexic` (emits `font-*`)
- `text.font.weight`: `light|normal|medium|semibold|bold` (emits `font-*`)
- `text.font.slant`: `normal|italic` (emits `not-italic|italic`)
- `text.font.render`: `auto|msdf|raster` (emits `font-render-*`)
- `text.outline.w`: pixels (emits `text-outline-N`)
- `text.outline.color`: `<colorToken>` (emits `text-outline-<colorToken>`)

Visibility:

- `hidden: true` emits `hidden`
- `clip: true` emits `overflow-hidden`

## Defaults And Sparsity

When serializing editor state to JSON:

- Omit any field that would not emit tokens.
- Omit values that are equivalent to “no token” defaults (example: don’t store `hidden: false`).
- Emit explicit “reset” tokens only when you intentionally need them (example: `text.font.slant = "normal"` emits `not-italic`).

## `classExtra`

`classExtra` preserves class tokens that are either:

- Unknown to DVUI, or
- Known but intentionally not modeled yet (example: `hover:*`, `cursor-*`, `transition*`, etc)

`toClass` appends `classExtra` after emitting canonical tokens from the structured fields.

## Conversion Contract

- `fromClass(class)` parses recognized tokens into structured fields and stores remaining tokens in `classExtra`.
- `toClass(node)` emits modeled tokens in a canonical order and then appends `classExtra`.
- Output is canonical/minimized and may omit redundant “default” tokens (semantic round-trip, not byte-for-byte token preservation).
