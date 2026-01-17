# UI_FEATURES.md -> Implementation Ownership (DVUI vs Luau API)

This document maps the feature list in `UI_FEATURES.md` onto the DVUI architecture described in `ARCHITECTURE.md`. It answers two questions for each requested API:

1. What needs to change in DVUI (the engine) to support the behavior?
2. What should live in the Luau binding layer in this repo (the `ui.*` APIs) to expose the feature?

The intended outcome is: the Luau API stays thin and policy-focused, while the Zig side owns deterministic layout/render/input semantics.

---

## Layers (what DVUI vs Luau API means here)

### DVUI engine (Zig)

For the Luau runtime in this repo, rendering is driven by the retained-style engine under:

- `src/integrations/solid/` (NodeStore, Tailwind-style class parsing, layout, render, events)

And it reuses DVUI core primitives:

- `src/render/`, `src/text/`, `src/widgets/`, `src/window/`

The Zig side should own:

- Layout math (including percent/scale-based sizing/positioning)
- Rendering semantics (backgrounds, clipping, transforms, gradients, text drawing)
- Hit-testing / picking consistency with what is drawn
- Input interpretation (hover/click/scroll/drag/focus) and event emission back to Luau

### Luau binding + script (this repo)

The Luau layer is:

- Zig binding that exposes the `ui.*` API: `src/integrations/luau_ui/mod.zig`
- Frame loop + event dispatch into Luau callbacks: `src/integrations/native_renderer/window.zig`
- Example script implementing `init()`, `update(dt, input)`, `on_event(kind, id, detail)`: `scripts/native_ui.luau`

The Luau layer should own:

- API surface and object model (Frame/ImageFrame/TextFrame/etc)
- Property storage, change detection, and translation into retained fields/tokens
- Tween scheduling, cancellation, callbacks
- Per-frame Heartbeat/RenderStepped dispatch (`update(dt, input)`)

Rule of thumb:

- If a feature changes layout/render/picking/input semantics, implement it in `src/integrations/solid/*`.
- If a feature is about authoring ergonomics, lifecycle, or scheduling, implement it in Luau (or `src/integrations/luau_ui/mod.zig`).

---

## Current Luau API surface (what exists today)

The built-in Luau bindings currently provide these functions (see `src/integrations/luau_ui/mod.zig`):

- `ui.reset()`
- `ui.create(tag, id, parent?, before?)`
- `ui.remove(id)`
- `ui.insert(id, parent, before?)`
- `ui.set_text(id, text)`
- `ui.set_class(id, className)`
- `ui.set_visual(id, { opacity?, cornerRadius?, background?, textColor?, clipChildren? })`
- `ui.set_transform(id, { rotation?, scaleX?, scaleY?, anchorX?, anchorY?, translateX?, translateY? })`
- `ui.set_scroll(id, { enabled?, scrollX?, scrollY?, canvasWidth?, canvasHeight?, autoCanvas? })`
- `ui.set_anchor(id, { anchorId?, side?, align?, offset? })`
- `ui.listen(id, eventName)`

This doc assumes new UI_FEATURES parity work extends this API rather than introducing a separate driver.

---

## Recommended representation strategy (Luau -> Zig)

The Luau API should translate properties into two buckets:

- **Layout/render critical numeric fields**: set directly on nodes via `ui.set_*` functions.
- **Styling tokens**: use `ui.set_class(id, "...")` with Tailwind-like tokens where they already exist.

For Roblox-style scale + offset values (UDim/UDim2), prefer **explicit numeric fields** over encoding them into `className` strings. This keeps parsing simple and makes layout deterministic inside Zig.

Suggested new node fields + Luau setters (optional, backwards compatible):

- Position (UDim2): `posScaleX`, `posScaleY`, `posOffsetX`, `posOffsetY`
- Size (UDim2): `sizeScaleX`, `sizeScaleY`, `sizeOffsetX`, `sizeOffsetY`
- Padding (UDim per side): `padLeftScale`, `padLeftOffset`, ... (`Right/Top/Bottom`)
- ZIndex (if not using `className`): `zIndex`

Recommended Luau binding additions:

