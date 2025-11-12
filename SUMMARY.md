# Overview

DVUI (Direct Zig UI), an immediate-mode GUI framework for the Zig programming language. DVUI enables developers to create user interfaces for complete applications or add debugging overlays to existing graphics applications.

## Framework Purpose and Design Philosophy
DVUI implements an immediate-mode GUI paradigm where widgets are created, processed, and destroyed within a single frame cycle. Unlike traditional retained-mode GUI frameworks, DVUI widgets are not persistent objects but rather functions that execute each frame to handle input, perform layout calculations, and render output.

## Framework Structure

DVUI follows a modular architecture with clear separation of concerns between different subsystems. The framework is built around an immediate-mode paradigm where the UI is reconstructed each frame, with persistent state managed through data storage systems.

### Major Architectural Components

#### Window Management System

Sources: 
- `src/Window.zig` 183-367
- `src/Window.zig` 13-130
- `src/Window.zig` 369-436

The Window struct manages the complete lifecycle of a GUI window, from initialization through frame processing to cleanup. It maintains all persistent state between frames and coordinates the major processing phases.

#### Backend Abstraction Layer

Sources: 
- `src/Backend.zig` 38-59
- `src/Backend.zig` 68-93
- `src/Backend.zig` 95-201

The backend system uses a VTable pattern to abstract platform-specific functionality. This allows DVUI to work across different rendering systems while maintaining a consistent internal API.

#### Event Processing Architecture
Sources: 
- `src/Event.zig` 6-26
- `src/Event.zig` 30-50
- `src/Event.zig` 95-178

Events flow through the system with specific handling semantics. Some events bubble up the widget hierarchy while others are consumed immediately. The event system supports focus management and handles both mouse and keyboard interactions.

#### Widget System Integration

##### Widget Lifecycle and Data Flow

Sources: 
- `src/widgets/IconWidget.zig` 15-34
- `src/widgets/IconWidget.zig` 37-58
- `src/widgets/DropdownWidget.zig` 28-35

Widget implementations follow a standardized lifecycle pattern. Each widget manages its own WidgetData instance and participates in the frame processing cycle through well-defined phases.

#### Options System Integration

The Options system provides a flexible way to configure widget appearance and behavior:

| Option Category | Examples | Purpose |
| --- | --- | --- |
| Layout | margin, padding, expand | Control widget positioning |
| Appearance | color_fill, border, corner_radius | Visual styling |
| Behavior | tab_index, gravity_x, gravity_y | Interaction settings |
| Content | min_size_content, max_size_content | Size constraints |

Sources: 
- `src/widgets/DropdownWidget.zig` 14-21
- `src/widgets/IconWidget.zig` 15-34

### System Integration Patterns

#### Frame Processing Coordination
Sources: 
- `src/Window.zig` 183-367
- `src/Backend.zig` 107-114
- `src/widgets/IconWidget.zig` 37-58

The frame processing follows a strict sequence where the window coordinates between the backend and widget systems. Each frame begins with event processing, continues through widget creation and layout, and ends with rendering.

#### Data Persistence Strategy

DVUI implements persistent data storage to maintain state across frames in an immediate-mode system:

Sources: 
- `src/Window.zig` 76-78
- `src/Window.zig` 153-170
- `src/dvui.zig` 1745-1850

The data persistence system uses hashed widget IDs and keys to store arbitrary data types between frames. Unused data is automatically garbage collected to prevent memory leaks.

This architectural foundation enables DVUI to provide a flexible, performant immediate-mode GUI system that abstracts platform differences while maintaining direct control over rendering and interaction.

## Event System and Window Management

### Relevant source files
This document covers DVUI's event system and window management infrastructure, including event types, routing, focus management, and the window hierarchy. It explains how user input flows from the backend through windows to individual widgets, and how the framework manages multiple windows, subwindows, and event handling.

For information about the backend abstraction layer that generates these events, see Backend System. For details about how individual widgets process events, see Widget System.

### Event Types and Structure
DVUI's event system is built around a central Event union type that encompasses all user interactions and system events.

#### Core Event Structure
Sources: 
- `src/Event.zig` 6-25

#### Event Categories
Events are divided into two categories based on their propagation behavior:

| Category | Description | Event Types |
| --- | --- | --- |
| Non-bubbleable | Processed only by the target widget | mouse |
| Bubbleable | Can propagate up the widget hierarchy | key, text, close_popup, scroll_drag, scroll_to, scroll_propagate |

Sources: 
- `src/Event.zig` 30-32

#### Mouse Event Actions
Sources: 
- `src/Event.zig` 95-121

### Event Lifecycle and Processing
Events flow through multiple stages from backend input to widget handling:

#### Event Flow Architecture
Sources: 
- `src/Window.zig` 525-692
- `src/Event.zig` 34-50

#### Event Addition Methods
The Window provides methods for adding different event types:

| Method | Purpose | Event Type |
| --- | --- | --- |
| addEventKey() | Keyboard input | Key up/down/repeat |
| addEventText() | Text input from IME | Unicode text |
| addEventMouseMotion() | Mouse movement | Motion events |
| addEventMouseButton() | Mouse clicks | Press/release |
| addEventPointer() | Touch events | Touch with normalized coordinates |
| addEventMouseWheel() | Scroll wheel | Wheel events |
| addEventTouchMotion() | Touch movement | Touch motion |

Sources: 
- `src/Window.zig` 525-750

### Window Hierarchy and Management
DVUI uses a hierarchical window system with a base window and multiple subwindows for floating elements.

#### Window Structure











Sources: 
- `src/Window.zig` 16-141

