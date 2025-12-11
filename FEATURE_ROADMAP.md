# SolidJS Native Renderer Feature Roadmap

This document outlines the prioritized feature development roadmap for the SolidJS to DVUI/Zig native rendering architecture.

---

## Current Status

The core incremental diff architecture is functional:
- ✅ Mutation ops (create, remove, move, listen, set)
- ✅ Version-based dirty tracking
- ✅ Event ring buffer (Zig → JS)
- ✅ Button click events working
- ✅ Basic Tailwind parsing (backgrounds, padding, margin, flex basics)
- ✅ Flex layout (direction, justify, align, gap)

---

## Priority Levels

| Priority | Description |
|----------|-------------|
| 🔴 **Critical** | Blocking common UI patterns; should be addressed first |
| 🟠 **High** | Important for real-world usage; address after critical items |
| 🟡 **Medium** | Enhances usability; can be deferred short-term |
| 🟢 **Low** | Nice-to-have; address when core is stable |

## Difficulty Levels

| Difficulty | Description |
|------------|-------------|
| ⚡ **Easy** | Straightforward implementation, isolated changes |
| 🔧 **Moderate** | Requires understanding of multiple systems |
| 🔩 **Complex** | Significant design decisions, cross-cutting concerns |
| 🧩 **Hard** | Major architectural work or research required |

---

## Phase 1: Layout & Tailwind Foundation

These features are foundational and affect almost every UI component.

### Tailwind Sizing Extensions
- **Priority:** 🔴 Critical
- **Difficulty:** 🔧 Moderate
- **Description:** Extend `tailwind.zig` parser to support additional sizing utilities
- **Scope:**
  - [ ] Fractional widths: `w-1/2`, `w-1/3`, `w-2/3`, `w-1/4`, etc.
  - [x] Viewport units: `h-screen`, `w-screen` ✅
  - [ ] `min-h-screen`
  - [ ] Max/min constraints: `max-w-sm`, `max-w-md`, `max-w-lg`, `min-h-0`, `min-w-full`
  - [ ] Arbitrary values: `w-[200px]`, `h-[50%]`

### Tailwind Spacing Utilities
- **Priority:** 🔴 Critical
- **Difficulty:** ⚡ Easy
- **Description:** Add support for space-between utilities
- **Scope:**
  - [ ] `space-x-*` (horizontal gaps between children)
  - [ ] `space-y-*` (vertical gaps between children)
  - [ ] Negative spacing variants

### Flex Advanced Properties
- **Priority:** 🟠 High
- **Difficulty:** 🔧 Moderate
- **Description:** Complete flexbox implementation
- **Scope:**
  - [ ] `flex-grow`, `flex-shrink`, `flex-basis`
  - [ ] `flex-1`, `flex-auto`, `flex-initial`, `flex-none`
  - [ ] `self-start`, `self-center`, `self-end`, `self-stretch`
  - [ ] `items-stretch` *(DVUI lacks stretch support)*
  - [ ] `order-*` for reordering children

### Text Styling
- **Priority:** 🟠 High
- **Difficulty:** ⚡ Easy
- **Description:** Expand text-related Tailwind utilities
- **Scope:**
  - [x] `text-center`, `text-right`, `text-left` ✅
  - [ ] `text-justify`
  - [ ] `text-xs`, `text-sm`, `text-base`, `text-lg`, `text-xl`, etc.
  - [ ] `font-thin`, `font-normal`, `font-medium`, `font-bold`, etc.
  - [ ] `leading-*` (line height)
  - [ ] `tracking-*` (letter spacing)

### Overflow Handling
- **Priority:** 🟠 High
- **Difficulty:** 🔩 Complex
- **Description:** Implement overflow clipping and scrolling
- **Scope:**
  - [ ] `overflow-hidden` (clip children to bounds)
  - [ ] `overflow-visible` (default, allow overflow)
  - [ ] `overflow-scroll` / `overflow-auto` (scrollable containers)
  - [ ] `overflow-x-*`, `overflow-y-*` variants

---

## Phase 2: Core Interactivity

Essential interactive patterns for building real applications.

