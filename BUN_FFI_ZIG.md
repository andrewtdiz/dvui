Here’s a clean high-level summary of the architecture in markdown.

## Shared-Memory + Polling (JS → Native call, data pull; no JSCallbacks)
Idea (proposed architecture):

JS is the only side that calls into native. Zig never calls JS. Instead, Zig writes into shared buffers (ring buffers, views), and JS polls those buffers after each frame().
Data Flow
JS → Zig (pull / drive):
Once per frame: lib.frame(statePtr)
JS also writes inputs into Zig-owned shared memory before the call.
Zig → JS (data only):
Zig simulates one frame, writes events / draws / states into:
Shared event ring buffer
Shared “render view” structs / arrays
On return, JS reads those buffers and dispatches to JS handlers entirely within JS.
Runtime Cost
1 FFI call per frame (frame()), not per event.
All events are processed as plain memory reads in JS.
JS handler calls are pure JS→JS (no native crossing).
CPU→GPU copy happens only when JS uploads shared buffers to WebGPU (expected for any graphics engine).
Memory
Engine state + bulk data allocated in Zig-owned memory.
JS holds TypedArray views over that memory (no extra copies).
Events are stored in shared ring buffers (e.g., [kind, a, b, ...]).
No JSCallback objects held by native; the interface is pure data, not function pointers.
GPU resources (buffers/textures) live in VRAM via WebGPU; JS just binds/upload from Zig-backed views.
Quick Contrast
Who calls whom?
Global / Persistent JSCallbacks: Native → JS (push).
Shared-memory + polling: JS → Native (pull), then JS consumes data.
Where is perf paid?
Callbacks: per-event native→JS boundary crossings.
Polling: single JS→native call per frame; rest is memory reads + JS→JS calls.
Where does data live / move?
Callbacks: data passed as call arguments, often marshaled each time.
Polling: data lives in Zig-owned buffers; JS reads via TypedArrays, then uploads to GPU as needed.
