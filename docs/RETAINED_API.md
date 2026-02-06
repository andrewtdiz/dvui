# Retained UI API (Luau + Tailwind-like Classes)

This document describes the **current, supported API surface** for DVUI’s retained renderer when driven from **Luau via SolidLuau**: **tag names**, **node properties (“attributes”)**, and **Tailwind-like class names**.

## Mental model

- A UI tree is built in Luau as nested tables (“nodes”).
- Each element node has a string `tag` (e.g. `"div"`, `"button"`) and optional styling via `class`.
- DVUI stores these into a retained `SolidNode` graph (`src/retained/core/node_store.zig`) and renders them each frame.
- Only a small set of tag strings have specialized renderers; unknown tags are treated as generic containers.

## Node shape (Luau)

The DVUI app side uses SolidLuau’s DSL (`deps/solidluau/src/ui/dsl.luau`). The local project’s `UINode` type is defined in `luau/ui/types.luau`.

Common fields you can use:

- `tag: string` (required for element nodes)
- `class: string | () -> string` (optional)
- `visual: { ... }` (optional; see “Prop keys”)
- `transform: { ... }` (optional)
- `scroll: { ... }` (optional)
- `anchor: { ... }` (optional)
- `image: { ... }` (optional)
- `src: string | () -> string` (optional)
- `listen: {string} | () -> {string}` (optional)
- `children`: strings/numbers/booleans, functions returning those, or nested nodes
- `scale: number | () -> number` (optional; maps to transform scale)
- Event handlers as fields on the node table (e.g. `onClick = function(payload, id, kind) ... end`)

### Quick example

```luau
local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag

local function App()
  return Tag.div({ class = "w-full h-full bg-neutral-950 flex items-center justify-center" }) {
    Tag.button({
      class = "px-4 py-2 rounded bg-neutral-800 hover:bg-neutral-700 text-white cursor-pointer transition duration-150 ease-in-out",
      onClick = function(_, id) print("clicked", id) end,
    }) { "Click me" },
  }
end

return App
```

## Tag names

### Where tags come from

- Tag names are created in Luau via the SolidLuau DSL (e.g. `Tag.div`, `Tag.button`), and stored as strings in `SolidNode.tag` (`src/retained/core/node_store.zig`).
- DVUI dispatches on `SolidNode.tag` to specialized renderers (`src/retained/render/internal/renderers.zig`).

### Supported tags (specialized renderers)

These tags have dedicated rendering behavior:

- `div`
  - Primary layout container.
  - Draws background/border (via `bg-*`, `border*`, `rounded*`, or `visual.*`).
  - Can emit `pointerdown`/`pointerup` events **when** you attach `onMouseDown`/`onMouseUp`.
- `button`
  - Interactive button.
  - Button caption is collected from descendant text children (strings / dynamic strings).
  - Emits `click` (via `onClick`), and can emit `pointerdown`/`pointerup` when listeners are present.
- `p`, `h1`, `h2`, `h3`
  - Paragraph/headings with built-in word wrapping.
  - Text is collected from descendant text nodes (strings / dynamic strings).
  - `h1`/`h2`/`h3` force a heading font style; `p` uses whatever typography classes you provide (or theme defaults).
- `image`
  - Renders an image from a required source string.
  - Source is `src` or `image.src` (stored in `SolidNode.image_src`).
  - Supports `image.tint` and `image.opacity`.
- `icon`
  - Renders an icon from `src` (same underlying `SolidNode.image_src` field).
  - Icon glyph/kind configuration exists in `SolidNode` but is **not currently exposed** to Luau (so `src` is the supported path).
- `triangle`
  - Draws an upward-pointing filled triangle within the node rect.
  - Color comes from `bg-*` or `visual.background`.
- `input`
  - Interactive single-line text input.
  - Emits `input`, `focus`, `blur`, and `enter` events (see “Events”).
  - Maintains internal input state in the node (buffer + caret).
- `slider`
  - Interactive 0..1 slider.
  - Emits `input`, `focus`, and `blur`.
  - Slider “value” is stored as text internally and parsed as a float.

