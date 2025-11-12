# Verification Criteria for Web-Based UI Migration

This document provides the grading criteria for an independent agent to verify the successful completion of the tasks outlined in `FEATURE_GUIDE.md`.

## Phase 1: Foundational Webview Integration

### Criteria for Task 1: Integrate a Web Rendering Engine

-   **Verification:**
    -   [ ] The application compiles and runs without errors.
    -   [ ] The main application window appears and displays content rendered from a web engine, not the old immediate-mode renderer. A simple "Hello, World!" text or a colored background originating from an HTML `<body>` tag is sufficient.

### Criteria for Task 2: Create and Serve a Basic `index.html`

-   **Verification:**
    -   [ ] The file `src/backends/index.html` exists.
    -   [ ] The file contains a valid HTML5 structure, including a `<body>` tag with a `<div id="root"></div>` element inside it.
    -   [ ] The application window content is confirmed to be rendered from this `index.html` file.

### Criteria for Task 3: Establish the Core Zig-to-JS Bridge

-   **Verification:**
    -   [ ] The verifier must be able to add a `window.dvui.test = (message) => alert(message);` script to `index.html`.
    -   [ ] The verifier must be able to add a call in the Zig application startup code that executes `window.dvui.test('Bridge is working!');`.
    -   [ ] Upon running the application, an alert dialog with the message "Bridge is working!" must appear.

## Phase 2: SolidJS Application and Event Handling

### Criteria for Task 4: Mount SolidJS in the Webview

-   **Verification:**
    -   [ ] The application window displays the UI from `src/js/main.jsx` (e.g., the "DVUI SolidJS Bridge" heading and buttons).
    -   [ ] The UI is interactive; for example, the "Increment" button should update the count displayed on the screen, confirming SolidJS is managing state.
    -   [ ] The custom `render` function in `src/js/dvui.js` has been removed and replaced with a standard SolidJS `render` call in `main.jsx`.

### Criteria for Task 5: Event Marshalling from Zig to JS

-   **Verification:**
    -   [ ] Add a DOM event listener in `main.jsx`, such as `document.getElementById('root').addEventListener('click', (e) => console.log('Root clicked:', e));`.
    -   [ ] When clicking inside the application window, a log message "Root clicked:" followed by a `MouseEvent` object should appear in the webview's developer console.
    -   [ ] The logged event object must contain accurate properties like `clientX`, `clientY`, and `type: 'click'`.

### Criteria for Task 6: Implement Event Bubbling

-   **Verification:**
    -   [ ] In `main.jsx`, add a click listener to a parent element (e.g., the main `<div>`) and a separate click listener to a child element (e.g., the "Increment" button).
    -   [ ] Clicking the "Increment" button must trigger the button's listener *first*, followed by the parent `<div>`'s listener.

### Criteria for Task 7: Implement JS-to-Zig Bridge for Native Actions

-   **Verification:**
    -   [ ] A function `window.dvui.native.performAction` must exist in the JS context.
    -   [ ] In the Zig backend, a message handler must be implemented that logs received messages.
    -   [ ] In `main.jsx`, add a call like `window.dvui.native.performAction('testAction', { payload: 42 })` to a button's click handler.
    -   [ ] Clicking the button must produce a log message in the Zig application's console confirming that `testAction` was received with the correct payload.

## Phase 3: Refactoring and Cleanup

### Criteria for Task 8: Deprecate Custom Reconciler and Drawing Code

-   **Verification:**
    -   [ ] The application must build and run correctly after this task.
    -   [ ] The directory `src/widgets` should be significantly reduced in size or removed entirely.
    -   [ ] The file `src/render.zig` should be removed or its contents heavily refactored to no longer contain widget-specific drawing logic.
    -   [ ] The custom `render` logic in `src/js/dvui.js` must be deleted.

### Criteria for Task 9: Update `SUMMARY.md`

-   **Verification:**
    -   [ ] The file `SUMMARY.md` must contain a new section titled "Hybrid Web Architecture".
    -   [ ] This section must accurately describe the new architecture, including the roles of the Zig backend and SolidJS frontend, and the data flow for both events and native actions.
