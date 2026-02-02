# Retained Mode Architecture Deep Dive

## 1. Overview & Core Philosophy

This architecture implements a **Retained Mode** layer on top of an **Immediate Mode** backend (`dvui`). The primary goal is to provide a persistent object model (DOM-like) that manages state, layout, and complex styling, while leveraging the immediate mode library for efficient low-level drawing and OS integration.

**Key Characteristics:**
-   **Data-Driven:** The UI is defined by a graph of data objects (`SolidNode`), not function calls.
-   **Stateful:** Component state (scroll position, text cursor, animations) is stored in the node graph, persisting across frames.
-   **Lazy Updates:** Layout and painting are only re-computed when the underlying data version changes.
-   **Hybrid Rendering:** Static content is drawn directly; interactive content delegates to immediate-mode widgets.

## 2. Core Data Structures

### 2.1 The Node Graph (`NodeStore`)
The `NodeStore` is the "heap" of the UI. It owns all nodes and manages their lifecycle.

-   **Structure:** A flat hash map `AutoHashMap(u32, SolidNode)`.
-   **Addressing:** Nodes are referenced by `u32` IDs. `0` is always the root.
-   **Versioning:** A global `VersionTracker` increments on every mutation.
    -   `node.version`: Last time this specific node changed.
    -   `node.subtree_version`: Last time this node or any descendant changed.
    -   `node.layout_subtree_version`: Last time a layout-affecting property changed in the subtree.
    -   *Purpose:* Allows the traverser to skip huge chunks of the tree during layout/render if `node.subtree_version < last_process_version`.

### 2.2 The Node (`SolidNode`)
The `SolidNode` is a heavyweight struct encompassing all aspects of a UI element.

| Component | Description |
| :--- | :--- |
| **Hierarchy** | `parent` (ID), `children` (List of IDs). |
| **Identity** | `tag` ("div", "button"), `id`. |
| **Styling** | `class_name` (string), `class_spec` (parsed Tailwind spec), `visual_props` (colors, radius). |
| **Layout Cache** | `rect` (Computed bounds), `child_rect` (Content area), `text_layout` (Line breaks). |
| **Persistent State** | `scroll` (Offset, canvas size), `input_state` (Text buffer, cursor), `transition_state` (Animation values). |
| **Flags** | `hovered`, `interactive_self`, `total_interactive` (Optimization flag: does subtree have events?). |

## 3. The Frame Lifecycle

The system operates in a distinct "Update -> Layout -> Render" cycle, orchestrated by `render/mod.zig`.

### Phase 1: Event & State Updates
Before rendering, external inputs or application logic might mutate the `NodeStore`.
-   API calls (e.g., `setText`, `setClassName`) update data and bump `node.version`.
-   **Transitions:** The animation engine checks for property deltas and updates `TransitionState`.

### Phase 2: Layout (`layout/mod.zig`)
The layout engine traverses the tree top-down.
1.  **Check Dirty:** If `node.layout_subtree_version > cached_layout_version`, proceed. Else skip.
2.  **Compute:**
    -   **Flexbox:** Native Zig implementation calculates positions for children.
    -   **Text:** `text_wrap` calculates line breaks and height based on font metrics.
    -   **Intrinsic:** Images/Icons report their natural size.
3.  **Output:** Writes results to `node.layout.rect`.

### Phase 3: Input & Hit Testing (`render/internal/interaction.zig`)
Unlike pure immediate mode, this system determines "what is hovered" **before** drawing.
-   **Z-Index Scanning:** A recursive scan (`scanPickPair`) finds the topmost node under the mouse cursor, respecting `z-index` and stacking contexts.
-   **Overlay Handling:** Checks if the mouse is interacting with a modal/portal layer.
-   **Result:** Sets `node.hovered` flags and updates `RenderRuntime.hover_layer`.

