# DVUI_DOCS.md API Coverage Checklist

Legend:
- `[L]` verify via `artifacts/*.layout.json`
- `[S]` verify via `artifacts/screenshot-*.png`
- `[E]` verify via deterministic input + event logs
- `[P]` parse/acceptance only (no functional effect today)

## `ui.json` File Shape

- [ ] `[L]` Top-level object supports `elements: { [elementKey]: Element }`
- [ ] `[L]` Unknown top-level fields are ignored
- [ ] `[L]` Element keys generate metadata tokens: `ui-key-<elementKey>` and `ui-path-<full.path>`
- [ ] `[L]` Unknown element object fields are ignored

Element fields:
- [ ] `[L]` `type` supports `div`, `text`, `button`, `image`, `input`
- [ ] `[L]` Unknown `type` falls back to `div`
- [ ] `[L]` `position.x` / `position.y` number parses as pixels
- [ ] `[L]` `position.x` / `position.y` string `"<N>px"` parses as pixels
- [ ] `[L]` `position.x` / `position.y` string `"<N>%"` resolves vs parent axis size
- [ ] `[L]` `size.width` / `size.height` numbers are treated as pixels
- [ ] `[L]` `anchor` supports: `top_left`, `top_center`, `top_right`, `center_left`, `center`, `center_right`, `bottom_left`, `bottom_center`, `bottom_right`
- [ ] `[L][S]` `color: {r,g,b,a}` clamps each channel to `0..255`
- [ ] `[L][S]` `text: string` is accepted
- [ ] `[L][S]` `value: string` is accepted
- [ ] `[L][S]` `src: string` is accepted
- [ ] `[L][S]` `fontSize: number` is accepted
- [ ] `[L][S]` `fontSizing: number` is accepted and takes precedence over `fontSize`
- [ ] `[L][S]` `fontFamily` supports: `ui`, `mono`, `game`, `dyslexic`
- [ ] `[L][S]` `fontWeight` supports: `light`, `medium`, `semibold`, `bold`
- [ ] `[L][S]` `fontItalic: boolean` is accepted
- [ ] `[L][S]` `fontRenderMode` supports: `msdf`, `raster`
- [ ] `[L]` `children: { [elementKey]: Element }` loads recursively

## Tags Produced By The `ui.json` Loader

- [ ] `[L]` `type: "div"` produces retained `tag: "div"`
- [ ] `[L]` `type: "text"` produces retained `tag: "p"` and inserts a child text node from `text`
- [ ] `[L]` `type: "button"` produces retained `tag: "button"`
- [ ] `[L]` `type: "image"` produces retained `tag: "image"` and uses `src`
- [ ] `[L]` `type: "input"` produces retained `tag: "input"` and uses `value` (or `text` fallback)

## Dedicated Renderers (Not Emitted By `ui.json` Today)

- [ ] `[L][S][E]` `slider`
- [ ] `[L][S]` `icon`
- [ ] `[L][S]` `h1`
- [ ] `[L][S]` `h2`
- [ ] `[L][S]` `h3`
- [ ] `[L]` Unknown tags render as generic elements (children only)

## Retained Tag Properties (Renderer)

- [ ] `[L][S]` `div` background/opacity/clip/z-index derive from `visual` (props + Tailwind classes)
- [ ] `[S]` `div` border and rounding draw via Tailwind `border*` and `rounded*`
- [ ] `[L]` `div` renders child elements and text nodes
- [ ] `[E]` `div` can emit `pointerdown` and `pointerup` when listeners are attached

- [ ] `[S]` `p` renders concatenated descendant text nodes with line breaking
- [ ] `[L][S]` `p` responds to `text-left`, `text-center`, `text-right`, `text-nowrap`, `break-words`
- [ ] `[S]` `p` uses Tailwind font and text outline tokens when drawing

- [ ] `[S]` `h1`/`h2`/`h3` behave like `p` but force font style overrides (`title`, `title_1`, `title_2`)

