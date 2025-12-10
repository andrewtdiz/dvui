## 1. Geometry & Transform

* 2D position
* Size
* Scale for position/size
* Anchor / pivot point support
* Rotation (for elements and images)
* Z-ordering (z-index / draw order)
* Clipping of descendants / children (masking to parent bounds)

---

## 2. Layout & Flow

* Automatic list / flow layout of child elements

  * Sort order of children
  * Fill direction (vertical / horizontal)
  * Alignment of children within the parent
  * Inter-item padding / spacing
* Padding on containers

  * Per-side padding (top / right / bottom / left)
  * Padding defined as absolute offsets or percentages

---

## 3. Text Rendering

* Text content (string)
* Text scaling / auto-scaling to fit bounds
* Font selection
* Font weight (bold, etc.)
* Text color
* Text stroke / outline
* Text alignment on X and Y axes (e.g., left/center/right, top/middle/bottom)
* Line wrapping within bounds

---

## 4. Image Rendering

* Image source reference (URL, asset ID, etc.)
* Image scaling behavior
* Image rotation
* Image color tint / modulation
* Image transparency / alpha

---

## 5. Styling & Visual Effects

* Background color for elements
* Overall element transparency / alpha
* Corner radius (rounded corners)
* Gradient fills

  * Color sequence over the element
  * Transparency sequence over the element
  * Gradient rotation / direction

---

## 6. Constraints & Aspect Ratios

* Fixed aspect ratio for elements
* Aspect ratio value configuration
* Dominant axis selection (width or height)
* Automatic adjustment of the other axis to maintain aspect ratio

---

## 7. Scrolling & Viewports

* Scrollable containers / viewports
* Scrollbar support (vertical / horizontal)
* Configurable canvas/content size
* Automatic canvas size based on child content
* Scroll input handling (mouse wheel, touch / drag)

---

## 8. Animation & Tweening

* Tweening of element properties, including:

  * Position
  * Size
  * Rotation
  * Color
  * Transparency
* Easing functions (linear, quadratic, cubic, etc.)
* Tween cancellation / override of in-progress tweens
* Callbacks / events on tween completion

---

## 9. Frame Updates & Timing

* Per-frame or render-step update callback/event for custom logic

  * Used to move or update objects each frame

---

## 10. Input & Interaction

* Input events on elements
* Hover enter / hover exit events