- `ui.set_layout(id, { posScaleX?, posScaleY?, posOffsetX?, posOffsetY?, sizeScaleX?, sizeScaleY?, sizeOffsetX?, sizeOffsetY? })`
- or `ui.set_udim2(id, { position = {sx, ox, sy, oy}, size = {sx, ox, sy, oy} })`

All offsets are in **DVUI natural units** (logical pixels). The Zig renderer multiplies by `windowNaturalScale()` internally to reach physical pixels.

---

## Feature-by-feature ownership map

### UIFrame

Requested:
- Position (scale)
- Size (scale)
- Anchor/Pivot point
- Background color
- Transparency
- Rotation
- Z-index
- Clipping

Mapping to the Luau retained node model:

| UIFrame API | Node mapping | Owner |
|---|---|---|
| Position (scale+offset) | new fields `posScaleX/Y`, `posOffsetX/Y` (preferred) | Zig layout + Luau API |
| Size (scale+offset) | new fields `sizeScaleX/Y`, `sizeOffsetX/Y` (preferred) | Zig layout + Luau API |
| Anchor/Pivot | existing `anchorX/anchorY` (also used for transform pivot) | Zig layout/render + Luau API |
| Background color | existing `background` or `className bg-*` | Zig render + Luau API |
| Transparency | existing `opacity` or `className opacity-*` | Zig render + Luau API |
| Rotation | existing `rotation` | Zig render + Luau API |
| Z-index | `className z-*` (today) or new `zIndex` field | Zig render order + Luau API |
| Clipping | existing `clipChildren` or `className overflow-hidden` | Zig render/picking + Luau API |

Zig work (engine):
- Data: add the UDim2 layout fields on `types.SolidNode` in `src/integrations/solid/core/types.zig`.
- Layout: compute `rect` using parent rect + UDim2 + anchor in `src/integrations/solid/layout/mod.zig:computeNodeLayout()`.
- Rendering: make sure clipping and transforms match layout in `src/integrations/solid/render/direct.zig` and `src/integrations/solid/render/cache.zig`.

Luau binding work:
- Expose setters in `src/integrations/luau_ui/mod.zig` (recommended `ui.set_layout`).
- Keep `ui.set_class` for stylistic tokens (padding, flex, theme colors).

---

### ImageFrame

Requested:
- All UIFrame properties
- Image source
- Image scaling + rotation
- Image tint
- Image transparency

Mapping to the Luau retained node model:

| ImageFrame API | Node mapping | Owner |
|---|---|---|
| Image source | node `image_src` (via `NodeStore.setImageSource`) | Zig render + Luau API |
| Fit mode (stretch/contain/cover) | new field `imageFit` (enum) | Zig render + Luau API |
| Image-only rotation/scale | new fields `imageRotation`, `imageScaleX/Y` (separate from node transform) | Zig render + Luau API |
| Tint | new field `imageTint` (u32 RGBA) | Zig render + Luau API |
| Image opacity | new field `imageOpacity` (f32) or reuse `imageTint` alpha | Zig render + Luau API |

Zig work (engine):
- Data: extend `types.SolidNode` with image-specific render props in `src/integrations/solid/core/types.zig`.
- Rendering: implement fit + UV cropping + tint in `src/integrations/solid/render/mod.zig:renderImage()` using `dvui.renderTexture` options (`uv`, `rotation`, `colormod`).
- Placeholder: when missing/unresolved image, render a stable placeholder and avoid repeated logs (store a per-node "failed" cache state).

Luau binding work:
- Add `ui.set_src(id, src)` (or `ui.set_image_src`) in `src/integrations/luau_ui/mod.zig` to call `store.setImageSource`.
- Map ImageFrame properties to the node fields; do not implement UV math in Luau.

---

### TextFrame

Requested:
- All UIFrame properties
- Text string
- Text scaling (auto-scale)
- Font + weight
- Text color
- Text stroke (outline)
- Text alignment (X/Y)
- Line wrapping

Mapping to the Luau retained node model:

