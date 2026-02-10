# DVUI Retained UI Library Reference (ClayEngine)

Runtime truth for ClayEngine `ui.json` support (what the loader reads) and DVUI retained UI support (what the renderer and Tailwind-style class parser handle).

## `ui.json` File Shape

Top-level object:
- `elements`: object map of `elementKey -> Element`

Element keys:
- Keys are used to generate metadata class tokens: `ui-key-<elementKey>` and `ui-path-<full.path>`.

Element object fields (unknown fields are ignored by the loader):
- `type`: string (`div`, `text`, `button`, `image`, `input`); unknown values fall back to `div`
- `position`: object with optional `x` and `y` axis values
- `size`: object with `width` and `height` numbers (pixels)
- `anchor`: string (`top_left`, `top_center`, `top_right`, `center_left`, `center`, `center_right`, `bottom_left`, `bottom_center`, `bottom_right`)
- `color`: `{ r, g, b, a }` numbers (0-255; clamped)
- `text`: string
- `value`: string
- `src`: string
- `fontSize`: number
- `fontSizing`: number (takes precedence over `fontSize`)
- `fontFamily`: string (`ui`, `mono`, `game`, `dyslexic`)
- `fontWeight`: string (`light`, `medium`, `semibold`, `bold`)
- `fontItalic`: boolean
- `fontRenderMode`: string (`msdf`, `raster`)
- `children`: object map of `elementKey -> Element`

Axis value formats (`position.x` / `position.y`):
- number: treated as pixels
- string ending with `px`: pixels (example: `"12px"`)
- string ending with `%`: percent of parent axis size (example: `"50%"`)

## Tag Coverage

### Tags Produced By The `ui.json` Loader

`ui.json` `type` is translated into a retained node `tag`:

| `ui.json` `type` | Retained `tag` | Notes |
|---|---|---|
| `div` | `div` | container |
| `text` | `p` | loader also inserts a child text node containing `text` |
| `button` | `button` | interactive |
| `image` | `image` | uses `src` |
| `input` | `input` | uses `value` (or `text` as fallback) |

### Tags With Dedicated Renderers (Not Emitted By `ui.json` Today)

The retained renderer has dedicated render paths for these tags:
- `slider`
- `icon`
- `h1`, `h2`, `h3`

Any other tag renders as a generic element (children only, no specialized behavior).

## Retained Tag Properties (Renderer)

This section is about the retained renderer behavior for each tag (independent of `ui.json`). It describes which node properties are consumed by the renderer.

`div`:
- Uses `visual` (derived from `visual_props` plus Tailwind classes) for background/opacity/clip/z-index.
- Uses Tailwind border and rounding tokens when drawing the cached/direct background.
- Renders child elements and text nodes.
- Can emit `pointerdown` and `pointerup` events when listeners are attached.

`p`:
- Draws paragraph text by concatenating descendant text nodes (`NodeKind.text`), then doing line breaking.
- Uses `text-left`, `text-center`, `text-right`, `text-nowrap`, `break-words`.
- Uses Tailwind font and text outline tokens when drawing.

`h1`, `h2`, `h3`:
- Same as `p`, but forces a font style override (`h1` => `title`, `h2` => `title_1`, `h3` => `title_2`).

`button`:
- Caption is derived from descendant text nodes; if empty, caption falls back to `"Button"`.
- Emits `click` when clicked if a `click` listener is attached.
- Can emit `pointerdown` and `pointerup` when listeners are attached.

`input`:
- Reads and writes text through the node's input state (set via `NodeStore.setInputValue`).
- Emits `focus`, `blur`, `input`, and `enter` when listeners are attached.

`slider`:
- Reads and writes its current value through the node's input state as a stringified float fraction in `[0, 1]` (set via `NodeStore.setInputValue`).
- Emits `input` when the slider value changes if a listener is attached.

`image`:
- Uses `image_src` (set via `NodeStore.setImageSource`) and caches loaded resources.
- Supports `image_tint` and `image_opacity` (set via `NodeStore.setImageTint` / `NodeStore.setImageOpacity`), and transitions can animate them.

`icon`:
- Uses `image_src` as an icon name/path and `icon_kind` plus `icon_glyph` (set via `NodeStore.setIconKind` / `NodeStore.setIconGlyph`).
- Caches resolved icons and can render vector, raster, or glyph icons depending on what resolves.

Text nodes (`NodeKind.text`):
- Store UTF-8 text content (set via `NodeStore.setTextNode`) and can be rendered directly or consumed by paragraph/button caption collection.

## `ui.json` Property Support By Element Type

Common behavior:
- `position`, `size`, `anchor`: used to generate the element's positioning and sizing classes.
- `children`: loaded recursively.
- Font fields: converted into Tailwind-style font tokens on the element's generated `className`.

`div`:
- `color`: sets background color.
- `text`: ignored.
- `value`: ignored (retained store only applies input values to `input`/`slider` tags).
- `src`: stored but not rendered.

