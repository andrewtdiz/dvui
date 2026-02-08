# Fix DVUI WGPU Multi-Encode Safety

## Summary

Make dvui’s WGPU backend safe to call encode() multiple times before a single queue.submit() by switching vertex/index/globals/MSDF uploads to append-only regions with per-encode/per-draw base offsets, and by keeping replaced GPU resources alive for max_frames_in_flight frames.

## Constraints / Decisions Locked

- Resource lifetime handling respects max_frames_in_flight (release replaced GPU resources after N frames, not immediately).

## DVUI Changes (Core Fix)

File: dvui/src/backends/wgpu.zig

### 1) Add per-frame upload heads

Add fields to WgpuBackend:

- vertex_upload_head_bytes: u64
- index_upload_head_bytes: u64
- globals_upload_head_bytes: u64
- msdf_upload_head_bytes: u64

Reset these to 0 in pub fn begin(...).

### 2) Add a small “retire later” resource ring (buffer + bind group)

Purpose: when a buffer or bind group is replaced due to growth, the old one must stay alive until already-recorded command buffers have executed.

Add types/fields:

- const RetiredFrame = struct { buffers: std.ArrayListUnmanaged(*wgpu.Buffer) = .{}, bind_groups: std.ArrayListUnmanaged(*wgpu.BindGroup) = .{} };
- retired_frames: []RetiredFrame
- retired_frame_index: usize

Initialization and teardown:

- In pub fn init(...): allocate retired_frames = try gpa.alloc(RetiredFrame, options.max_frames_in_flight + 1) and default-init each element.
- In pub fn deinit(...): release all resources remaining in all retired_frames slots, then deinit the ArrayLists and gpa.free(retired_frames).

Frame rotation:

- In pub fn begin(...):
    1. Advance retired_frame_index = (retired_frame_index + 1) % retired_frames.len
    2. Release all buffers and bind groups in retired_frames[retired_frame_index], then clear those lists
    3. Reset upload heads to 0
    4. Keep existing clearFrameData() behavior

Retirement helper behavior:

- When replacing a buffer or bind group, append the old pointer to retired_frames[retired_frame_index].buffers or .bind_groups and do not call .release() immediately.

### 3) Make writeBufferAligned take a base offset

Change:

- From: fn writeBufferAligned(self: *WgpuBackend, buffer: *wgpu.Buffer, data: []const u8) !void
- To: fn writeBufferAligned(self: *WgpuBackend, buffer: *wgpu.Buffer, base_bytes: u64, data: []const u8) !void

Behavior:

- Write the main chunk at base_bytes
- Write tail padding at base_bytes + main_len
- Require base_bytes to be 4-byte aligned (enforced by callers via alignment)

### 4) Change geometry upload to append-only and return per-encode base offsets

Introduce:

- const GeometryUpload = struct { vertex_base_bytes: u64, index_base_bytes: u64 };

Change fn uploadGeometry(self: *WgpuBackend) !GeometryUpload:

- Compute vertex_bytes, index_bytes
- Compute aligned sizes: vertex_size = alignForward(vertex_bytes, 4), index_size = alignForward(index_bytes, 4)
- Compute bases:
    - vertex_base = alignForward(self.vertex_upload_head_bytes, 4)
    - index_base = alignForward(self.index_upload_head_bytes, 4)
- Ensure capacity:
    - Required end = vertex_base + vertex_size / index_base + index_size
    - If current buffer is too small: create a new buffer sized exactly to required end, retire the old buffer, set self.vertex_buffer / self.index_buffer to new
- Upload:
    - writeBufferAligned(vertex_buffer, vertex_base, vertex_bytes_slice)
    - writeBufferAligned(index_buffer, index_base, index_bytes_slice)
- Advance heads:
    - self.vertex_upload_head_bytes = vertex_base + vertex_size
    - self.index_upload_head_bytes = index_base + index_size
- Return bases in GeometryUpload

Update encode() to bind using returned bases:

- pass.setVertexBuffer(0, self.vertex_buffer.?, upload.vertex_base_bytes, wgpu.WGPU_WHOLE_SIZE);
- pass.setIndexBuffer(self.index_buffer.?, .uint16, upload.index_base_bytes, wgpu.WGPU_WHOLE_SIZE);

### 5) Make globals uploads append-only across encodes

Add a new helper that ensures the globals buffer is large enough for required_end_bytes rather than just pass count.

In encode():

- Compute pass_count (existing logic).
- Compute per-encode base:
    - globals_base = alignForward(self.globals_upload_head_bytes, globals_stride)
    - globals_end = globals_base + pass_count * globals_stride
- Ensure buffer capacity for globals_end:
    - If resizing requires new buffer: create new buffer, retire old buffer; create a new bind group for the new buffer and retire the old bind group; update self.globals_buffer and
      self.globals_bind_group
- For each pass:
    - globals_offset = globals_base + pass_index * globals_stride
    - queue.writeBuffer(globals_buffer, globals_offset, &globals_data, @sizeOf(Globals))
    - pass.setBindGroup(0, self.globals_bind_group.?, 1, &[_]u32{@intCast(globals_offset)})
- After encoding all passes:
    - self.globals_upload_head_bytes = globals_end

### 6) Fix MSDF params (currently overwritten at offset 0 across encodes)

This is required for true multi-encode safety because encode() currently calls queue.writeBuffer(msdf_buffer, 0, ...) per MSDF draw.

Adjust MSDF binding to use dynamic offsets and append-only storage:

- Add const msdf_stride: usize = 256;
- In ensureMsdfPipeline:
    - Create msdf_bind_group_layout with .has_dynamic_offset = 1
    - Create msdf_bind_group entry with .size = @sizeOf(MsdfParams) and .offset = 0
- Buffer sizing:
    - Do not fix msdf buffer size at @sizeOf(MsdfParams); ensure it is large enough for msdf_end (below) and replace/retire on growth, same pattern as globals
- In encode() when needs_msdf:
    1. Count MSDF draw commands in self.draw_commands.items into msdf_cmd_count
    2. Compute:
        - msdf_base = alignForward(self.msdf_upload_head_bytes, msdf_stride)
        - msdf_end = msdf_base + msdf_cmd_count * msdf_stride
    3. Ensure msdf buffer capacity for msdf_end (replace + retire buffer/bind group if needed)
    4. During the draw loop, maintain msdf_cmd_index:
        - For each MSDF cmd:
            - msdf_offset = msdf_base + msdf_cmd_index * msdf_stride
            - queue.writeBuffer(msdf_buffer, msdf_offset, &cmd.msdf_params, @sizeOf(MsdfParams))
            - pass.setBindGroup(2, self.msdf_bind_group.?, 1, &[_]u32{@intCast(msdf_offset)})
            - msdf_cmd_index += 1
    5. After encoding:
        - self.msdf_upload_head_bytes = msdf_end

### 7) Keep clearFrameData() call placement

Leave self.clearFrameData() at the end of encode() so Clay can build, encode, build, encode in the same frame.