| TextFrame API | Node mapping | Owner |
|---|---|---|
| Text string | existing `ui.set_text(id, text)` | Zig render/layout + Luau API |
| Auto-scale-to-fit | new boolean `textAutoScale` | Zig measure+render + Luau API |
| Font family/weight | `ui.set_class` tokens (e.g. `font-*`) | Luau chooses; Zig applies |
| Text color | `ui.set_visual(textColor=...)` or `ui.set_class("text-*")` | Zig + Luau |
| Stroke/outline | new fields `textStrokeColor` + `textStrokeWidth` | Zig render + Luau API |
| Align X/Y | new fields `textAlignX`, `textAlignY` (or token X + numeric Y) | Zig render + Luau API |
| Wrapping | token `text-nowrap` (and default wrap) | Zig + Luau |

Zig work (engine):
- Text layout/wrap: implement multi-line wrapping inside a rect in:
  - `src/integrations/solid/layout/measure.zig`
  - `src/integrations/solid/layout/text_wrap.zig` (if/when added)
  - `src/integrations/solid/render/mod.zig` (render path that draws multi-line text inside a rect)
- Auto-scale-to-fit: when enabled, measure text, compute a scale factor, and render with a resized font.
- Stroke: render text outline via a small multi-pass draw (8 offsets) before the main fill, using `dvui.renderText`.
- Alignment Y: implement vertical alignment (top/center/bottom) by offsetting the text rect before drawing.

Luau binding work:
- Expose API-level flags/enums and map to node fields.
- Font name policy belongs in Luau; Zig should only expose configurable default font ids.

---

### UIListLayout

Requested:
- Sort order
- Padding
- Fill direction (vertical/horizontal)
- Alignment

Mapping to the Luau retained node model:

| UIListLayout API | Node mapping | Owner |
|---|---|---|
| Fill direction | `className flex flex-col` / `flex-row` | Luau sets; Zig lays out |
| Padding | `className p-*` (and side variants) or UDim padding fields | Zig computes; Luau sets |
| Spacing between items | `className gap-*` | Luau sets; Zig lays out |
| Sort order | `order-*` / `order-[n]` on children (preferred) | Zig layout + Luau API |
| Alignment | `justify-*`, `items-*`, `content-*` | Luau sets; Zig lays out |

Zig work (engine):
- Tailwind parsing: add `order-*` / `order-[n]` to `src/integrations/solid/style/tailwind.zig`.
- Flex layout: apply order in `src/integrations/solid/layout/flex.zig` before measuring/placing.

Luau binding work:
- Implement `UIListLayout` as a pure Luau-side policy that updates:
  - parent `className` (flex direction/alignment/gap/padding)
  - per-child order tokens (from `LayoutOrder` / `SortOrder` semantics)

---

### UIAspectRatioConstraint

Requested:
- Aspect ratio value
- Dominant axis
- Auto adjustment

Zig work (engine):
- Prefer explicit fields (avoid parsing complexity): add `aspectRatio`, `aspectDominant` on `types.SolidNode` in `src/integrations/solid/core/types.zig`.
- Enforce in `src/integrations/solid/layout/mod.zig` before laying out children:
  - if dominant axis is width, derive height
  - if dominant axis is height, derive width

Luau binding work:
- Add `ui.set_aspect(id, { ratio, dominant })` (or similar) that writes the node fields.

---

### UIScrollingFrame

Requested:
- Scrollbar support (vertical/horizontal)
- Canvas size or AutomaticCanvasSize
- Scroll input handling (wheel/touch)

Mapping to the Luau retained node model:

| UIScrollingFrame API | Node mapping | Owner |
|---|---|---|
| Enable scrolling | existing `ui.set_scroll({ enabled = true })` (or a scroll tag) | Zig + Luau API |
| Canvas size | existing `canvasWidth/canvasHeight` | Zig + Luau API |
| AutomaticCanvasSize | existing `autoCanvas` | Zig + Luau API |
| Axis enable (x/y) | new fields `scrollXEnabled`, `scrollYEnabled` | Zig + Luau API |
| Scrollbars | implemented in solid render | Zig |
| Wheel/touch | implemented in solid render | Zig |

Zig work (engine):
- Add axis enable flags to `ScrollState` in `src/integrations/solid/core/types.zig`.
- Render/input: respect axis flags when handling wheel/touch in `src/integrations/solid/render/mod.zig`.
- Scrollbars: implement scrollbars (today solid layout/input tracks offsets but does not draw bars) in `src/integrations/solid/render/mod.zig` using `dvui.ScrollBarWidget`.

