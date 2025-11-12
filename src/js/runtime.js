(() => {
  if (globalThis.__clayRuntimeBootstrapped) {
    return;
  }

  const resolvedPromise = typeof Promise === "function" ? Promise.resolve() : null;

  function scheduleJob(callback) {
    if (typeof callback !== "function") return;
    if (!resolvedPromise) {
      callback();
      return;
    }
    resolvedPromise.then(callback).catch((error) => {
      resolvedPromise.then(() => {
        throw error;
      });
    });
  }

  const timerJobs = new Map();
  let nextTimerId = 1;

  function startTimer(id) {
    scheduleJob(() => {
      const job = timerJobs.get(id);
      if (!job) return;
      try {
        job.callback(...job.args);
      } catch (error) {
        if (resolvedPromise) {
          resolvedPromise.then(() => {
            throw error;
          });
        } else {
          throw error;
        }
      }
      if (job.repeat && timerJobs.has(id)) {
        startTimer(id);
      } else {
        timerJobs.delete(id);
      }
    });
  }

  if (typeof globalThis.setTimeout !== "function") {
    globalThis.setTimeout = function timeoutPolyfill(callback, _delay, ...args) {
      if (typeof callback !== "function") {
        return 0;
      }
      const id = nextTimerId++;
      timerJobs.set(id, { callback, args, repeat: false });
      startTimer(id);
      return id;
    };
  }

  if (typeof globalThis.clearTimeout !== "function") {
    globalThis.clearTimeout = function clearTimeoutPolyfill(id) {
      timerJobs.delete(id);
    };
  }

  if (typeof globalThis.setInterval !== "function") {
    globalThis.setInterval = function intervalPolyfill(callback, _delay, ...args) {
      if (typeof callback !== "function") {
        return 0;
      }
      const id = nextTimerId++;
      timerJobs.set(id, { callback, args, repeat: true });
      startTimer(id);
      return id;
    };
  }

  if (typeof globalThis.clearInterval !== "function") {
    globalThis.clearInterval = function clearIntervalPolyfill(id) {
      timerJobs.delete(id);
    };
  }

  if (typeof globalThis.setImmediate !== "function") {
    globalThis.setImmediate = function immediateFallback(callback, ...args) {
      return globalThis.setTimeout(callback, 0, ...args);
    };
  }

  if (typeof globalThis.clearImmediate !== "function") {
    globalThis.clearImmediate = globalThis.clearTimeout;
  }

  if (typeof globalThis.queueMicrotask !== "function") {
    globalThis.queueMicrotask = function queueMicrotaskFallback(callback) {
      if (typeof callback !== "function") {
        throw new TypeError("queueMicrotask callback must be a function");
      }
      scheduleJob(callback);
    };
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
