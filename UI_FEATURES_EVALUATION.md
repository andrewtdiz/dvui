# UI Features Implementation Evaluation

Scope: Luau-driven retained UI via Solid (`src/integrations/solid`) + Luau bindings (`src/integrations/luau_ui`).

Legend: Implemented, Partial, Not Implemented.

## div
- Position (X/Y): Implemented (tailwind-style layout + per-node transform translation). Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/layout/mod.zig`, `src/integrations/luau_ui/mod.zig` (`set_transform`).
- Size (W/H): Implemented. Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/layout/mod.zig`.
- Anchor/Pivot point: Implemented via `Transform.anchor`. Evidence: `src/integrations/solid/core/types.zig` (`Transform`), `src/integrations/luau_ui/mod.zig` (`set_anchor`).
- Background color: Implemented via `VisualProps.background`. Evidence: `src/integrations/solid/core/types.zig` (`VisualProps`), `src/integrations/solid/style/apply.zig`.
- Transparency (alpha): Implemented via `VisualProps.opacity` (combined with colors at render time). Evidence: `src/integrations/solid/core/types.zig` (`VisualProps.opacity`), `src/integrations/luau_ui/mod.zig` (`set_visual`).
- Rotation (UI elements): Implemented via `Transform.rotation`. Evidence: `src/integrations/solid/core/types.zig` (`Transform`), `src/integrations/luau_ui/mod.zig` (`set_transform`).
- Z-index: Implemented via `VisualProps.z_index` + ordered child rendering when any child has non-zero z. Evidence: `src/integrations/solid/style/tailwind.zig` (z parsing), `src/integrations/solid/style/apply.zig`, `src/integrations/solid/render/mod.zig`.
- Clipping (clips descendants): Implemented via `VisualProps.clip_children` (and also for scroll containers). Evidence: `src/integrations/solid/render/mod.zig` (clip in `renderChildrenOrdered`), `src/integrations/luau_ui/mod.zig` (`clipChildren` in `set_visual`).

## image
- All div basics above (position/size/color/alpha): Implemented (same node pipeline). Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.
- Image source: Implemented via `SolidNode.image_src` + `NodeStore.setImageSource` and Luau `ui.set_src` / `ui.set_image`. Evidence: `src/integrations/solid/core/types.zig` (`setImageSource`), `src/integrations/luau_ui/mod.zig`.
- Image scaling + Rotation (beyond resizing the node rect): Implemented via transform scale/rotation applied during render. Evidence: `src/integrations/solid/core/types.zig` (`Transform`), `src/integrations/solid/render/mod.zig`.
- Image color/tint: Implemented via `SolidNode.image_tint` and `RenderTextureOptions.colormod`. Evidence: `src/integrations/solid/core/types.zig` (`image_tint`), `src/integrations/solid/render/mod.zig` (`renderImage`), `src/integrations/luau_ui/mod.zig` (`set_image`).
- Image transparency (separate from background alpha): Implemented via `SolidNode.image_opacity` (multiplies with node opacity). Evidence: `src/integrations/solid/core/types.zig` (`image_opacity`), `src/integrations/solid/render/mod.zig` (`renderImage`), `src/integrations/luau_ui/mod.zig` (`set_image`).

## text
- All div basics above (position/size/color/alpha): Implemented. Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.
- Text string: Implemented via text nodes (`tag == "text"` / `NodeKind.text`). Evidence: `src/integrations/luau_ui/mod.zig` (text node creation + `set_text`), `src/integrations/solid/core/types.zig`.
- Text scaling (font size via fontSizing/fontSize): Implemented (tailwind text sizing and renderer font sizing). Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/render/mod.zig`.
- Font + weight: Implemented (tailwind font tokens map to dvui fonts). Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/render/mod.zig`.
- Text color: Implemented via `VisualProps.text_color`. Evidence: `src/integrations/solid/core/types.zig` (`VisualProps`), `src/integrations/luau_ui/mod.zig` (`textColor` in `set_visual`).
- Text stroke (outline): Not Implemented (no stroke field or draw path). Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.
- Text alignment (X/Y): Partial (horizontal alignment supported via style; no dedicated vertical text alignment). Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/render/mod.zig`.
- Line wrapping: Implemented via wrapping/break-word style. Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/render/mod.zig`.