Luau binding work:
- Extend `ui.set_scroll` to accept axis enable flags.

---

### UIPadding

Requested:
- Percent or offset padding on each side

Zig work (engine):
- If percent padding is required, add UDim-per-side padding fields on nodes and apply them in `src/integrations/solid/layout/mod.zig` when computing the child content rect.
- If offset-only is sufficient, no engine work is required (use existing `p-*` / `px-*` / `pt-*` tokens).

Luau binding work:
- Implement `UIPadding` as an attached API component that sets either:
  - retained UDim padding fields (preferred for scale+offset parity), or
  - `className` padding tokens (offset-only).

---

### UICorner

Requested:
- Corner radius

Zig work (engine):
- Already supported via `ui.set_visual({ cornerRadius = ... })` (stored on `types.SolidNode.visual.corner_radius`).

Luau binding work:
- No new Zig API needed; expose a nicer Luau wrapper type if desired.

---

### UIGradient

Requested:
- Color sequence
- Transparency sequence
- Rotation

Zig work (engine):
- Data: `Gradient` exists in `src/integrations/solid/core/types.zig` but is currently unused.
- Add node fields for gradient data (colors/stops/angle).
- Render: implement gradient background drawing in `src/integrations/solid/render/cache.zig` (preferred) or `src/integrations/solid/render/direct.zig`.
- Ensure gradient respects:
  - `opacity`
  - `cornerRadius`
  - clipping (`clipChildren` / scroll)

Luau binding work:
- Provide API types for sequences and map them to node gradient fields.
- Keep any sequence interpolation policy in Luau; Zig should only render the resolved stops.

---

### Tweening system

Requested:
- Tween position, size, rotation, color, transparency
- Easing styles
- Tween cancellation/override
- Callback events on complete

Luau work (recommended):
- Implement tweens entirely in Luau:
  - maintain a list of active tweens
  - advance by dt each frame (Heartbeat/RenderStepped)
  - call `ui.set_*` each frame to update the target fields (`pos*`, `size*`, `rotation`, `background`, `opacity`, etc)
  - Use DVUI easing helpers if desired: `src/layout/easing.zig` (or mirror in Luau).

Zig work (engine):
- None required beyond exposing the fields being tweened.
- No dt accessor required (dt is already passed into `update(dt, input)`).

---

### Heartbeat / RenderStepped

Requested:
- Per-frame update event (dt) usable by the driver

Luau work:
- This is owned by the native renderer loop. `src/integrations/native_renderer/window.zig` calls `update(dt, input)` each frame.

Zig work:
- No new DVUI API required.

---

### Input handling

Requested:
- Input events
- Hover enter/exit

Zig work (engine):
- Events are stored in `src/integrations/solid/events/mod.zig` and should be emitted by `src/integrations/solid/render/mod.zig`.
- If additional Roblox-style events are required, add them to `EventKind` and emit them from the render/event helpers.
- Hover enter/exit is not currently implemented in the solid renderer; add per-node hover tracking on `types.SolidNode` and emit `mouseenter`/`mouseleave` when listeners are registered.

Luau binding + script work:
- In `scripts/*.luau`, implement `on_event(kind, id, detail)` to route events to handlers.
- If you want an object/event model (signals, connections), build it in Luau on top of `on_event`.

---

## Config surface (Luau runtime)

Some behavior is integration-specific but shouldn't be hardcoded.

Zig work (engine):
- Add a small config surface used by the solid renderer for:
  - image search roots (used by `src/integrations/solid/render/image_loader.zig`)
  - default font ids for `font-*` tokens (used by `src/integrations/solid/style/tailwind.zig`)

Luau binding work:
- Expose config setters on `ui` (or hardcode for the native runner) before `init()` builds the tree.

---

## Notes on current repo state

- The Luau runtime currently renders through `src/integrations/native_renderer/window.zig` using the retained-style engine in `src/integrations/solid/*`.
- UI_FEATURES parity work should be implemented in `src/integrations/solid/*` and surfaced through `src/integrations/luau_ui/mod.zig`.
