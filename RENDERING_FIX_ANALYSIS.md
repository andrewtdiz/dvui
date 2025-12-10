# SolidJS Rendering Issue - Root Cause Analysis & Fix

## Problem
The SolidJS UI appeared for one frame then showed a black screen with only the FPS counter visible. The application crashed with a Bun FFI error.

## Root Cause
The crash was caused by **Bun FFI callback instability** when calling JavaScript callbacks too frequently from native code. Specifically:

1. **`sendFrameEvent()`** was called every frame (60+ times/second)
2. This FFI callback from Zig → JavaScript was triggering a Bun runtime bug
3. The crash message indicated: `bug in Bun, not your code`

The garbled output like `wovuC_i4l1oB___A2wiBgyhw7uD_renderer.dll` suggested memory corruption in Bun's FFI layer.

## Fix Applied
Temporarily disabled the per-frame FFI callbacks in `src/native_renderer.zig`:

```zig
// In renderFrame():
// Disabled per-frame logging to avoid FFI callback overhead
// Disabled sendFrameEvent() - this was the crash trigger

ray.drawFPS(10, 10);
// sendFrameEvent(renderer);  // DISABLED
```

## Verification
After disabling `sendFrameEvent()`, the application:
- Runs continuously without crashing ✅
- Shows `solid snapshot nodes=4` indicating tree is synced ✅
- Window stays open and responsive ✅

## Impact Assessment
The `sendFrameEvent` callback was used to notify JavaScript when a frame completes. With it disabled:
- UI rendering still works correctly
- Frame loop continues normally
- JavaScript loses frame-complete notifications (may affect animation timing)

## Recommended Long-Term Solutions

### Option 1: Rate-limit callbacks
Only send frame events occasionally (e.g., every 100ms) instead of every frame:
```zig
if (renderer.frame_count % 6 == 0) {
    sendFrameEvent(renderer);
}
```

### Option 2: Use polling instead of callbacks
Have JavaScript poll for frame status via a separate FFI call rather than receiving callbacks.

### Option 3: Batch callbacks
Accumulate events and send them less frequently in a batch.

### Option 4: Upgrade Bun
This may be fixed in newer Bun versions. The crash pattern suggests a Windows-specific FFI callback issue.

## Additional Changes Made
Also removed debug logging that was adding noise:
- `log.debug` calls in `drawRectDirect`, `layoutNode`, `renderText`, `render()`
- These were not causing the crash but added unnecessary output

## Files Modified
- `src/native_renderer.zig` - Disabled `sendFrameEvent()` and per-frame logging
- `src/solid_renderer.zig` - Removed debug logging, simplified non-interactive path

## Status
✅ **Application now runs stably** - The black screen issue is resolved.
⚠️ **Frame event callback disabled** - May need alternative for animation timing.
