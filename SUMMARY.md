# DVUI Overview

- DVUI is a Zig-first UI toolkit that previously rendered its immediate-mode widgets directly through GPU backends such as WGPU, SDL, Raylib, and DirectX.
- Applications describe their UI declaratively via Zig code, and each backend drives the platform event loop and rendering surface for its target.
- The repository also contains a SolidJS-based demo front-end that now serves as the canonical web surface for hybrid applications.

## Hybrid Web Architecture

- **Zig backend**: Owns the native window, input processing, clipboard, and any platform integrations (dialogs, file pickers, timers). The backend bootstraps a `JSRuntime`, loads `src/backends/index.html`, and injects JavaScript via `executeJavaScript`. All keyboard, pointer, and IME events now flow through `dvui.Window`, which marshals them into JSON payloads before calling `JSRuntime.dispatchNativeEvent`.

- **SolidJS frontend**: Compiled by `scripts/build-main.ts` into `zig-out/web/main.js`, then mounted onto `<div id="root">` inside the HTML shell. UI state and layout are handled with ordinary DOM nodes and CSS instead of custom canvases or texture atlases. The front-end exposes a global `window.dvui` namespace that provides `dispatchNativeEvent` plus `native.performAction`.

- **Event flow**: native input → `dvui.Window.addEvent*` → JSON marshalling → `JSRuntime.dispatchNativeEvent` → `window.dvui.dispatchNativeEvent(event)` → DOM event (`MouseEvent`, `KeyboardEvent`, etc.) → SolidJS components.

- **Action flow**: SolidJS code calls `window.dvui.native.performAction(name, payload)` → host bridge posts JSON to Zig → `JSRuntime.handleMessageFromJs` validates the envelope and routes it through a registered Zig callback → backend executes the requested native action (show dialog, start computation, etc.).

- **Webview lifecycle**: The WGPU backend now accepts an optional `js_runtime` pointer. When present it loads the HTML template during `begin` and short-circuits GPU drawing so the operating system-provided webview becomes the primary surface. Future work can embed a real platform webview (Edge WebView2, WKWebView, WebKitGtk) using the same `JSRuntime` hooks.