`text` (renders as `p`):
- `text`: becomes the paragraph's content (stored as a child text node).
- `color`: sets text color (not background).

`button`:
- `color`: sets background color.
- `text`: ignored by the loader.
- Caption source: button caption is derived from descendant text nodes (there is no `ui.json` field that directly sets a button label).

`image`:
- `src`: required to display an image (missing `src` causes the renderer to skip drawing).
- `color`: sets background behind the image.

`input`:
- `value`: sets the initial input text.
- Fallback: if `value` is missing, `text` is used as the initial input text.
- `color`: sets background color.

## Layout Semantics (`ui.json`)

Layout is resolved during load and baked into generated Tailwind-style positioning classes.

`anchor` affects how `position` is interpreted within the parent:
- Horizontal: `left`, `center`, `right`
- Vertical: `top`, `center`, `bottom`

Percent axis values (`"N%"`) are resolved against the parent element's width or height.

## Auto-Generated `className` For `ui.json`

`ui.json` does not accept author-supplied `className`. The loader generates `className` for every element.

Always present:
- `absolute`
- `left-[<px>] top-[<px>]`
- `w-[<px>] h-[<px>]`
- `ui-key-<elementKey>`
- `ui-path-<full.path>` (dot-joined ancestor keys, e.g. `Hud.Title`)

Metadata tokens (`ui-key-*`, `ui-path-*`) are ignored by the Tailwind parser and exist for identification/debugging.

Optional font tokens (added when the corresponding `font*` fields exist):
- Font family: `font-ui`, `font-mono`, `font-game`, `font-dyslexic`
- Font weight: `font-light`, `font-medium`, `font-semibold`, `font-bold`
- Italic: `italic` (only when `fontItalic: true` and the resolved family is not `font-game`)
- Render mode: `font-render-msdf`, `font-render-raster`
- Text size: `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`

Font size mapping from numeric `fontSizing`/`fontSize`:
- `<= 12` => `text-xs`
- `<= 14` => `text-sm`
- `<= 16` => `text-base`
- `<= 20` => `text-lg`
- `<= 24` => `text-xl`
- `<= 28` => `text-2xl`
- `> 28` => `text-3xl`

## Tailwind-Style Class Tokens Supported By DVUI

Class tokens are whitespace-delimited. Unknown tokens are ignored.

Design token scales:
- `spacing_unit = 4px` (used by spacing and inset numeric scales)
- `dimension_unit = 4px` (used by `w-*` and `h-*` numeric scales)
- Bracket values (like `w-[123]`) are raw pixels, not scaled.

### Positioning, Insets, And Layout Anchors

Tokens:
- `absolute`
- `top-*`, `right-*`, `bottom-*`, `left-*`
- `anchor-top-left`, `anchor-top`, `anchor-top-right`, `anchor-left`, `anchor-center`, `anchor-right`, `anchor-bottom-left`, `anchor-bottom`, `anchor-bottom-right`

Inset value formats:
- `*-px` (1px)
- `*-N` where `N` is a number scaled by `spacing_unit` (no negative numeric scales)
- `*-[N]` or `*-[Npx]` for raw pixels (supports negative values)
- `*-[N%]` for percent of the parent axis (supports negative values)

### Sizing

Width tokens:
- `w-full`, `w-screen`
- `w-px` (1px)
- `w-N` where `N` is scaled by `dimension_unit`
- `w-[N]` or `w-[Npx]` for raw pixels

Height tokens:
- `h-full`, `h-screen`
- `h-px` (1px)
- `h-N` where `N` is scaled by `dimension_unit`
- `h-[N]` or `h-[Npx]` for raw pixels

### Scale

Tokens:
- `scale-N`
- `scale-[N]`

Parsing rules:
- `scale-[N]` uses `N` directly (must be `> 0`).
- `scale-N` treats `N >= 10` as a percent (example: `scale-50` => `0.5`).

### Flexbox Layout (Layout Only)

Tokens:
- `flex`
- `flex-row`, `flex-col`
- `justify-start`, `justify-center`, `justify-end`, `justify-between`, `justify-around`
- `items-start`, `items-center`, `items-end`
- `content-start`, `content-center`, `content-end`
- `gap-N`, `gap-x-N`, `gap-y-N` (scaled by `spacing_unit`, or `gap-px` for 1px)

### Margin And Padding

Margin tokens:
- `m-N`, `mx-N`, `my-N`, `mt-N`, `mr-N`, `mb-N`, `ml-N`

Padding tokens:
- `p-N`, `px-N`, `py-N`, `pt-N`, `pr-N`, `pb-N`, `pl-N`

Spacing value formats:
- `*-px` (1px)
- `*-N` where `N` is a number scaled by `spacing_unit` (no negative spacing values)

Hover variants:
- `hover:m-*`, `hover:p-*`

### Borders And Rounding