### Generic tags (no specialized renderer)

Any other tag string is accepted by the DSL, but currently renders as a **generic transparent container**:

- Children render, but there is no built-in background/border/text drawing for the container itself.
- Hover styling (`hover:*`) and cursor styling (`cursor-*`) can still work (hover is computed via hit testing).
- Pointer down/up and click dispatch are **not** implemented for generic tags.

### Reserved internal tags

These tags are used internally by SolidLuau’s renderer:

- `text` (created for string/number/boolean children; becomes a retained text node)
- `slot` (created for control-flow anchors like `For` and `Show`)

You generally should not create these directly.

## Prop keys (“attributes”)

UI nodes use a single flat table of keys; `props = { ... }` is not supported.

SolidLuau forwards a small, explicit set of node keys to the DVUI binding (`src/native_renderer/luau_ui.zig`). Other keys are ignored by the adapter.

### `class`

- `class = "..."` stores a whitespace-separated class string into `SolidNode.class_name`.
- Classes are parsed on-demand into a `tailwind.Spec` (`src/retained/style/tailwind/parse.zig`) and applied in layout/render.

### `src: string`

Sets the node source string (used by `image` and `icon`).

Example:

```luau
Tag.image({ class = "w-16 h-16", src = "assets/sprite.png" })
```

### `image: { src?: string, tint?: number, opacity?: number }`

Image-specific configuration:

- `src` (string): same as top-level `src`
- `tint` (number): packed color `0xRRGGBBAA`
- `opacity` (number): 0..1

Example:

```luau
Tag.image({
  class = "w-16 h-16",
  image = { src = "assets/sprite.png", tint = 0xffffffff, opacity = 0.9 },
})
```

### `visual: { ... }`

Explicit visual overrides. Supported keys:

- `opacity: number` (usually 0..1)
- `cornerRadius: number` (logical pixels)
- `background: number` packed `0xRRGGBBAA`
- `textColor: number` packed `0xRRGGBBAA`
- `textOutlineColor: number` packed `0xRRGGBBAA`
- `textOutlineThickness: number` (logical pixels)
- `clipChildren: boolean`
- `fontRenderMode: "auto" | "msdf" | "raster"`

Notes:

- Tailwind classes override `background`, `textColor`, `textOutline*`, `cornerRadius`, `opacity`, and `clipChildren` **when present**.
- Border color is currently **Tailwind-only** (`border-*`); there is no `visual.borderColor`.
- `fontRenderMode` is an override stored separately from `visual`; `"auto"` clears the override.

### `transform: { ... }` and `scale`

Transform affects rendering (and child coordinate space), not layout measurement.

Supported keys:

- `scale: number` (uniform)
- `scaleX: number`
- `scaleY: number`
- `rotation: number` (radians)
- `anchorX: number` (0..1)
- `anchorY: number` (0..1)
- `translateX: number` (logical pixels)
- `translateY: number` (logical pixels)

You can also set a top-level `scale` on the node (outside `transform`) which maps to `transform.scale`.

Note: Tailwind also supports a `scale-*` class which is a **layout scale** (it affects layout and sizing). Transform scale and layout scale are different and multiply together when both are used.

### `scroll: { ... }` (accepted; currently not applied)

Accepted keys:

- `enabled: boolean`
- `scrollX: number`
- `scrollY: number`
- `canvasWidth: number`
- `canvasHeight: number`
- `autoCanvas: boolean`

These values are stored on the node, but **scrolling is not currently wired into layout/render**.

### `anchor: { ... }` (accepted; currently not applied)

Accepted keys:

- `anchorId: number`
- `side: "top" | "bottom" | "left" | "right"`
- `align: "start" | "center" | "end"`
- `offset: number`

These values are stored on the node, but **anchored placement is not currently applied**.

## Events

Event handlers are installed by putting functions on the node table. The handler signature is:

```luau
function(payload, id, kind) ... end
```

### Supported handler fields

