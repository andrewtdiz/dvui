# Retained Style Module Summary

This module implements a Tailwind-CSS-inspired styling system for the retained mode UI in `dvui`. It allows defining styles using string-based classes which are parsed into structured specifications (`Spec`) and then applied to UI components.

## Core Components

### 1. Main Interface (`mod.zig`, `tailwind.zig`)
- **`mod.zig`**: Exports submodules (`tailwind`, `apply`, `colors`).
- **`tailwind.zig`**: The central hub.
    - **Caching**: Implements a `SpecCache` to store parsed specs for performance, avoiding re-parsing common class strings.
    - **Public API**: `parse()`, `applyToOptions()`, `buildFlexOptions()`.
    - **Hover Support**: Logic to apply hover-specific styles (`applyHover`, `hasHover`).

### 2. Application Logic (`apply.zig`)
- Bridges the gap between the abstract `Spec` and `dvui`'s concrete types (`dvui.Options`, `SolidNode`).
- **`applyClassSpecToVisual`**: Applies style properties (colors, opacity, z-index, radii) to a retained mode `SolidNode`.
- **`applyToOptions`**: Applies style properties to immediate mode `dvui.Options` (used by the retained mode renderer).
- **Color Packing**: Utilities to convert between `dvui.Color` and packed integer representations used in visual props.

### 3. Data Definitions (`colors.zig`, `tailwind/types.zig`)
- **`colors.zig`**: Defines the standard color palette (e.g., `slate-500`, `blue-600`, `transparent`).
- **`tailwind/types.zig`**: Defines the `Spec` struct which holds all parsed style attributes.
    - Includes enums for `TextAlign`, `FontWeight`, `Position`, `EasingStyle`, etc.
    - `SideValues`: Helper for margin/padding/border properties that can vary per side.
    - `TransitionConfig`: Configuration for style animations.

### 4. Parsing Engine (`tailwind/parse*.zig`)
The parsing logic is split into domain-specific modules:
- **`tailwind/parse.zig`**: The main parser loop. Tokenizes class strings and delegates to specific handlers. Handles general tokens like hover prefixes, literals (`flex`, `hidden`), and anchors.
- **`tailwind/parse_layout.zig`**: Handles layout-related tokens.
    - Spacing (`m-`, `p-`), Sizing (`w-`, `h-`), Borders (`border-`), Radius (`rounded-`), Insets (`top-`, `left-`), Gaps (`gap-`).
    - Supports pixel values and bracket syntax (e.g., `w-[50px]`).
- **`tailwind/parse_color_typography.zig`**: Handles visual and text tokens.
    - Colors (`bg-`, `text-`, `border-`), Opacity (`opacity-`).
    - Typography (`text-xl`, `font-bold`, `italic`).
    - Font resolution logic (mapping generic families like `sans`/`mono` to `dvui` font IDs).

## Supported Features
- **Layout**: Flexbox (`flex`, `flex-row`, `justify-*`, `items-*`), Absolute positioning, Margins/Padding, Sizing (fixed, full, screen).
- **Typography**: Font families, weights, sizes, alignment, text wrapping.
- **Visuals**: Background colors, Text colors, Borders, Corner radius, Opacity, Z-Index.
- **Interactivity**: Hover states (`hover:bg-red-500`), Cursor styles (`cursor-pointer`).
- **Animations**: Transitions for layout, transform, colors, and opacity with customizable duration and easing.

## Usage Flow
1. **Parse**: `tailwind.parse("bg-red-500 p-4")` returns a `Spec`.
2. **Cache**: The parser checks the internal cache first.
3. **Apply**: The `Spec` is passed to `apply.applyClassSpecToVisual` (for updating the render node) or `apply.applyToOptions` (for configuring `dvui` widgets).
