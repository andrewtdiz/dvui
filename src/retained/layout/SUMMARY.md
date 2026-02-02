# Layout Module Summary

This directory contains the layout engine for the retained mode UI system. It is responsible for calculating the position and size of every node in the render tree.

## Core Components

### `mod.zig`
The main entry point for the layout system.
- **Lifecycle Management:** Handles `updateLayouts` to trigger layout passes, checking for screen size changes or dirty nodes.
- **Layout Computation:** `computeNodeLayout` calculates the final rectangle (`rect`) and content rectangle (`child_rect`) for a node, applying margins, padding, borders, and scroll offsets.
- **Delegation:** Delegates specific layout strategies (like flexbox) to other modules.
- **Anchoring:** implementation of `applyAnchoredPlacement` to handle nodes anchored to others (popups, tooltips).
- **Scrolling:** Calculates scrollable content size (`updateScrollContentSize`).

### `flex.zig`
Implements a native Zig flexbox layout algorithm.
- **`layoutFlexChildren`:** The primary function that arranges children according to flexbox rules (direction, justify, align, gap).
- **Features:** Supports horizontal/vertical direction, various alignment modes, and absolute positioning of children within a flex container.

### `measure.zig`
Responsible for determining the intrinsic size of nodes.
- **`measureNodeSize`:** Calculates the required width and height for a node based on its content, styles (explicit size, padding, border), and children.
- **Text Measurement:** `measureTextCached` efficiently measures text nodes, caching results to avoid expensive re-calculations.
- **Combined Text:** Handles measurement for complex text elements (like paragraphs with mixed content) by collecting text and simulating wrapping.

### `text_wrap.zig`
Handles text wrapping and line breaking.
- **`computeLineBreaks`:** Splits text into lines given a maximum width, font, and scale.
- **Logic:** Supports wrapping, word breaking, and preserving whitespace. It calculates the total height and maximum line width required for the text block.

### `yoga.zig`
An alternative flexbox implementation using the Yoga layout engine.
- Wraps `yoga-zig` to provide the same `layoutFlexChildren` interface as `flex.zig`.
- Maps internal style enums to Yoga enums.
- *Note:* Enabled via the `use_yoga_layout` flag in `mod.zig`.