### Phase 4: Paint (`render/internal/renderers.zig`)
The renderer walks the tree to issue draw commands.
1.  **Clipping:** Uses `node.layout.rect` and `clip_children` property to set scissor rects.
2.  **Dirty Tracking:** A `DirtyRegionTracker` maintains a list of screen regions that need repainting. Nodes completely outside these regions are skipped.
3.  **Dispatch:**
    -   **Containers/Text/Shapes:** Drawn directly (`direct.zig`) using `dvui` primitives (triangles, rects). Fast, no widget overhead.
    -   **Interactive (Buttons/Inputs):** Delegated to `dvui.button` / `dvui.textEntry`.
        -   *Why?* DVUI handles OS clipboard, key repeats, and complex focus logic perfectly.
        -   *How?* The retained system calculates the exact `rect`, creates a `dvui.Options` struct with that rect and style, and calls the widget.

## 4. Subsystems Detail

### 4.1 Event System (`events/mod.zig`)
A **Ring Buffer** (`EventRing`) decouples the UI from the app logic.
-   **Producers:** The UI (rendering phase) pushes events (`click`, `input`, `scroll`) into the ring.
-   **Consumer:** The application polls the ring after `render()` returns.
-   **Data Layout:** Events use a packed `EventEntry` struct. Variable-length data (like typed text) is stored in a parallel `detail_buffer`.

### 4.2 Styling Engine (`style/`)
-   **Input:** String (e.g., "bg-red-500 p-4 hover:bg-red-600").
-   **Parsing:** `tailwind/parse.zig` tokenizes and converts this into a `Spec` struct.
-   **Derivation:** `derive.zig` combines the base `Spec`, hover state, and animations to produce the final `VisualProps`.
-   **Caching:** A global `SpecCache` maps string hashes to parsed `Spec`s to avoid parsing "p-4" 1000 times per frame.

### 4.3 Overlays & Portals
-   **Challenge:** Modals and tooltips must render above everything else, ignoring parent clipping (overflow: hidden).
-   **Solution:**
    -   Nodes flagged as portals are skipped during the normal recursive render.
    -   They are collected into a list (`portal_cache`).
    -   After the main tree renders, a new `dvui` **Subwindow** is opened covering the screen.
    -   Portal nodes are rendered into this subwindow, sorted by Z-index.

## 5. Persistent State Deep Dive

This is the critical differentiator from immediate mode.

### Input State (`InputState`)
-   **Problem:** In immediate mode, you must pass a buffer to the text input every frame. If the app logic updates slower than typing speed, characters are lost or the cursor jumps.
-   **Solution:** `SolidNode` owns an `InputState`. It buffers the text and cursor position *inside* the UI layer. The app only sees the finalized text via events.

### Scroll State (`ScrollState`)
-   **Problem:** Scrolling requires remembering an offset `(x, y)`.
-   **Solution:** `SolidNode` stores `offset_x` and `offset_y`.
-   **Logic:** The render function for scroll containers (`renderScrollFrame`) uses these offsets to adjust the "view" into the child content. It detects scroll events (mouse wheel, drag) and updates the stored offsets directly.

### Animations (`TransitionState`)
-   **Mechanism:** When a style changes (e.g., `opacity` 0 -> 1), the render loop sees the delta.
-   **Storage:** `TransitionState` stores:
    -   `start_time`: When the change happened.
    -   `from_value`: The value at start.
    -   `to_value`: The new target.
-   **Interpolation:** On subsequent frames, it calculates `lerp(from, to, (now - start) / duration)` and applies it to the visual properties before drawing.

## 6. Reproducing the Architecture

To build a similar system from scratch:

1.  **Define the Atom:** Create a `Node` struct. It *must* have an ID, a parent ID, and a list of child IDs.
2.  **Create the Heap:** Use a Hash Map to store Nodes. Pointers are dangerous because the map might reallocate; use IDs (handles) instead.
3.  **Implement Versioning:** Add a `global_version` and `node_version`. Every setter (e.g., `setWidth`) must bump both. This is the key to performance.
4.  **Split Layout & Render:**
    -   Don't calculate positions while drawing.
    -   Write a `layout(node_id)` function that recursively fills `node.rect`.
5.  **Build the Bridge:**
    -   Write a `render(node_id)` function.
    -   If the node is a "container", draw a rectangle.
    -   If the node is a "button", call your backend's `drawButton(node.rect, node.color)`.
6.  **Add State:** Identify what needs to persist (scroll, text input) and add those structs to your `Node`.