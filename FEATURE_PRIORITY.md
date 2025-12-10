# Frontend Features: Difficulty & Utility Analysis

Analysis of UI features for an indie game engine, rated for **technical difficulty** (1-5, higher = harder) and **utility** (1-5, higher = more useful).

---

## Summary Matrix

| Feature | Difficulty | Utility | Priority | Notes |
|---------|:----------:|:-------:|:--------:|-------|
| **Geometry & Transform** |
| 2D position | 1 | 5 | 🔴 Critical | Foundation of all layout |
| Size | 1 | 5 | 🔴 Critical | Foundation |
| Scale | 2 | 4 | 🟡 High | Essential for juice/animation |
| Anchor/pivot | 2 | 4 | 🟡 High | Required for rotation, scaling from point |
| Rotation | 2 | 4 | 🟡 High | Common for effects, indicators |
| Z-ordering | 2 | 5 | 🔴 Critical | Layering is fundamental |
| Clipping | 3 | 4 | 🟡 High | Needed for scroll views, masks |
| **Layout & Flow** |
| Flexbox layout | 4 | 5 | 🔴 Critical | Auto-layout is high-value |
| Sort order | 2 | 3 | 🟢 Medium | Nice for dynamic lists |
| Fill direction | 2 | 5 | 🔴 Critical | Part of flex implementation |
| Alignment | 3 | 5 | 🔴 Critical | Centering, distribution |
| Spacing/gap | 2 | 4 | 🟡 High | Common need |
| Per-side padding | 2 | 4 | 🟡 High | Standard box model |
| Percentage padding | 3 | 2 | 🟢 Medium | Rarely needed |
| **Text Rendering** |
| Text content | 1 | 5 | 🔴 Critical | Fundamental |
| Auto-scaling text | 4 | 3 | 🟢 Medium | Nice, but complex |
| Font selection | 2 | 4 | 🟡 High | Multiple fonts common |
| Font weight | 2 | 3 | 🟢 Medium | Bold/normal usually enough |
| Text color | 1 | 5 | 🔴 Critical | Basic styling |
| Text stroke/outline | 4 | 3 | 🟢 Medium | Useful for readability |
| Text alignment | 2 | 5 | 🔴 Critical | Common need |
| Line wrapping | 3 | 4 | 🟡 High | Essential for descriptions |
| **Image Rendering** |
| Image source | 1 | 5 | 🔴 Critical | Foundation |
| Image scaling | 2 | 5 | 🔴 Critical | Fit, fill, stretch |
| Image rotation | 2 | 3 | 🟢 Medium | Less common for UI |
| Image tint | 2 | 4 | 🟡 High | Great for theming, state |
| Image alpha | 1 | 4 | 🟡 High | Common for fade effects |
| **Styling & Effects** |
| Background color | 1 | 5 | 🔴 Critical | Foundation |
| Element alpha | 1 | 5 | 🔴 Critical | Fade in/out |
| Corner radius | 2 | 4 | 🟡 High | Modern look |
| Gradient fills | 3 | 3 | 🟢 Medium | Nice polish |
| Gradient rotation | 3 | 2 | ⚪ Low | Rarely needed |
| **Constraints** |
| Fixed aspect ratio | 3 | 3 | 🟢 Medium | Images, cards |
| Dominant axis | 3 | 2 | ⚪ Low | Niche use |
| **Scrolling** |
| Scroll containers | 4 | 5 | 🔴 Critical | Lists, inventories, logs |
| Scrollbars | 3 | 3 | 🟢 Medium | Visual feedback |
| Content size | 2 | 4 | 🟡 High | Part of scroll impl |
| Auto content size | 3 | 4 | 🟡 High | Convenience |
| Scroll input | 3 | 5 | 🔴 Critical | Mouse wheel, drag |
| **Animation** |
| Position tween | 2 | 5 | 🔴 Critical | Core animation |
| Size tween | 2 | 4 | 🟡 High | Expand/collapse |
| Rotation tween | 2 | 4 | 🟡 High | Spin effects |
| Color tween | 2 | 4 | 🟡 High | State changes |
| Alpha tween | 2 | 5 | 🔴 Critical | Fade in/out |
| Easing functions | 2 | 5 | 🔴 Critical | Makes animation feel good |
| Tween cancel/override | 3 | 4 | 🟡 High | Responsive interruption |
| Completion callbacks | 2 | 4 | 🟡 High | Sequencing, chaining |
| **Frame Updates** |
| Per-frame callback | 1 | 5 | 🔴 Critical | Custom logic hook |
| **Input & Interaction** |
| Input events | 2 | 5 | 🔴 Critical | Click, touch |
| Hover events | 2 | 4 | 🟡 High | Desktop UX |

---

## Detailed Analysis

### 🔴 Critical (Utility 5, Difficulty 1-2)
**Ship without these = broken engine**

