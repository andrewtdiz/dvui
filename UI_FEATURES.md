# UI Features Checklist

## div
- [x] Position (X/Y)
- [x] Size (W/H)
- [x] Anchor/Pivot point
- [x] Background color
- [x] Transparency (alpha)
- [x] Rotation (UI elements)
- [x] Z-index
- [x] Clipping (clips descendants)

## image
- [x] All div basics above (position/size/color/alpha)
- [x] Image source
- [x] Image scaling + Rotation (beyond resizing the node rect)
- [x] Image color/tint
- [x] Image transparency (separate from background alpha)

## textp
- [x] All div basics above (position/size/color/alpha)
- [x] Text string
- [x] Text scaling (font size via fontSizing/fontSize)
- [x] Font + weight
- [x] Text color (color applies as textColor for text nodes)
- [ ] Text stroke (outline)
- [ ] Text alignment (X/Y) (partial: X only)
- [x] Line wrapping

## flexbox
- [ ] Sort order
- [x] Padding
- [x] Fill direction (vertical/horizontal)
- [x] Alignment

## Aspect Ratio
- [ ] Aspect ratio value
- [ ] Dominant axis (Width/Height)
- [ ] Auto adjustment to maintain ratio

## overflow
- [x] Scrollbar support (vertical/horizontal)
- [x] Canvas size / AutomaticCanvasSize
- [x] Scroll input handling (wheel/touch)

## padding
- [ ] Percent or offset padding (top/right/bottom/left) (partial: offset only)

## rounded
- [x] Corner radius

## gradient
- [ ] Color sequence
- [ ] Transparency sequence
- [ ] Rotation

## transition
- [ ] Tween position/size/rotation/color/transparency
- [ ] Easing styles (Sine, Quad, Cubic, Quart, Quint, Expo, Circ, Back, Elastic, Bounce)
- [ ] Easing Direction (In, Out, and InOut)

## on-frame
- [x] App-level per-frame update callback (script `update(dt, input)`)
- [ ] Per-node per-frame update event

## on-events
- [x] Input events (per UI element)
- [x] Hover enter/exit (per UI element)
- [ ] Editor-level pointer move + hover region telemetry (host-only; not per-element UI events)