- `onClick` → `click` (button only)
- `onMouseEnter` → `mouseenter` (any element)
- `onMouseLeave` → `mouseleave` (any element)
- `onMouseDown` → `pointerdown` (div/button only)
- `onMouseUp` → `pointerup` (div/button only)
- `onInput` → `input` (input/slider)
- `onFocus` → `focus` (focusable nodes; input/slider also emit)
- `onBlur` → `blur` (focusable nodes; input/slider also emit)
- `onEnter` → `enter` (input only)

### Payload format

The payload passed to Luau depends on event kind:

- For `input`/`enter`/`keydown`/`keyup`: UTF-8 text content (string)
- For pointer/drag events (`pointerdown`/`pointermove`/`pointerup`/`pointercancel`/`dragstart`/`drag`/`dragend`/`dragenter`/`dragleave`/`drop`): a table
  - `x: number`
  - `y: number`
  - `button: number`
  - `modifiers: { shift: boolean, ctrl: boolean, alt: boolean, cmd: boolean }`
- For `click`/`focus`/`blur`/`mouseenter`/`mouseleave`: empty string (`""`)

## Tailwind-like classes

Classes are parsed by `src/retained/style/tailwind/parse.zig` into a `tailwind.Spec` struct and applied in layout + rendering.

Unknown tokens are ignored (no errors).

### Design-token scales (DVUI Theme)

These come from `dvui.Theme.Tokens` (`src/theming/theme.zig`):

- Spacing unit: `4.0` (used by `m-*`, `p-*`, `gap-*`, and non-bracket `top-*`/`left-*`/etc)
- Dimension unit: `spacing_unit` (used by numeric `w-*` / `h-*`)
- Default border width: `1.0` (used by `border`, `border-x`, etc)
- Default z-index: `0` (used by `z-auto`)

### Colors

Supported patterns:

- `bg-{name}` (background)
- `text-{name}` (text color)
- `border-{name}` (border color)
- Hover variants: `hover:bg-{name}`, `hover:text-{name}`, `hover:border-{name}`

Where `{name}` can be:

- A theme role token: `content`, `window`, `control`, `highlight`, `err`, `app1`, `app2`, `app3`
- A palette token from `src/retained/style/colors.zig` (e.g. `neutral-950`, `amber-600`, `slate-900`, `white`, `transparent`)

### Typography

Font size/style tokens (theme-mapped):

- `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`

Font family/weight/slant:

- `font-light`, `font-normal`, `font-medium`, `font-semibold`, `font-bold`
- `font-ui`, `font-mono`, `font-game`, `font-dyslexic`
- `italic`, `not-italic`

Font render mode:

- `font-render-auto`, `font-render-msdf`, `font-render-raster`

Text layout:

- `text-left`, `text-center`, `text-right`
- `text-nowrap` (disable wrapping)
- `break-words`

Text outline (custom extension):

- `text-outline-{color}` (uses the same `{name}` rules as colors)
- `text-outline-{N}` / `text-outline-{Npx}` / `text-outline-[Npx]`
- Hover variants: `hover:text-outline-*`

### Layout & positioning

Display & direction:

- `flex` (enables flex layout)
- `flex-row`, `flex-col` (direction; requires `flex` to actually lay out as flex)

Justification/alignment (current implementation is limited):

- `justify-start`, `justify-center`, `justify-end`, `justify-between`, `justify-around`
- `items-start`, `items-center`, `items-end`
- `content-start`, `content-center`, `content-end`

Notes:

- `justify-between` and `justify-around` are recognized but currently behave like `justify-start`.
- `content-*` is parsed but currently has no practical effect (single-line flex only).

Sizing:

- `w-full`, `w-screen`, `w-px`, `w-{N}`, `w-[Npx]`
- `h-full`, `h-screen`, `h-px`, `h-{N}`, `h-[Npx]`

`{N}` is a float scale multiplied by `dimension_unit` (default `4.0`). Example: `w-16` → 64px (before DPI/layout scaling).

Spacing (no bracket syntax):

