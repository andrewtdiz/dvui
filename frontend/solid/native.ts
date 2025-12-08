import { existsSync } from "fs";
import { dlopen, JSCallback, suffix, toArrayBuffer, type Pointer } from "bun:ffi";
import { join, resolve } from "path";

const defaultLibName =
  process.platform === "win32" ? `native_renderer.${suffix}` : process.platform === "darwin" ? `libnative_renderer.${suffix}` : `libnative_renderer.${suffix}`;

const frontendRoot = resolve(import.meta.dir, "..");
const repoRoot = resolve(import.meta.dir, "../..");
const roots = [frontendRoot, repoRoot];

const fallbackNames = ["native_renderer.dll", "libnative_renderer.so", "libnative_renderer.dylib"];
const candidateLibs: string[] = [];

for (const root of roots) {
  const binDir = join(root, "zig-out", "bin");
  const libDir = join(root, "zig-out", "lib");
  candidateLibs.push(
    ...fallbackNames.map((name) => join(binDir, name)),
    ...fallbackNames.map((name) => join(libDir, name)),
    join(process.platform === "win32" ? binDir : libDir, defaultLibName),
  );
}

const defaultLibPath = candidateLibs.find((p) => existsSync(p)) ?? join(repoRoot, "zig-out", process.platform === "win32" ? "bin" : "lib", defaultLibName);

const binDirs = Array.from(new Set(roots.map((root) => join(root, "zig-out", "bin"))));

const nativeSymbols = {
  createRenderer: {
    args: ["ptr", "ptr"],
    returns: "ptr",
  },
  destroyRenderer: {
    args: ["ptr"],
    returns: "void",
  },
  resizeRenderer: {
    args: ["ptr", "u32", "u32"],
    returns: "void",
  },
  commitCommands: {
    args: ["ptr", "ptr", "usize", "ptr", "usize", "u32"],
    returns: "void",
  },
  presentRenderer: {
    args: ["ptr"],
    returns: "void",
  },
  setRendererText: {
    args: ["ptr", "ptr", "usize"],
    returns: "void",
  },
} as const;

export type NativeLibrary = ReturnType<typeof loadNativeLibrary>;

export type NativeCallbacks = {
  onEvent?: (name: string, payload: Uint8Array) => void;
  onLog?: (level: number, message: string) => void;
};

export type CallbackBundle = {
  log: JSCallback;
  event: JSCallback;
  setEventHandler: (handler?: NativeCallbacks["onEvent"]) => void;
  setLogHandler: (handler?: NativeCallbacks["onLog"]) => void;
};

export const loadNativeLibrary = (libPath: string = defaultLibPath): NativeLibrary => {
  if (process.platform === "win32") {
    const currentPath = process.env.PATH ?? "";
    const entries = currentPath.split(";");
    const additions = binDirs.filter((dir) => existsSync(dir) && !entries.includes(dir));
    if (additions.length > 0) {
      process.env.PATH = `${additions.join(";")};${currentPath}`;
    }
  }
  return dlopen(libPath, nativeSymbols);
};

export const createCallbackBundle = (callbacks: NativeCallbacks = {}): CallbackBundle => {
  const decoder = new TextDecoder();
  let onEvent = callbacks.onEvent;
  let onLog = callbacks.onLog;

  const logCallback = new JSCallback(
    (level: number, msgPtr: Pointer, msgLenRaw: number | bigint) => {
      if (!onLog || !msgPtr) return;
      const msgLen = typeof msgLenRaw === "bigint" ? Number(msgLenRaw) : msgLenRaw;
      if (msgLen === 0) return;

      const messageBuffer = new Uint8Array(toArrayBuffer(msgPtr, 0, msgLen));
      const message = decoder.decode(messageBuffer);
      onLog(level, message);
    },
    {
      args: ["u8", "ptr", "usize"],
      returns: "void",
    },
  );

  const eventCallback = new JSCallback(
    (namePtr: Pointer, nameLenRaw: number | bigint, dataPtr: Pointer, dataLenRaw: number | bigint) => {
      if (!onEvent || !namePtr) return;
      const nameLen = typeof nameLenRaw === "bigint" ? Number(nameLenRaw) : nameLenRaw;
      const dataLen = typeof dataLenRaw === "bigint" ? Number(dataLenRaw) : dataLenRaw;
      if (nameLen === 0) return;

      const nameBytes = new Uint8Array(toArrayBuffer(namePtr, 0, nameLen));
      const eventName = decoder.decode(nameBytes);

      if (dataLen === 0 || !dataPtr) {
        onEvent(eventName, new Uint8Array(0));
        return;
      }

      const payload = new Uint8Array(toArrayBuffer(dataPtr, 0, dataLen)).slice();
      onEvent(eventName, payload);
    },
    {
      args: ["ptr", "usize", "ptr", "usize"],
      returns: "void",
    },
  );

  return {
    log: logCallback,
    event: eventCallback,
    setEventHandler(handler) {
      onEvent = handler;
    },
    setLogHandler(handler) {
      onLog = handler;
    },
  };
};