- [ ] `[L][S]` `button` caption is derived from descendant text nodes
- [ ] `[L][S]` `button` caption falls back to `"Button"` when empty
- [ ] `[E]` `button` emits `click` only when a click listener is attached
- [ ] `[E]` `button` can emit `pointerdown` and `pointerup` when listeners are attached

- [ ] `[E]` `input` reads/writes text via node input state
- [ ] `[E]` `input` emits `focus`, `blur`, `input`, `enter` when listeners are attached

- [ ] `[E]` `slider` reads/writes value via node input state as a stringified float fraction in `[0, 1]`
- [ ] `[E]` `slider` emits `input` when the value changes if a listener is attached

- [ ] `[S]` `image` draws from `image_src` and caches loaded resources
- [ ] `[S]` `image` supports `image_tint` and `image_opacity`
- [ ] `[S]` `image` tint/opacity can be animated by transitions

- [ ] `[S]` `icon` resolves from `image_src` and caches resolved icons
- [ ] `[S]` `icon` can render vector, raster, or glyph icons depending on what resolves

- [ ] `[L][S]` Text nodes store UTF-8 text and can be rendered directly or consumed by `p` / `button` caption collection

## `ui.json` Property Support By Element Type

Common:
- [ ] `[L]` `position`, `size`, `anchor` generate positioning/sizing classes
- [ ] `[L]` `children` load recursively
- [ ] `[L]` Font fields generate Tailwind-style font tokens

`div`:
- [ ] `[S]` `color` sets background color
- [ ] `[L]` `text` is ignored
- [ ] `[L]` `value` is ignored
- [ ] `[L]` `src` is stored but not rendered

`text` (`tag: "p"`):
- [ ] `[L][S]` `text` becomes paragraph content (child text node)
- [ ] `[S]` `color` sets text color (not background)

`button`:
- [ ] `[S]` `color` sets background color
- [ ] `[L]` `text` is ignored by the loader
- [ ] `[L][S]` Button caption is still derived from descendant text nodes (no direct label field)

`image`:
- [ ] `[S]` `src` is required to draw (missing `src` skips drawing)
- [ ] `[S]` `color` sets background behind the image

`input`:
- [ ] `[E]` `value` sets initial input text
- [ ] `[E]` If `value` is missing, `text` is used as the initial input text
- [ ] `[S]` `color` sets background color

## Layout Semantics (`ui.json`)

- [ ] `[L]` Layout is resolved during load and baked into generated Tailwind-style positioning classes
- [ ] `[L]` `anchor` affects how `position` is interpreted within the parent (horizontal: left/center/right; vertical: top/center/bottom)
- [ ] `[L]` Percent axis values (`"N%"`) resolve against the parent width/height

## Auto-Generated `className` For `ui.json`

Always present:
- [ ] `[L]` `absolute`
- [ ] `[L]` `left-[<px>] top-[<px>]`
- [ ] `[L]` `w-[<px>] h-[<px>]`
- [ ] `[L]` `ui-key-<elementKey>`
- [ ] `[L]` `ui-path-<full.path>`

Metadata tokens:
- [ ] `[L]` `ui-key-*` and `ui-path-*` are ignored by the Tailwind parser

Optional font tokens:
- [ ] `[L][S]` Font family: `font-ui`, `font-mono`, `font-game`, `font-dyslexic`
- [ ] `[L][S]` Font weight: `font-light`, `font-medium`, `font-semibold`, `font-bold`
- [ ] `[L][S]` Italic: `italic` only when `fontItalic: true` and resolved family is not `font-game`
- [ ] `[L][S]` Render mode: `font-render-msdf`, `font-render-raster`
- [ ] `[L][S]` Text size: `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`
- [ ] `[L]` Font size mapping from numeric `fontSizing`/`fontSize` matches DVUI_DOCS.md thresholds

## Tailwind-Style Class Tokens Supported By DVUI

