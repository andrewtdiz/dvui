# Task: DVUI retained — Tailwind/HTML UI feature pass

## Context
An external driver sends retained UI snapshots/ops into DVUI retained (`src/retained/*`), DVUI stores them in a `NodeStore`, computes layout, renders, and pushes interaction events back through an `EventRing`.
Keep the snapshot/ops, event ring, and picking/rect-query API stable.

## Target tags (snapshot `tag`)
### `div` (UIFrame)
- Layout via `className`: `absolute left-[x] top-[y] w-[w] h-[h]`
  - Must also support **scale-based** position/size (0..1 relative to parent) to match `UI_FEATURES.md`.
- Props: `anchorX/anchorY`, `scaleX/scaleY`, `rotation`, `translateX/translateY`
- Visual: `background` (u32), `opacity` (or `className: opacity-*`), `z-index` (`className: z-*`)
- Clipping: `clipChildren` and/or `className: overflow-hidden` clips descendants

### `image` (ImageFrame)
- All `div` properties
- `src` image source path
- Content fit mode (stretch/contain/cover) + **independent image transform** rotation/scale (separate from node transform)
- Tint/color + opacity (separate from background)
- If missing/unresolved: render a placeholder (no spammy logs)

### `text` (TextFrame)
- All `div` properties
- `text` string
- Text scaling: auto-scale-to-fit (shrink text to fit rect; opt-in flag or `className` token)
- Font family + weight via `className: font-*` (and keep `font-render-*` behavior)
- Color via `textColor` + `className: text-*`
- Stroke/outline (width + color)
- Alignment X/Y (tokens or explicit props)
- Wrapping: default wrap, `className: text-nowrap` disables

## `className` features to support (Tailwind-style)
### Flex layout (`className: flex`) (UIListLayout)
- Direction: `flex-row` / `flex-col`
- Alignment: `justify-*`, `items-*`, `content-*`
- Padding: `p-*` + side variants
- Child sort order: `order-*` / `order-[n]` affects flex item ordering (stable)

### Sizing (aspect ratio) (UIAspectRatioConstraint)
- Token: `aspect-[ratio]` (e.g. `aspect-[1.777]`)
- Dominant axis token: `aspect-dominant-w` / `aspect-dominant-h`
- Auto adjust: enforce aspect by deriving the non-dominant size during layout

### Scrolling (UIScrollingFrame)
- Enable scroll region (token or prop) with axis control:
  - Tokens: `overflow-scroll`, `overflow-x-scroll`, `overflow-y-scroll`
  - Or explicit fields/props if preferred (but must support horizontal/vertical independently).
- Canvas sizing: `canvasWidth/canvasHeight` or `autoCanvas` (AutomaticCanvasSize)
- Input: wheel/touch scrolling, visible scrollbars for enabled axes

### Padding (`p-`) (UIPadding)
- Support `p-*`, `px-*`, `py-*`, `pt-*`, `pr-*`, `pb-*`, `pl-*` (percent-or-offset if your spacing system supports it)

### Corner radius (`rounded-`) (UICorner)
- Support `rounded-*` tokens -> corner radius

### Gradient (UIGradient)
- Background gradient on `div` (and compatible with opacity + corner radius)
- Fields (or tokens) must support: color sequence, transparency sequence, rotation

## Tweening system (UI_FEATURES.md parity)
- Tween position, size, rotation, color, transparency
- Easing styles (linear, quad, cubic, etc.)
- Tween cancellation/override
- Callback events on complete

## Heartbeat / RenderStepped (UI_FEATURES.md parity)
- A per-frame update event (with `dt`) usable by the driver to advance animations or move objects.

## Input handling (UI_FEATURES.md parity)
- Input events (pointer/keyboard/focus) surfaced via the retained `EventRing`
- Hover enter/exit (`mouseenter` / `mouseleave`)

## Integration requirements
- Snapshot apply must preserve runtime state where relevant (scroll offsets, input state).
- Keep `pickNodeAt` + `getNodeRect` accurate with transforms/clipping/z-index.
- Add a small config API (Zig) to set image search roots + default fonts for integrations, avoiding hardcoded `examples/...` paths.
  - Retained `className` font token resolution is currently fixed; extend `src/retained/style/tailwind.zig` so integrations can provide custom font families/ids.

## Acceptance
A minimal scene renders and interacts with: positioned `div`, wrapped + aligned `text`, tinted `image` with placeholder fallback, a `flex` container with `order-*`, and a scroll region; hover/scroll/input events arrive via the event ring; picking/rect queries match what’s on screen.
