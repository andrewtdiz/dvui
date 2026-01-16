import { NativeRenderer } from "./solid";
import { createSolidTextApp } from "./solid/solid-entry";
import { createFrameScheduler } from "./solid/util/frame-scheduler";
import { setTime } from "./solid/state/time";

const screenWidth = 800;
const screenHeight = 450;

type WindowResizePayload = {
  width: number;
  height: number;
  pixelWidth: number;
  pixelHeight: number;
};

const parseWindowResize = (payload: Uint8Array): WindowResizePayload | null => {
  if (payload.byteLength < 16) return null;
  const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const width = view.getUint32(0, true);
  const height = view.getUint32(4, true);
  const pixelWidth = view.getUint32(8, true);
  const pixelHeight = view.getUint32(12, true);
  return { width, height, pixelWidth, pixelHeight };
};

let logicalSize = { width: screenWidth, height: screenHeight };
let pixelSize = { width: 0, height: 0 };
let deviceScale = 1;
let pendingResize: WindowResizePayload | null = null;
let resizeRequested: { width: number; height: number } | null = null;

const computeDeviceScale = (payload: WindowResizePayload) => {
  if (payload.width <= 0 || payload.height <= 0) return deviceScale;
  const scaleX = payload.pixelWidth / payload.width;
  const scaleY = payload.pixelHeight / payload.height;
  const scale = Math.max(scaleX, scaleY);
  return Number.isFinite(scale) && scale > 0 ? scale : deviceScale;
};


const requestResize = (width: number, height: number) => {
  resizeRequested = { width, height };
  logicalSize = { width, height };
  renderer.resize(width, height);
};



const renderer = new NativeRenderer({
  callbacks: {
    onLog(level, message) {
      console.log(`[native:${level}] ${message}`);
    },

    onEvent(name, payload) {
      if (name === "window_closed") {
        renderer.markNativeClosed();
        requestShutdown(false);
        return;
      }
      if (name === "window_resize") {
        const parsed = parseWindowResize(payload);
        if (!parsed) return;
        pendingResize = parsed;
      }
    },

  },
});

requestResize(screenWidth, screenHeight);


const { host, setMessage, dispose } = createSolidTextApp(renderer);
const scheduler = createFrameScheduler();

let running = true;
let frame = 0;
let startTime = performance.now();
let lastTime = startTime;
let pendingShutdown: { closeRenderer: boolean } | null = null;

const requestShutdown = (closeRenderer: boolean) => {
  if (!running || pendingShutdown) return;
  pendingShutdown = { closeRenderer };
};

const shutdown = ({ closeRenderer = true }: { closeRenderer?: boolean } = {}) => {
  if (!running) return;
  running = false;
  scheduler.stop();
  dispose();
  if (closeRenderer) {
    renderer.close();
  }
};

const drainPendingShutdown = () => {
  if (!pendingShutdown) return false;
  const { closeRenderer } = pendingShutdown;
  pendingShutdown = null;
  shutdown({ closeRenderer });
  return true;
};


process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
process.once("exit", shutdown);

if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    shutdown();
  });
}

const loop = () => {
  if (!running) return false;
  if (drainPendingShutdown()) return false;

  const now = performance.now();

  const dt = (now - lastTime) / 1000;
  const elapsed = (now - startTime) / 1000;
  lastTime = now;

  setTime(elapsed, dt);
  setMessage(`dvui text @ ${elapsed.toFixed(2)}s (frame ${frame})`);

  host.flush();
  renderer.present();
  if (drainPendingShutdown()) return false;

  if (pendingResize) {
    const next = pendingResize;
    pendingResize = null;

    if (
      resizeRequested &&
      resizeRequested.width === next.width &&
      resizeRequested.height === next.height
    ) {
      resizeRequested = null;
    }

    const logicalChanged =
      next.width !== logicalSize.width || next.height !== logicalSize.height;
    const pixelChanged =
      next.pixelWidth !== pixelSize.width || next.pixelHeight !== pixelSize.height;
    if (logicalChanged || pixelChanged) {
      logicalSize = { width: next.width, height: next.height };
      pixelSize = { width: next.pixelWidth, height: next.pixelHeight };
      deviceScale = computeDeviceScale(next);
      // Native window already resized; avoid feedback that can reset HiDPI scaling.
    }
  }

  // Poll event ring buffer and dispatch to Solid handlers
  const nodeIndex = host.getNodeIndex?.() ?? new Map();
  renderer.pollEvents(nodeIndex);

  frame += 1;
  return true;
};

scheduler.start(loop);
