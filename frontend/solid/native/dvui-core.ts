import { dlopen, ptr, suffix, CString } from "bun:ffi";
import { existsSync } from "fs";
import { join, resolve } from "path";

const frontendRoot = resolve(import.meta.dir, "..");
const repoRoot = resolve(import.meta.dir, "../..");
const roots = [frontendRoot, repoRoot];

const fallbackNames = ["dvui.dll", "libdvui.so", "libdvui.dylib"];
const defaultLibName = process.platform === "win32" ? `dvui.${suffix}` : `libdvui.${suffix}`;

function findLib(libPath?: string): string {
  if (libPath && existsSync(libPath)) return libPath;
  const candidates: string[] = [];
  for (const root of roots) {
    const binDir = join(root, "zig-out", "bin");
    const libDir = join(root, "zig-out", "lib");
    candidates.push(
      ...fallbackNames.map((n) => join(binDir, n)),
      ...fallbackNames.map((n) => join(libDir, n)),
      join(process.platform === "win32" ? binDir : libDir, defaultLibName),
    );
  }
  const found = candidates.find((p) => existsSync(p));
  if (found) return found;
  return join(repoRoot, "zig-out", process.platform === "win32" ? "bin" : "lib", defaultLibName);
}

const coreSymbols = {
  dvui_core_version: { args: [], returns: "ptr" },
  dvui_core_init: { args: ["ptr"], returns: "ptr" },
  dvui_core_deinit: { args: ["ptr"], returns: "void" },
  dvui_core_begin_frame: { args: ["ptr"], returns: "bool" },
  dvui_core_end_frame: { args: ["ptr"], returns: "bool" },
  dvui_core_pointer: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_wheel: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_key: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_text: { args: ["ptr", "ptr"], returns: "bool" },
  dvui_core_commit: { args: ["ptr", "ptr", "usize", "ptr", "usize", "u32"], returns: "bool" },
} as const;

export type CoreLibrary = ReturnType<typeof loadCoreLibrary>;
export type CoreHandle = { handle: bigint; titleBuf: Uint8Array };

export enum BackendKind {
  raylib = 0,
  wgpu = 1,
}

type InitOptions = {
  backend?: BackendKind;
  width?: number;
  height?: number;
  vsync?: boolean;
  title?: string;
};

export function loadCoreLibrary(libPath?: string) {
  const lib = dlopen(findLib(libPath), coreSymbols);
  return lib;
}

function makeInitBuffer(opts: InitOptions) {
  // Layout matches extern struct InitOptions in core/ffi.zig
  // u8 backend; pad3; f32 width; f32 height; u8 vsync; pad3; pointer title;
  const buf = new ArrayBuffer(24);
  const view = new DataView(buf);
  view.setUint8(0, opts.backend ?? BackendKind.raylib);
  view.setFloat32(4, opts.width ?? 800, true);
  view.setFloat32(8, opts.height ?? 600, true);
  view.setUint8(12, opts.vsync ? 1 : 0);
  return { buf, view };
}

export function initCore(opts: InitOptions = {}, libPath?: string): { handle: CoreHandle; deinit: () => void; version: string } {
  const lib = loadCoreLibrary(libPath);

  const titleBuf = new TextEncoder().encode(`${opts.title ?? "dvui" }\0`);
  const { buf, view } = makeInitBuffer(opts);
  // title pointer at offset 16
  view.setBigUint64(16, BigInt(ptr(titleBuf)), true);

  const handlePtr = lib.symbols.dvui_core_init(ptr(new Uint8Array(buf)));
  if (!handlePtr) {
    throw new Error("dvui_core_init returned null");
  }

  const versionPtr = lib.symbols.dvui_core_version();
  const version = versionPtr ? CString.fromPointer(versionPtr) : "unknown";

  const handle: CoreHandle = { handle: BigInt(handlePtr), titleBuf };

  const deinit = () => {
    lib.symbols.dvui_core_deinit(handle.handle);
  };

  return { handle, deinit, version };
}

// --- Helpers for event structs (C ABI layouts) ------------------------------

function makePointerEvent(x: number, y: number, button: number, action: number) {
  const buf = new ArrayBuffer(12); // f32 x2 + u8 + u8 + pad2
  const view = new DataView(buf);
  view.setFloat32(0, x, true);
  view.setFloat32(4, y, true);
  view.setUint8(8, button);
  view.setUint8(9, action);
  return new Uint8Array(buf);
}

function makeWheelEvent(dx: number, dy: number) {
  const buf = new ArrayBuffer(8); // f32 + f32
  const view = new DataView(buf);
  view.setFloat32(0, dx, true);
  view.setFloat32(4, dy, true);
  return new Uint8Array(buf);
}

function makeKeyEvent(code: number, action: number, mods: number) {
  const buf = new ArrayBuffer(6); // u16 code, u8 action, pad1, u16 mods
  const view = new DataView(buf);
  view.setUint16(0, code, true);
  view.setUint8(2, action);
  view.setUint16(4, mods, true);
  return new Uint8Array(buf);
}

function makeTextEvent(text: Uint8Array) {
  const buf = new ArrayBuffer(16); // pointer + usize
  const view = new DataView(buf);
  view.setBigUint64(0, BigInt(ptr(text)), true);
  view.setBigUint64(8, BigInt(text.byteLength), true);
  return { buf: new Uint8Array(buf), text };
}

export type CoreSession = {
  handle: CoreHandle;
  version: string;
  beginFrame(): boolean;
  endFrame(): boolean;
  pointer(x: number, y: number, button: number, action: number): boolean;
  wheel(dx: number, dy: number): boolean;
  key(code: number, action: number, mods: number): boolean;
  text(utf8: Uint8Array): boolean;
  commit(headers: Uint8Array, payload: Uint8Array, count: number): boolean;
  deinit(): void;
};

export function createCoreSession(opts: InitOptions = {}, libPath?: string): CoreSession {
  const lib = loadCoreLibrary(libPath);
  const { handle, deinit, version } = initCore(opts, libPath);

  return {
    handle,
    version,
    beginFrame() {
      return lib.symbols.dvui_core_begin_frame(handle.handle);
    },
    endFrame() {
      return lib.symbols.dvui_core_end_frame(handle.handle);
    },
    pointer(x, y, button, action) {
      const evt = makePointerEvent(x, y, button, action);
      return lib.symbols.dvui_core_pointer(handle.handle, ptr(evt));
    },
    wheel(dx, dy) {
      const evt = makeWheelEvent(dx, dy);
      return lib.symbols.dvui_core_wheel(handle.handle, ptr(evt));
    },
    key(code, action, mods) {
      const evt = makeKeyEvent(code, action, mods);
      return lib.symbols.dvui_core_key(handle.handle, ptr(evt));
    },
    text(utf8) {
      const evt = makeTextEvent(utf8);
      return lib.symbols.dvui_core_text(handle.handle, ptr(evt.buf));
    },
    commit(headers, payload, count) {
      const hptr = headers.byteLength > 0 ? ptr(headers) : 0n;
      const pptr = payload.byteLength > 0 ? ptr(payload) : 0n;
      return lib.symbols.dvui_core_commit(handle.handle, hptr, headers.byteLength, pptr, payload.byteLength, count >>> 0);
    },
    deinit,
  };
}