| Feature | Why Critical | Implementation Notes |
|---------|--------------|---------------------|
| Position, size | Everything needs placement | Store x, y, w, h per node |
| Z-ordering | Layering modals, tooltips | Sort by z before render |
| Text content | Every game has text | Already have `dvui.label` |
| Text color | State feedback | Pass to render options |
| Background color | Containers, buttons | Already in Tailwind subset |
| Element alpha | Fade transitions | Multiply in render |
| Image source | Icons, portraits | Already have image loading |
| Image scaling | Fit UI containers | Scale modes in options |
| Per-frame callback | Game logic integration | Already have frame loop |
| Input events | Buttons must work | Already have click handlers |

**Effort**: Low. Most are already implemented or trivial additions.

---

### 🟡 High Priority (Utility 4-5, Difficulty 2-3)
**Needed for a polished feel**

| Feature | Why Important | Implementation Notes |
|---------|---------------|---------------------|
| Flexbox layout | Auto-arranging children | Already using `dvui.flexbox` |
| Scale, rotation | Animation juice | Transform struct (proposed) |
| Anchor/pivot | Rotate around center | Add to Transform |
| Clipping | Scroll views, masks | `dvui.pushClipRect` |
| Line wrapping | Dialogue, descriptions | DVUI text handles this |
| Corner radius | Modern look | Already in Tailwind subset |
| Image tint/alpha | Theming, disabled states | Color modulation in render |
| All tweens | UI feels alive | JS-side animation + FFI |
| Easing functions | Professional feel | Library (e.g., `@solid-primitives/tween`) |
| Hover events | Desktop feedback | DVUI hit testing |
| Scroll containers | Inventories, logs | Complex but essential |

**Effort**: Medium. Requires new FFI ops for transforms, scroll state management.

---

### 🟢 Medium Priority (Utility 3, Difficulty 2-4)
**Nice to have, defer if time is tight**

| Feature | Why Defer | When to Add |
|---------|-----------|-------------|
| Auto-scaling text | Complex measurement | When dialogue boxes need it |
| Font weight | Bold is usually enough | When typography is a focus |
| Text stroke | Readability on images | When needed for aesthetics |
| Image rotation | Rare for UI | When adding spinning icons |
| Gradient fills | Polish | After core is solid |
| Scrollbars | Can use invisible scroll | When users request feedback |
| Aspect ratio | Specific use cases | When image containers need it |
| Sort order | Dynamic lists | When leaderboards, etc. |
| Percentage padding | Rarely needed | Probably never |

**Effort**: Varies. Some are easy (font weight), others complex (auto-scaling text).

---

### ⚪ Low Priority (Utility ≤2)
**Skip unless specifically requested**

| Feature | Why Low |
|---------|---------|
| Gradient rotation | Edge case |
| Dominant axis selection | Niche constraint system |

---

## Recommended Implementation Order

### Phase 1: Foundation
Already mostly done. Verify these work:
- Position, size, z-order ✓
- Text content, color, alignment ✓
- Background color ✓
- Image source, scaling ✓
- Click events ✓
- Per-frame callback ✓

### Phase 2: Transform & Animation
Highest impact for "game feel":
1. Add `Transform` struct (scale, rotation, anchor, translation)
2. Add `set_transform` FFI op
3. Add `set_visual` FFI op (alpha primarily)
4. Integrate JS tween library
5. Test: spinning icons, fade transitions, scale pulses

### Phase 3: Layout Polish
1. Verify flexbox works for common cases
2. Add clipping for scroll containers
3. Implement basic scroll container with mouse wheel
4. Add corner radius if not working
5. Test: inventory grid, scrollable log

### Phase 4: Text & Images
1. Font selection (if not working)
2. Line wrapping verification
3. Image tint/alpha
4. Test: dialogue boxes, item tooltips

### Phase 5: Polish
- Hover events
- Scrollbars
- Gradients
- Text stroke
- Auto-scaling text

---

## Effort vs Impact Chart

```
                        HIGH UTILITY
                             │
     ┌───────────────────────┼───────────────────────┐
     │ Scroll containers    │ Position, size        │
     │ Flexbox layout       │ Z-order               │
     │ Clipping             │ Text content/color    │
     │                       │ Background color      │
     │                       │ Element alpha         │
     │                       │ Input events          │
     │                       │ Per-frame callback    │
HARD ├───────────────────────┼───────────────────────┤ EASY
     │ Auto-scaling text    │ Scale, rotation       │
     │ Text stroke          │ Anchor/pivot          │
     │ Gradient fills       │ Corner radius         │
     │                       │ Image tint/alpha      │
     │                       │ Tweens + easing       │
     │                       │ Hover events          │
     └───────────────────────┼───────────────────────┘
                             │
                        LOW UTILITY
```

**Focus on the right side first** (easy + high utility), then move left (hard + high utility).
