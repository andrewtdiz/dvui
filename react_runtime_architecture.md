# React Native Runtime Architecture Guide

This document provides high-level guidance for organizing the React-to-Zig runtime. The goal is to establish a scalable architecture that separates concerns, simplifies the addition of new components, and provides a clear path for implementing advanced features like styling and complex event handling.

## Core Principle: A Declarative JavaScript Renderer

The central principle is to treat the entire JavaScript side as a **declarative renderer**. Its sole responsibility is to prepare and send a clean, structured "render packet" to the native (Zig) layer on every state change.

-   **JavaScript's Role (The "Renderer"):**
    -   Manage application state via React.
    -   Parse styles (e.g., Tailwind classes).
    -   Manage event listeners.
    -   On state changes, produce a complete, declarative description of the UI.

-   **Zig's Role (The "Host"):**
    -   Act as a "dumb" rendering client.
    -   Receive the render packet from JavaScript.
    -   Render the UI exactly as described in the packet.
    -   Forward raw input events (clicks, mouse movement) back to JavaScript.

This separation ensures that presentation logic lives in JavaScript, while the native layer focuses purely on performance-critical rendering.

## Proposed Project Structure

To enforce separation of concerns, the JavaScript logic should be organized as follows:

```
/resources/js/
|
|-- /components/      # Dumb React components mapping 1:1 to native widgets.
|   |-- Button.jsx
|   |-- Label.jsx
|   |-- Box.jsx
|
|-- /runtime/         # Core modules that power the renderer.
|   |-- reconciler.js   # (Existing) React reconciler setup.
|   |-- hostConfig.js   # (Existing) React host configuration.
|   |-- serializer.js   # NEW: Logic to create the render packet.
|   |-- styleParser.js  # NEW: Logic to parse CSS classes into style objects.
|   |-- eventManager.js # NEW: Manages component state (hover) and listener callbacks.
|
|-- /bridge/          # The explicit interface between JS and Zig.
|   |-- native.js       # Functions that call *into* Zig (e.g., engine.render).
|   |-- events.js       # Functions for Zig to call *into* JS (e.g., onNativeEvent).
|
|-- main.jsx          # Application entry point and main render loop orchestration.
```

## Guidance for Feature Expansion

### 1. Adding New Components

To add a new component (e.g., a `TextInput`):

1.  **Create the React Component (`/components/TextInput.jsx`):**
    -   This is a standard React component that accepts props like `value`, `onChange`, `className`, etc.
    -   It should render with the appropriate type, e.g., `return <textinput {...props} />;`. The reconciler will use this lowercase `textinput` type string.

2.  **Update the Serializer (`/runtime/serializer.js`):**
    -   Add logic to handle the `textinput` type. This includes registering its `onChange` listener with the `eventManager` and packaging any specific props it needs.

3.  **Update the Zig Renderer (`raylib-ontop.zig`):**
    -   Add a case to handle the `textinput` command type and render the corresponding `dvui` widget.

This isolates the logic, preventing changes from cascading across the entire codebase.

### 2. Parsing Tailwind Classes

The current approach of parsing class names in Zig is not scalable.

1.  **Create a Style Parser (`/runtime/styleParser.js`):**
    -   This module exports a function: `parseClassNames(className, componentState)`.
    -   It takes the `className` string and the component's current state (e.g., `{ isHovered: true }`).
    -   It returns a structured `style` object:
        ```javascript
        // Input: "bg-blue-500 hover:bg-blue-700", { isHovered: true }
        // Output:
        {
          backgroundColor: 0x3B82F6FF, // Resolved color for bg-blue-700
        }
        ```
    -   This module contains all the logic for mapping class names to color values and handling state variants like `hover:`.

2.  **Integrate with the Serializer:**
    -   The `serializer.js` will call `parseClassNames` for each component and attach the resulting `style` object to the render command.

3.  **Simplify the Zig Renderer:**
    -   The Zig code no longer parses strings. It simply checks for the existence of properties on the `style` object (e.g., `command.style.backgroundColor`) and applies them.

### 3. Handling Hover and Mouse Events

A robust event system is crucial for features like `hover:`.

1.  **Centralize Native Events (`/bridge/events.js`):**
    -   Expose a single function for Zig to call: `globalThis.dispatchNativeEvent(type, payload)`.
    -   Examples:
        -   `dispatchNativeEvent('click', { componentId: '...' })`
        -   `dispatchNativeEvent('mouseEnter', { componentId: '...' })`
        -   `dispatchNativeEvent('mouseLeave', { componentId: '...' })`

2.  **Create an Event Manager (`/runtime/eventManager.js`):**
    -   This stateful module tracks the state for every component (e.g., which component is currently hovered).
    -   It receives events from `dispatchNativeEvent` and updates its internal state.
    -   It calls the appropriate React prop handlers (`onClick`, `onMouseEnter`).
    -   **Crucially, after updating state, it triggers a new React render.**

3.  **Implement the Hover Logic:**
    -   **Zig:** In the main loop, track which `dvui` widget ID is currently under the mouse. When this ID changes, call `dispatchNativeEvent` for `mouseLeave` (on the old ID) and `mouseEnter` (on the new ID).
    -   **JS:** The `eventManager` receives these events and updates the hover state for the respective components. It then triggers a re-render.
    -   **Render Cycle:** During the new render, the `serializer` asks the `eventManager` for the component's state. The `styleParser` receives `{ isHovered: true }` and correctly applies the `hover:` styles. The new render packet is sent to Zig, and the UI updates visually.

By adopting this organized, modular approach, the runtime becomes far more robust and easier to extend, accelerating the development of a rich component library.