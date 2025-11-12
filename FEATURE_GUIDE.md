# Feature Migration Guide: From Custom Reconciler to Web-Based UI

This document outlines the tasks required to migrate the DVUI framework from its current custom SolidJS reconciler to a web-based architecture. The goal is to enable development with standard HTML and CSS, rendered within a webview, while maintaining a performant bridge to the Zig backend.

You may read `SUMMARY.md` for an overview of the project structure.

## Phase 1: Foundational Webview Integration

This phase focuses on replacing the custom rendering engine with a standard web rendering component and establishing the basic HTML-based workflow.

### Task 1: Integrate a Web Rendering Engine

-   **Objective:** Replace the current immediate-mode and custom reconciler rendering with a webview. The application window should display HTML content.
-   **Key Actions:**
    1.  Choose and integrate a web rendering library compatible with the existing `wgpu` backend or a lightweight platform-native webview library (e.g., `webview` for Zig).
    2.  Modify the main application loop in `App.zig` and the `wgpu` backend in `src/backends/wgpu.zig` to initialize and manage the webview lifecycle.
    3.  The webview should become the primary surface rendered into the main window.

### Task 2: Create and Serve a Basic `index.html`

-   **Objective:** Provide a minimal HTML document that will serve as the mounting point for the SolidJS application.
-   **Key Actions:**
    1.  Create a new file, `src/backends/index.html`.
    2.  This file should contain a basic HTML5 structure (`<!DOCTYPE html>`, `<html>`, `<head>`, `<body>`).
    3.  The `<body>` must include a root element for the SolidJS application to mount to, e.g., `<div id="root"></div>`.
    4.  Modify the webview integration to load this `index.html` file as its content upon initialization.

### Task 3: Establish the Core Zig-to-JS Bridge

-   **Objective:** Create a simple, robust communication channel from the Zig backend to the JavaScript running in the webview.
-   **Key Actions:**
    1.  Implement a function in Zig that can execute arbitrary JavaScript code within the webview context.
    2.  Refactor the existing `JSRuntime` (`src/jsruntime/runtime.zig`) to use this new execution method instead of QuickJS directly for UI-related tasks. The QuickJS runtime may still be useful for non-UI background tasks.
    3.  Create a global `dvui` object in the JavaScript environment (`window.dvui`) to serve as the namespace for all bridged functions.

## Phase 2: SolidJS Application and Event Handling

This phase focuses on getting the SolidJS application running within the new webview and establishing a complete, event-driven communication layer.

### Task 4: Mount SolidJS in the Webview

-   **Objective:** Compile and run the existing SolidJS application within the webview.
-   **Key Actions:**
    1.  Update the JavaScript build process (`scripts/build-main.ts`) to produce a single, bundled JS file that can be injected into or loaded by `index.html`.
    2.  Modify `src/js/main.jsx` to use SolidJS's standard `render` function to mount the `App` component to the `#root` div in `index.html`.
    3.  Remove the custom `render` and `registerSignal` logic from `src/js/dvui.js`, as state will be managed by SolidJS and the DOM. A new bridge mechanism will be created for Zig/JS state synchronization if needed.

### Task 5: Event Marshalling from Zig to JS

-   **Objective:** Capture native window events (mouse, keyboard) in the Zig backend and forward them to the JS environment as standard DOM events.
-   **Key Actions:**
    1.  The Zig backend (`wgpu.zig`, `Window.zig`) should capture user input events.
    2.  Create a JS function, e.g., `window.dvui.dispatchNativeEvent(eventObject)`, that can receive an event description from Zig.
    3.  In Zig, when a native event occurs, construct a JSON object that mimics a standard JS event (e.g., `{ type: 'click', clientX: 100, clientY: 200, target: '#some-element-id' }`).
    4.  Call `dispatchNativeEvent` with this JSON object.
    5.  In the JS layer, the `dispatchNativeEvent` function will parse the object and use `document.createEvent` and `element.dispatchEvent` to inject the event into the DOM.

### Task 6: Implement Event Bubbling

-   **Objective:** Ensure that events dispatched into the DOM follow standard bubbling behavior.
-   **Key Actions:**
    1.  When creating events in the `dispatchNativeEvent` function, ensure the `bubbles` property is set to `true` for all relevant event types (e.g., `click`, `mousedown`, `keydown`).
    2.  Verify that an event triggered on a nested element correctly propagates up to parent elements, triggering their event listeners in sequence.

### Task 7: Implement JS-to-Zig Bridge for Native Actions

-   **Objective:** Allow the SolidJS application to trigger actions in the Zig backend.
-   **Key Actions:**
    1.  The webview integration must provide a mechanism for JS to send messages back to Zig. This is often an injected "host" object or a message handler.
    2.  Create a function in JS, e.g., `window.dvui.native.performAction(actionName, payload)`, that sends a message to the Zig host.
    3.  In Zig, create a callback handler that receives these messages and dispatches them to the appropriate Zig functions (e.g., show a native file dialog, perform a heavy computation).

## Phase 3: Refactoring and Cleanup

This phase focuses on removing obsolete code and documenting the new architecture.

### Task 8: Deprecate Custom Reconciler and Drawing Code

-   **Objective:** Remove all code related to the immediate-mode UI and the custom SolidJS reconciler.
-   **Key Actions:**
    1.  Delete the custom reconciler logic in `src/js/dvui.js` and related files.
    2.  Analyze and remove the now-unused widget rendering logic from `src/render.zig` and the `src/widgets/` directory.
    3.  Remove the custom `FrameCommand` processing loop from the Zig backend, as rendering is now handled by the webview.

### Task 9: Update `SUMMARY.md`

-   **Objective:** Document the new web-based architecture.
-   **Key Actions:**
    1.  Add a new section to `SUMMARY.md` titled "Hybrid Web Architecture".
    2.  Describe the role of the Zig backend (windowing, event capture, native action provider) and the SolidJS frontend (state management, UI rendering via HTML/CSS).
    3.  Explain the event flow from native input -> Zig -> JS -> DOM, and the action flow from JS -> Zig.
