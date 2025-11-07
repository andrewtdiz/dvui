(() => {
  if (globalThis.__clayRuntimeBootstrapped) {
    return;
  }

  const listeners = new Map();
  let tickConnected = false;

  const windowBridge = globalThis.window || {};
  windowBridge.addEventListener = function addEventListener(type, listener) {
    let bucket = listeners.get(type);
    if (bucket == null) {
      bucket = new Set();
      listeners.set(type, bucket);
    }
    bucket.add(listener);
  };

  windowBridge.removeEventListener = function removeEventListener(type, listener) {
    const bucket = listeners.get(type);
    if (bucket == null) return;
    bucket.delete(listener);
  };

  globalThis.window = windowBridge;

  globalThis.__dispatchWindowEvent = (type, detail) => {
    detail.type = type;
    const bucket = listeners.get(type);
    if (bucket == null) return;
    for (const listener of bucket) {
      listener(detail);
    }
  };

  if (!globalThis.mouse) {
    globalThis.mouse = { x: 0, y: 0 };
  }

  if (!globalThis.__frame_args) {
    globalThis.__frame_args = { position: 0, dt: 0 };
  }

  if (!globalThis.__mouseEvent) {
    globalThis.__mouseEvent = { type: "", button: "", x: 0, y: 0 };
  }

  if (!globalThis.__keyEvent) {
    globalThis.__keyEvent = { type: "", code: "", repeat: false };
  }

  function connectTick(callback) {
    if (tickConnected) {
      throw new Error("Tick already connected");
    }
    tickConnected = true;
    globalThis.runFrame = callback;
  }

  globalThis.editor = {
    Tick: {
      Connect: connectTick,
    },
  };

  globalThis.__clayRuntimeBootstrapped = true;
})();