General:
- [ ] `[L]` Tokens are whitespace-delimited and unknown tokens are ignored
- [ ] `[L]` Numeric scales use `spacing_unit = 4px` and `dimension_unit = 4px`
- [ ] `[L]` Bracket values (example: `w-[123]`) are raw pixels (not scaled)

Positioning, insets, layout anchors:
- [ ] `[L]` `absolute`
- [ ] `[L]` `top-*`, `right-*`, `bottom-*`, `left-*` support `*-px`, `*-N` (scaled, non-negative), `*-[N|Npx]` (raw px, negative allowed), `*-[N%]` (percent, negative allowed)
- [ ] `[L]` `anchor-top-left`, `anchor-top`, `anchor-top-right`, `anchor-left`, `anchor-center`, `anchor-right`, `anchor-bottom-left`, `anchor-bottom`, `anchor-bottom-right`

Sizing:
- [ ] `[L]` Width: `w-full`, `w-screen`, `w-px`, `w-N` (scaled), `w-[N|Npx]` (raw px)
- [ ] `[L]` Height: `h-full`, `h-screen`, `h-px`, `h-N` (scaled), `h-[N|Npx]` (raw px)

Scale:
- [ ] `[L]` `scale-[N]` uses `N` directly and requires `N > 0`
- [ ] `[L]` `scale-N` treats `N >= 10` as percent (example: `scale-50` => `0.5`)

Flexbox layout (layout only):
- [ ] `[L]` `flex`
- [ ] `[L]` `flex-row`, `flex-col`
- [ ] `[L]` `justify-start`, `justify-center`, `justify-end`, `justify-between`, `justify-around`
- [ ] `[L]` `items-start`, `items-center`, `items-end`
- [ ] `[L]` `content-start`, `content-center`, `content-end`
- [ ] `[L]` `gap-N`, `gap-x-N`, `gap-y-N` (scaled) and `gap-px` (1px)

Margin and padding:
- [ ] `[L]` Margin: `m-N`, `mx-N`, `my-N`, `mt-N`, `mr-N`, `mb-N`, `ml-N`
- [ ] `[L]` Padding: `p-N`, `px-N`, `py-N`, `pt-N`, `pr-N`, `pb-N`, `pl-N`
- [ ] `[L]` Spacing values support `*-px` (1px) and `*-N` (scaled, non-negative)
- [ ] `[L][E]` Hover variants: `hover:m-*`, `hover:p-*`

Borders and rounding:
- [ ] `[L][S]` Border widths: `border`, `border-x`, `border-y`, `border-t`, `border-r`, `border-b`, `border-l`
- [ ] `[L][S]` Border widths: `border-px`, `border-N` (raw px), directional `border-x-N`, `border-t-N`, `border-r-N`, `border-b-N`, `border-l-N`
- [ ] `[S]` Border colors: `border-<colorToken>` and directional `border-x-<colorToken>`, `border-t-<colorToken>`, `border-r-<colorToken>`, `border-b-<colorToken>`, `border-l-<colorToken>`
- [ ] `[E][S]` Hover variants: `hover:border-*` (width and/or color)
- [ ] `[S]` Rounded: `rounded-none`, `rounded-sm`, `rounded`, `rounded-md`, `rounded-lg`, `rounded-xl`, `rounded-2xl`, `rounded-3xl`, `rounded-full`

Colors, typography, text layout:
- [ ] `[S]` Background: `bg-<colorToken>` and `hover:bg-<colorToken>`
- [ ] `[S]` Text color: `text-<colorToken>` and `hover:text-<colorToken>`
- [ ] `[L][S]` Text size: `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`
- [ ] `[S]` Text outline thickness: `text-outline-N`, `text-outline-[N]`, `text-outline-[Npx]` with `N >= 0`
- [ ] `[S]` Text outline color: `text-outline-<colorToken>`
- [ ] `[E][S]` Hover variants: `hover:text-outline-*`
- [ ] `[L][S]` Text alignment/wrapping: `text-left`, `text-center`, `text-right`, `text-nowrap`, `break-words`
- [ ] `[S]` Opacity: `opacity-N` (`0..100`) and `hover:opacity-N`