## flexbox
- Sort order: Not Implemented (child order is insertion order, with optional `before` insertion). Evidence: `src/integrations/solid/core/types.zig` (`children`), `src/integrations/luau_ui/mod.zig` (`insert`).
- Padding: Implemented via style spec -> layout padding. Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/layout/mod.zig`.
- Fill direction (vertical/horizontal): Implemented via `flex-row` / `flex-col`. Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/layout/mod.zig`.
- Alignment: Implemented via `justify-*` / `items-*`. Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/layout/mod.zig`.

## Aspect Ratio
- Aspect ratio value: Not Implemented (no layout constraint). Evidence: `src/integrations/solid/layout/mod.zig`.
- Dominant axis (Width/Height): Not Implemented. Evidence: `src/integrations/solid/layout/mod.zig`.
- Auto adjustment to maintain ratio: Not Implemented. Evidence: `src/integrations/solid/layout/mod.zig`.

## overflow
- Scrollbar support (vertical/horizontal): Implemented (dvui scroll container + ScrollBarWidget). Evidence: `src/integrations/solid/render/mod.zig`.
- Canvas size / AutomaticCanvasSize: Implemented via `ScrollState.canvas_*` / `auto_canvas`. Evidence: `src/integrations/solid/core/types.zig` (`ScrollState`), `src/integrations/luau_ui/mod.zig` (`set_scroll`).
- Scroll input handling (wheel/touch): Implemented (dvui scroll widget handles wheel + drag). Evidence: `src/integrations/solid/render/mod.zig`.

## padding
- Percent or offset padding (top/right/bottom/left): Partial (offset/bracketed px supported; percent parsing not implemented). Evidence: `src/integrations/solid/style/tailwind.zig`.

## rounded
- Corner radius: Implemented via `VisualProps.corner_radius` (and `rounded-*` tokens). Evidence: `src/integrations/solid/style/tailwind.zig`, `src/integrations/solid/style/apply.zig`, `src/integrations/luau_ui/mod.zig` (`cornerRadius` in `set_visual`).

## gradient
- Color sequence: Not Implemented (types exist; renderer doesn’t apply). Evidence: `src/integrations/solid/core/types.zig` (`Gradient`), `src/integrations/solid/render/mod.zig`.
- Transparency sequence: Not Implemented. Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.
- Rotation: Not Implemented. Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.

## transition
- Tween position/size/rotation/color/transparency: Not Implemented (no retained tween system). Evidence: `src/integrations/solid/core/types.zig`, `src/integrations/solid/render/mod.zig`.
- Easing styles: Not Implemented (no retained tween API). Evidence: `src/integrations/solid/core/types.zig`.
- Tween cancellation/override: Not Implemented. Evidence: `src/integrations/solid/core/types.zig`.
- Callback events on complete: Not Implemented. Evidence: `src/integrations/solid/core/types.zig`.

## on-frame
- App-level per-frame update callback (script `update(dt, input)`): Implemented. Evidence: `src/integrations/native_renderer/window.zig` (calls Luau `update`).
- Per-node per-frame update event: Not Implemented. Evidence: `src/integrations/solid/events/mod.zig` (no per-node frame event kind).

## on-events
- Input events (per UI element): Implemented via listeners + EventRing dispatch (`click`, `input`, `focus`, `blur`). Evidence: `src/integrations/solid/events/mod.zig`, `src/integrations/solid/render/mod.zig`, `src/integrations/native_renderer/window.zig` (calls Luau `on_event`).
- Hover enter/exit (per UI element): Implemented (`mouseenter` / `mouseleave`). Evidence: `src/integrations/solid/render/mod.zig`, `src/integrations/solid/events/mod.zig`.
- Editor-level pointer move + hover region telemetry: Not Implemented. Evidence: `src/integrations/solid/events/mod.zig`.