### Text Input Handling
- **Priority:** 🔴 Critical
- **Difficulty:** 🔧 Moderate
- **Description:** Complete text input widget with two-way binding
- **Scope:**
  - [ ] `onInput` event dispatch from Zig to JS
  - [ ] Value prop synchronization (JS → Zig → input buffer)
  - [ ] Cursor position preservation
  - [ ] Selection handling
  - [ ] Placeholder text support

### Conditional Rendering Validation
- **Priority:** 🔴 Critical
- **Difficulty:** ⚡ Easy
- **Description:** Verify and fix SolidJS conditional primitives
- **Scope:**
  - [ ] `<Show when={...}>` component
  - [ ] `<For each={...}>` list rendering
  - [ ] `<Switch>` / `<Match>` conditional blocks
  - [ ] Node removal/insertion ordering edge cases
  - [ ] Keyed list updates

### Focus Management
- **Priority:** 🟡 Medium
- **Difficulty:** 🔧 Moderate
- **Description:** Implement focus state tracking and events
- **Scope:**
  - [ ] `onFocus` / `onBlur` event dispatch
  - [ ] Focus ring styling (`:focus` equivalent)
  - [ ] Tab navigation order
  - [ ] Programmatic focus control

### Keyboard Events
- **Priority:** 🟡 Medium
- **Difficulty:** ⚡ Easy
- **Description:** Complete keyboard event handling
- **Scope:**
  - [ ] `onKeyDown` / `onKeyUp` event dispatch
  - [ ] Key code and modifier detection
  - [ ] Event detail with key information
  - [ ] Form submission on Enter

### Mouse Events
- **Priority:** 🟡 Medium
- **Difficulty:** ⚡ Easy
- **Description:** Expand mouse event coverage
- **Scope:**
  - [ ] `onMouseEnter` / `onMouseLeave` (hover detection)
  - [ ] `onMouseDown` / `onMouseUp`
  - [ ] `onMouseMove` with position data
  - [ ] `onDoubleClick`

---

## Phase 3: Visual Enhancements

Features that improve visual polish and user experience.

### Border Support
- **Priority:** 🟠 High
- **Difficulty:** 🔧 Moderate
- **Description:** Implement border rendering
- **Scope:**
  - [ ] `border`, `border-2`, `border-4`, etc.
  - [ ] `border-t`, `border-r`, `border-b`, `border-l` (per-side)
  - [ ] `border-{color}` classes
  - [ ] Border rendering in direct draw path

### Box Shadows
- **Priority:** 🟡 Medium
- **Difficulty:** 🔩 Complex
- **Description:** Add shadow effects to elements
- **Scope:**
  - [ ] `shadow-sm`, `shadow`, `shadow-md`, `shadow-lg`, `shadow-xl`
  - [ ] Shadow rendering in GPU pipeline
  - [ ] Consider multi-pass or blur approximation

### Opacity & Visibility
- **Priority:** 🟡 Medium
- **Difficulty:** ⚡ Easy
- **Description:** Complete opacity handling
- **Scope:**
  - [x] `opacity-*` classes (0-100) ✅
  - [ ] `invisible` / `visible` (visibility without layout change)
  - [x] `hidden` (display: none equivalent) ✅

### Z-Index Stacking
- **Priority:** 🟡 Medium
- **Difficulty:** 🔧 Moderate
- **Description:** Implement z-order control
- **Scope:**
  - [ ] `z-*` classes parsing
  - [ ] Render order sorting by z-index
  - [ ] Stacking context handling

### Gradient Backgrounds
- **Priority:** 🟢 Low
- **Difficulty:** 🔩 Complex
- **Description:** Support linear/radial gradients
- **Scope:**
  - [ ] `bg-gradient-to-*` direction classes
  - [ ] `from-*`, `via-*`, `to-*` color stops
  - [ ] Gradient rendering in shader

---

## Phase 4: Advanced Layout

More sophisticated layout patterns.

### CSS Grid Layout
- **Priority:** 🟡 Medium
- **Difficulty:** 🔩 Complex
- **Description:** Implement CSS Grid layout engine
- **Scope:**
  - [ ] `grid`, `grid-cols-*`, `grid-rows-*`
  - [ ] `gap-*` (already works for flex)
  - [ ] `col-span-*`, `row-span-*`
  - [ ] `grid-flow-row`, `grid-flow-col`
  - [ ] Auto-placement algorithm