#### Subwindow Types
Subwindows serve different purposes in the UI hierarchy:

- `Base Window`: The main application window (window.wd.id)
- `Floating Windows`: Dialog boxes, menus, tooltips
- `Modal Windows`: Capture all input until closed
- `Stay-Above Windows`: Remain above specific parent windows

Sources: 
- `src/Window.zig` 131-141

#### Event Routing and Focus Management
DVUI's focus system determines which subwindow and widget receive events.

##### Focus Hierarchy








Sources: 
- `src/Window.zig` 27-31
- `src/Event.zig` 10-11

##### Focus Management Methods
| Method | Purpose |
| --- | --- |
| focusSubwindowInternal() | Switch focus between subwindows |
| focusRemainingEventsInternal() | Update event targets after focus change |
| windowFor() | Determine which subwindow contains a point |

Sources: 
- `src/Window.zig` 497-523

### Event Target Assignment
Events are assigned target windows and widgets during creation:








Sources: 
- `src/Window.zig` 594-691

### Widget Event Processing
Widgets receive events through their processEvent() methods and can handle or bubble them.

#### Event Matching and Handling








Sources: 
- `src/Event.zig` 30-50
- `src/dvui.zig` 167-177

#### Event Handling Pattern
Widgets typically follow this pattern for event processing:

- Match: Check if event applies to widget (eventMatch())
- Process: Handle the specific event type
- Handle: Mark event as handled (event.handle())
- Bubble: Pass unhandled bubbleable events to parent

Sources: 
- `src/Event.zig` 34-50

### Mouse and Touch Event Handling
Mouse and touch events follow similar patterns but with different coordinate systems.

#### Mouse Event Processing








Sources: 
- `src/Window.zig` 587-691

#### Touch Event Differences
Touch events include normalized coordinates and finger identification:

- Normalized Coordinates: Touch points as 0-1 values
- Finger Tracking: Different fingers use different button values
- Coordinate Conversion: Normalized to physical coordinates

Sources: 
- `src/Window.zig` 726-750

#### Mouse Position Tracking
The window maintains mouse position state for event processing:

| Field | Purpose |
| --- | --- |
| mouse_pt | Current mouse position |
| mouse_pt_prev | Previous mouse position |
| inject_motion_event | Force position event next frame |

Sources: 
- `src/Window.zig` 43-50

### Keyboard Event Processing
Keyboard events support keybind matching and text input handling.

#### Keybind System






Sources: 
- `src/Event.zig` 66-84
- `src/Window.zig` 88-339

#### Platform-Specific Keybinds
DVUI supports different keybind sets for different platforms:

| Platform | Modifier Key | Example Bindings |
| --- | --- | --- |
| Windows | Ctrl | Ctrl+C (copy), Ctrl+V (paste) |
| Mac | Cmd | Cmd+C (copy), Cmd+V (paste) |

Sources: 
- `src/Window.zig` 243-339

### Event Bubbling and Propagation
Bubbleable events can propagate up the widget hierarchy when unhandled.

#### Scroll Event Propagation






Sources: 
- `src/Event.zig` 170-178

#### Bubble Event Types
| Event Type | Purpose |
| --- | --- |
| ScrollDrag | Ensure scrolling during drag operations |
| ScrollTo | Request scrolling to make rect visible |
| ScrollPropagate | Propagate scroll when at limits |
| ClosePopup | Close popup menus and dialogs |

Sources: 
- `src/Event.zig` 134-178

The event system and window management work together to provide a robust foundation for user interaction in DVUI applications, handling everything from basic mouse clicks to complex multi-window focus scenarios.

## Hybrid Frontend Architecture (SolidJS Integration)

DVUI integrates a JavaScript runtime, powered by QuickJS, to enable frontend development using modern JS frameworks. The current implementation uses SolidJS with a custom reconciler, allowing developers to write UI components in JSX while leveraging the performance of the Zig backend.

### Core Components

-   **JS Runtime (`src/jsruntime/`)**: A Zig module responsible for initializing and managing the QuickJS virtual machine. It exposes native Zig functions to the JavaScript context and handles the marshalling of data and events between the two environments.
-   **SolidJS Frontend (`src/js/`)**: The frontend application code written in SolidJS and JSX. It defines the UI components and application logic.
-   **Custom Reconciler (`src/js/dvui.js`)**: A bridge that intercepts the render output of SolidJS. Instead of creating DOM nodes, it translates the JSX structure and props into a series of commands that are sent to the Zig backend for rendering. This avoids the need for a full web browser environment.

### Architectural Pattern

1.  **Initialization**: The Zig host initializes the QuickJS runtime and executes a bundled JavaScript file containing the SolidJS application.
2.  **Rendering**: The SolidJS application renders its components. The custom reconciler captures the resulting UI tree and sends a serialized representation to the Zig backend.
3.  **Native Rendering**: The Zig backend parses the command stream from the reconciler and uses the existing DVUI drawing primitives to render the UI, bypassing the need for an HTML DOM.
4.  **Event Handling**: Native events (e.g., mouse clicks, keyboard input) are captured by the Zig windowing system. They are then serialized and forwarded to the JS runtime, which dispatches them to the appropriate SolidJS components.
5.  **State Management**: Application state is managed primarily within the SolidJS application using signals. A `registerSignal` mechanism allows for two-way state synchronization between Zig and JavaScript, enabling the backend to read from or write to frontend state.

This hybrid model allows for a declarative, component-based UI development experience with SolidJS while retaining the native performance and control of the underlying DVUI framework. However, it requires implementing all rendering and layout logic for UI elements on the Zig side, as it does not use a standard web rendering engine.
