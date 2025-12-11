pub const native_dialogs = @import("native_dialogs.zig");
pub const dialogWasmFileOpen = native_dialogs.Wasm.open;
pub const wasmFileUploaded = native_dialogs.Wasm.uploaded;
pub const dialogWasmFileOpenMultiple = native_dialogs.Wasm.openMultiple;
pub const wasmFileUploadedMultiple = native_dialogs.Wasm.uploadedMultiple;
pub const dialogNativeFileOpen = native_dialogs.Native.open;
pub const dialogNativeFileOpenMultiple = native_dialogs.Native.openMultiple;
pub const dialogNativeFileSave = native_dialogs.Native.save;
pub const dialogNativeFolderSelect = native_dialogs.Native.folderSelect;

pub const io_compat = @import("io_compat.zig");
pub const dialogs = @import("dialogs.zig");