### Absolute/Relative Positioning
- **Priority:** 🟡 Medium
- **Difficulty:** 🔧 Moderate
- **Description:** Complete positioning modes
- **Scope:**
  - [ ] `relative`, `absolute`, `fixed`
  - [ ] `top-*`, `right-*`, `bottom-*`, `left-*` positioning
  - [ ] `inset-*` shorthand
  - [ ] Positioning relative to parent bounds

### Aspect Ratio
- **Priority:** 🟢 Low
- **Difficulty:** ⚡ Easy
- **Description:** Maintain aspect ratios
- **Scope:**
  - [ ] `aspect-square`, `aspect-video`, `aspect-auto`
  - [ ] Arbitrary aspect ratios

---

## Phase 5: Complex Interactions

Advanced interaction patterns for rich applications.

### Drag and Drop
- **Priority:** 🟢 Low
- **Difficulty:** 🧩 Hard
- **Description:** Implement native drag/drop
- **Scope:**
  - [ ] `onDragStart`, `onDrag`, `onDragEnd` events
  - [ ] `onDragEnter`, `onDragLeave`, `onDrop` targets
  - [ ] Drag preview rendering
  - [ ] Drop zone highlighting
  - [ ] Data transfer between drag source and drop target

### Tooltips & Popovers
- **Priority:** 🟢 Low
- **Difficulty:** 🔩 Complex
- **Description:** Floating UI elements
- **Scope:**
  - [ ] Tooltip component with hover trigger
  - [ ] Popover component with click trigger
  - [ ] Positioning algorithm (flip, shift, arrow)
  - [ ] Z-index management for overlay

### Modal Dialogs
- **Priority:** 🟢 Low
- **Difficulty:** 🔧 Moderate
- **Description:** Overlay modal system
- **Scope:**
  - [ ] Modal backdrop rendering
  - [ ] Focus trap within modal
  - [ ] Escape key to close
  - [ ] Portal rendering (render outside normal tree)

### Animations & Transitions
- **Priority:** 🟢 Low
- **Difficulty:** 🧩 Hard
- **Description:** CSS-like transitions and animations
- **Scope:**
  - [ ] `transition-*` property interpolation
  - [ ] Entry/exit animations
  - [ ] Keyframe animations
  - [ ] Animation timing functions

---

## Phase 6: Performance & Polish

Optimization and developer experience improvements.

### Binary Op Buffer
- **Priority:** 🟢 Low
- **Difficulty:** 🔧 Moderate
- **Description:** Replace JSON ops with binary format
- **Scope:**
  - [ ] Define packed `BinaryOp` struct
  - [ ] Implement `consumeBinaryOps` in Zig
  - [ ] TypeScript binary encoder
  - [ ] Measure performance improvement

### Idle Frame Skipping
- **Priority:** 🟢 Low
- **Difficulty:** ⚡ Easy
- **Description:** Complete idle optimization
- **Scope:**
  - [ ] Frame skip counter for debugging
  - [ ] More aggressive layout skip for clean subtrees
  - [ ] Metric reporting for skipped frames

### Hot Reload Support
- **Priority:** 🟢 Low
- **Difficulty:** 🔩 Complex
- **Description:** Fast refresh during development
- **Scope:**
  - [ ] Component state preservation
  - [ ] Incremental tree reconciliation
  - [ ] Error boundary recovery

---

## Notes

### Testing Strategy
Each feature should include:
1. A minimal test component in `solid-entry.tsx`
2. Visual verification in the native window
3. Event verification via console logs

### File Locations
- **Tailwind parsing:** `src/solid/style/tailwind.zig`
- **Layout engine:** `src/solid/layout/mod.zig`, `flex.zig`, `measure.zig`
- **Rendering:** `src/solid/render/mod.zig`, `direct.zig`, `widgets.zig`
- **Events:** `src/solid/events/ring.zig`
- **TypeScript host:** `frontend/solid/solid-host.tsx`, `runtime.ts`