- Margin: `m-{N}`, `mx-{N}`, `my-{N}`, `mt-{N}`, `mr-{N}`, `mb-{N}`, `ml-{N}`, and `m-px`
- Padding: `p-{N}`, `px-{N}`, `py-{N}`, `pt-{N}`, `pr-{N}`, `pb-{N}`, `pl-{N}`, and `p-px`
- Gap: `gap-{N}`, `gap-x-{N}`, `gap-y-{N}`, and `gap-px`

Hover variants are supported for margin/padding:

- `hover:m-*`, `hover:mx-*`, `hover:mt-*`, etc
- `hover:p-*`, `hover:px-*`, `hover:pt-*`, etc

Layout scale (custom interpretation of Tailwind’s `scale-*`):

- `scale-{N}` and `scale-[N]`
  - If `{N} >= 10`, it’s treated as a percent: `scale-110` → `1.1`
  - If `{N} < 10`, it’s treated as a direct factor: `scale-1.25` → `1.25`
  - Scale must be `> 0`

This affects layout measurement and sizing/spacing under that node (it is not the same as `transform.scale`).

Absolute positioning:

- `absolute`
- Insets: `top-*`, `right-*`, `bottom-*`, `left-*` (supports `{N}`, `px`, and bracket `[...]` values like `top-[12px]`)

Absolute anchor point (custom extension; affects how `top/left/right/bottom` place the node):

- `anchor-top-left`, `anchor-top`, `anchor-top-right`
- `anchor-left`, `anchor-center`, `anchor-right`
- `anchor-bottom-left`, `anchor-bottom`, `anchor-bottom-right`

### Borders & rounding

- Border width:
  - `border` (all sides, default width)
  - `border-{N}` / `border-px`
  - Side variants: `border-x`, `border-y`, `border-t`, `border-r`, `border-b`, `border-l`
  - Side width variants: `border-x-{N}`, `border-t-{N}`, etc
- Border color:
  - `border-{name}` (theme role or palette token)
  - Hover: `hover:border-{name}`
- Hover variants are supported for border widths as well:
  - `hover:border`, `hover:border-{N}`, `hover:border-x`, `hover:border-x-{N}`, etc
- Corner radius (theme-mapped):
  - `rounded-none`, `rounded-sm`, `rounded`, `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl`, `rounded-3xl`, `rounded-full`

### Visibility & clipping

- `hidden` (skips layout and rendering for the element)
- `overflow-hidden` (clips descendants to the element rect)

Overflow scrolling tokens are parsed but currently not applied:

- `overflow-scroll`, `overflow-x-scroll`, `overflow-y-scroll`

### Opacity

- `opacity-{N}` where `N` is 0..100 (percentage)
- Hover: `hover:opacity-{N}`

### Z-index

- `z-auto` (reset to theme default, currently 0)
- `z-{N}` / `z-[N]`
- `z-{layer}` where layer is one of: `base`, `dropdown`, `overlay`, `modal`, `popover`, `tooltip`
- Negative forms: `-z-{...}`

### Cursor

- `cursor-auto`, `cursor-default`
- `cursor-pointer`
- `cursor-text`
- `cursor-move`
- `cursor-wait`, `cursor-progress`
- `cursor-crosshair`
- `cursor-not-allowed`
- `cursor-none`
- `cursor-grab`, `cursor-grabbing`
- Resize cursors: `cursor-col-resize`, `cursor-row-resize`, `cursor-ne-resize`, `cursor-nw-resize`, `cursor-e-resize`, `cursor-w-resize`, `cursor-n-resize`, `cursor-s-resize`, `cursor-se-resize`, `cursor-sw-resize`

### Transitions

Enable transitions:

- `transition` (layout + transform + colors + opacity)
- `transition-none`
- `transition-layout`
- `transition-transform`
- `transition-colors`
- `transition-opacity`

Configure:

- `duration-{MS}` (milliseconds; clamped 0..10000)
- Easing direction: `ease-in`, `ease-out`, `ease-in-out`
- Easing curve: `ease-linear`, `ease-sine`, `ease-quad`, `ease-cubic`, `ease-quart`, `ease-quint`, `ease-expo`, `ease-circ`, `ease-back`, `ease-elastic`, `ease-bounce`