Border width tokens:
- `border` (default width is `1px`)
- `border-x`, `border-y`, `border-t`, `border-r`, `border-b`, `border-l` (default width)
- `border-px` (1px)
- `border-N` (raw px, not scaled)
- Directional widths: `border-x-N`, `border-t-N`, `border-r-N`, `border-b-N`, `border-l-N`

Border color tokens:
- `border-<colorToken>`
- Directional colors: `border-x-<colorToken>`, `border-t-<colorToken>`, `border-r-<colorToken>`, `border-b-<colorToken>`, `border-l-<colorToken>`

Hover variants:
- `hover:border-*` (width and/or color)

Rounded corner tokens:
- `rounded-none`, `rounded-sm`, `rounded`, `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl`, `rounded-3xl`, `rounded-full`

### Colors, Typography, And Text Layout

Background color tokens:
- `bg-<colorToken>`
- `hover:bg-<colorToken>`

Text color tokens:
- `text-<colorToken>`
- `hover:text-<colorToken>`

Typography size tokens:
- `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`

Text outline tokens:
- `text-outline-N` or `text-outline-[N]` or `text-outline-[Npx]` for thickness (must be `>= 0`)
- `text-outline-<colorToken>` for outline color
- Hover versions via `hover:text-outline-*`

Text alignment and wrapping:
- `text-left`, `text-center`, `text-right`
- `text-nowrap` (disable wrapping)
- `break-words` (allow breaking long words)

Opacity:
- `opacity-N` where `N` is an integer `0..100`
- `hover:opacity-N`

### Font Family, Weight, Slant, Render Mode

Font family:
- `font-ui`, `font-mono`, `font-game`, `font-dyslexic`

Font weight:
- `font-light`, `font-normal`, `font-medium`, `font-semibold`, `font-bold`

Font slant:
- `italic`, `not-italic`

Font render mode:
- `font-render-auto`, `font-render-msdf`, `font-render-raster`

### Z-Index

Tokens:
- `z-auto` (resets to default)
- Theme layer aliases: `z-base`, `z-dropdown`, `z-overlay`, `z-modal`, `z-popover`, `z-tooltip`
- Numeric: `z-N` or `z-[N]`
- Negative: `-z-N` or `-z-[N]`

### Visibility And Overflow

Tokens:
- `hidden`
- `overflow-hidden` (clips children)

Parsed but not currently wired to scrolling behavior:
- `overflow-scroll`
- `overflow-x-scroll`
- `overflow-y-scroll`

### Cursor

Tokens:
- `cursor-auto`, `cursor-default`, `cursor-pointer`, `cursor-text`, `cursor-move`, `cursor-wait`, `cursor-progress`, `cursor-crosshair`, `cursor-not-allowed`, `cursor-none`, `cursor-grab`, `cursor-grabbing`
- `cursor-col-resize`, `cursor-e-resize`, `cursor-w-resize`
- `cursor-row-resize`, `cursor-n-resize`, `cursor-s-resize`
- `cursor-ne-resize`, `cursor-sw-resize`
- `cursor-nw-resize`, `cursor-se-resize`

### Transitions

Enable transitions:
- `transition` (enables layout, transform, colors, opacity)
- `transition-none`
- `transition-layout`
- `transition-transform`
- `transition-colors`
- `transition-opacity`

Timing:
- `duration-N` where `N` is an integer milliseconds value clamped to `0..10000`

Easing:
- Direction: `ease-in`, `ease-out`, `ease-in-out`
- Style: `ease-linear`, `ease-sine`, `ease-quad`, `ease-cubic`, `ease-quart`, `ease-quint`, `ease-expo`, `ease-circ`, `ease-back`, `ease-elastic`, `ease-bounce`

## Color Token Set (`<colorToken>`)

`<colorToken>` resolves either to a theme role or a palette color name.

Theme role tokens:
- `content`, `window`, `control`, `highlight`, `err`, `app1`, `app2`, `app3`

Palette tokens are defined in `src/retained/style/colors.zig`:
- `transparent`, `white`, `black`
- `{amber|blue|cyan|emerald|fuchsia|gray|green|indigo|lime|neutral|orange|pink|purple|red|rose|sky|slate|stone|teal|violet|yellow|zinc}-{50|100|200|300|400|500|600|700|800|900}`

## Appendix

File References:
- `src/retained/loaders/ui_json.zig`
- `src/retained/render/internal/renderers.zig`
- `src/retained/style/tailwind/parse.zig`
- `src/retained/style/tailwind/parse_layout.zig`
- `src/retained/style/tailwind/parse_color_typography.zig`

Event kinds that can be dispatched through the retained event ring:
- `click`
- `input`
- `focus`, `blur`
- `mouseenter`, `mouseleave`
- `keydown`, `keyup`
- `change`, `submit`
- `pointerdown`, `pointermove`, `pointerup`, `pointercancel`
- `dragstart`, `drag`, `dragend`, `dragenter`, `dragleave`, `drop`
- `scroll`
- `enter`
