# Guidance for Achieving Smooth Rounded Borders

This document analyzes the likely cause of pixelated borders on widgets like `ButtonWidget` and provides recommendations for implementing smooth, anti-aliased rounded corners.

## Problem Analysis

The `ButtonWidget.zig` file defines default options that include a `corner_radius` of 5, indicating that rounded corners are an intended part of the design.

The drawing logic is handled by these two functions:
- `drawBackground()` → `self.data().borderAndBackground(...)`
- `drawFocus()` → `self.data().focusBorder()`

These functions are defined in `WidgetData.zig` and are responsible for issuing the actual drawing commands to the rendering backend.

The observed pixelation, especially on the curved parts of the border, is a classic artifact known as **aliasing** or "jaggies." This happens when a smooth curve is represented on a grid of pixels without any blending on the edges. The root cause is almost certainly that the underlying rendering primitive used to draw the border does not have **anti-aliasing** enabled.

## Recommended Solution

To achieve smooth borders, you must modify the rendering pipeline to draw shapes with anti-aliasing. The current implementation likely draws the rounded border using a series of simple, aliased lines or rectangles.

Here are two common and effective approaches to solve this:

### 1. Shader-Based Rendering with Signed Distance Fields (SDFs)

This is the modern, preferred method for high-quality UI rendering.

- **How it works:** Instead of drawing the shape with vertices, you draw a simple quad (a rectangle) that covers the area of the button. A special fragment shader then runs for every pixel in that quad. The shader calculates each pixel's distance from the ideal outline of the rounded rectangle. Pixels far inside are filled, pixels far outside are discarded, and pixels very close to the edge are blended (e.g., semi-transparent), creating a smooth, anti-aliased border.

- **Advantages:**
    - Produces perfectly smooth, resolution-independent curves.
    - Highly flexible; can be used for borders, shadows, glows, and other effects.
    - Excellent performance.

- **Implementation Steps:**
    1.  **Write a Shader:** Create a new fragment shader that implements SDF logic for a rounded rectangle.
    2.  **Update `render.zig`:** Add a new drawing command or modify an existing one to use this shader.
    3.  **Modify `WidgetData.zig`:** Update the `borderAndBackground` and `focusBorder` functions to use this new anti-aliased drawing command instead of the old one.

### 2. Multisample Anti-Aliasing (MSAA)

This is a more traditional and systemic approach that can be easier to implement as a first step.

- **How it works:** MSAA is a feature of the graphics hardware. When enabled, the GPU renders the scene at a higher resolution internally and then downsamples it to the final screen size, smoothing out all geometric edges in the process.

- **Advantages:**
    - Relatively simple to enable, often requiring only a few lines of configuration in the backend.
    - Smooths *all* geometry, not just borders.

- **Disadvantages:**
    - Can be less efficient than the SDF approach as it uses more video memory.
    - May not provide the same level of quality and control for specific shapes as a dedicated shader.

- **Implementation Steps:**
    1.  **Locate Backend Code:** Find the render target (framebuffer or swap chain) configuration in your rendering backends (e.g., `src/backends/wgpu.zig`).
    2.  **Enable MSAA:** Modify the configuration to enable a sample count greater than 1 (e.g., 4x or 8x MSAA).
    3.  **Add Resolve Step:** The multi-sampled texture must be "resolved" (downsampled) to a regular texture before it can be displayed. Ensure this step is added to your render pass.

## Next Steps

1.  **Investigate `WidgetData.zig`:** Start by examining `borderAndBackground` to understand the exact drawing primitives being used.
2.  **Choose an Approach:**
    - For the highest quality and long-term flexibility, the **SDF shader approach is recommended**.
    - For a quicker, more global fix, **enabling MSAA** is a viable option.
3.  **Implement** the chosen solution by modifying the rendering code in `src/render.zig`, `src/backends/`, and `src/WidgetData.zig`.