Font family, weight, slant, render mode:
- [ ] `[S]` Family: `font-ui`, `font-mono`, `font-game`, `font-dyslexic`
- [ ] `[S]` Weight: `font-light`, `font-normal`, `font-medium`, `font-semibold`, `font-bold`
- [ ] `[S]` Slant: `italic`, `not-italic`
- [ ] `[S]` Render: `font-render-auto`, `font-render-msdf`, `font-render-raster`

Z-index:
- [ ] `[S]` `z-auto`
- [ ] `[S]` Theme layer aliases: `z-base`, `z-dropdown`, `z-overlay`, `z-modal`, `z-popover`, `z-tooltip`
- [ ] `[S]` Numeric: `z-N`, `z-[N]`
- [ ] `[S]` Negative: `-z-N`, `-z-[N]`

Visibility and overflow:
- [ ] `[L][S]` `hidden`
- [ ] `[S]` `overflow-hidden` clips children
- [ ] `[P]` `overflow-scroll`, `overflow-x-scroll`, `overflow-y-scroll` are parsed but not wired to scrolling behavior

Cursor:
- [ ] `[S]` `cursor-auto`, `cursor-default`, `cursor-pointer`, `cursor-text`, `cursor-move`, `cursor-wait`, `cursor-progress`, `cursor-crosshair`, `cursor-not-allowed`, `cursor-none`, `cursor-grab`, `cursor-grabbing`
- [ ] `[S]` `cursor-col-resize`, `cursor-e-resize`, `cursor-w-resize`
- [ ] `[S]` `cursor-row-resize`, `cursor-n-resize`, `cursor-s-resize`
- [ ] `[S]` `cursor-ne-resize`, `cursor-sw-resize`
- [ ] `[S]` `cursor-nw-resize`, `cursor-se-resize`

Transitions:
- [ ] `[E][S]` Enable: `transition`, `transition-none`, `transition-layout`, `transition-transform`, `transition-colors`, `transition-opacity`
- [ ] `[E][S]` Timing: `duration-N` clamped to `0..10000`
- [ ] `[E][S]` Easing direction: `ease-in`, `ease-out`, `ease-in-out`
- [ ] `[E][S]` Easing style: `ease-linear`, `ease-sine`, `ease-quad`, `ease-cubic`, `ease-quart`, `ease-quint`, `ease-expo`, `ease-circ`, `ease-back`, `ease-elastic`, `ease-bounce`

## Color Token Set (`<colorToken>`)

- [ ] `[S]` Theme role tokens: `content`, `window`, `control`, `highlight`, `err`, `app1`, `app2`, `app3`
- [ ] `[S]` Palette tokens: `transparent`, `white`, `black`
- [ ] `[S]` Palette token pattern: `{amber|blue|cyan|emerald|fuchsia|gray|green|indigo|lime|neutral|orange|pink|purple|red|rose|sky|slate|stone|teal|violet|yellow|zinc}-{50|100|200|300|400|500|600|700|800|900}`

## Event Kinds (Retained Event Ring)

- [ ] `[E]` `click`
- [ ] `[E]` `input`
- [ ] `[E]` `focus`
- [ ] `[E]` `blur`
- [ ] `[E]` `mouseenter`
- [ ] `[E]` `mouseleave`
- [ ] `[E]` `keydown`
- [ ] `[E]` `keyup`
- [ ] `[E]` `change`
- [ ] `[E]` `submit`
- [ ] `[E]` `pointerdown`
- [ ] `[E]` `pointermove`
- [ ] `[E]` `pointerup`
- [ ] `[E]` `pointercancel`
- [ ] `[E]` `dragstart`
- [ ] `[E]` `drag`
- [ ] `[E]` `dragend`
- [ ] `[E]` `dragenter`
- [ ] `[E]` `dragleave`
- [ ] `[E]` `drop`
- [ ] `[E]` `scroll`
- [ ] `[E]` `enter`
