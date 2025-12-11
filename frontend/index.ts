import { NativeRenderer } from "./solid/native-renderer";
import { createSolidTextApp } from "./solid/solid-entry";
import { createFrameScheduler } from "./solid/frame-scheduler";
import { setTime } from "./solid/state/time";

const screenWidth = 800;
const screenHeight = 450;

const renderer = new NativeRenderer({
  callbacks: {
    onLog(level, message) {
      console.log(`[native:${level}] ${message}`);
    },
    onEvent(name) {
      if (name === "window_closed") {
        shutdown();
      }
    },
  },
});

renderer.resize(screenWidth, screenHeight);

const { host, setMessage, dispose } = createSolidTextApp(renderer);
const scheduler = createFrameScheduler();

let running = true;
let frame = 0;
let startTime = performance.now();
let lastTime = startTime;

const shutdown = () => {
  if (!running) return;
  running = false;
  scheduler.stop();
  dispose();
  renderer.close();
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

  const now = performance.now();
  const dt = (now - lastTime) / 1000;
  const elapsed = (now - startTime) / 1000;
  lastTime = now;

  setTime(elapsed, dt);
  setMessage(`dvui text @ ${elapsed.toFixed(2)}s (frame ${frame})`);

  host.flush();
  renderer.present();

  // One-time log of render-time class names to verify active bundle.
  if (frame === 0) {
    const rootChild = host.root.children[0];
    if (rootChild) {
      const cls = rootChild.props.className ?? rootChild.props.class;
      console.log("[frontend debug] root child className=", cls);
      const nested = rootChild.children[0];
      if (nested) {
        const nestedCls = nested.props.className ?? nested.props.class;
        console.log("[frontend debug] nested className=", nestedCls);
      }
    }
  }
  
  // Poll event ring buffer and dispatch to Solid handlers
  const nodeIndex = host.getNodeIndex?.() ?? new Map();
  renderer.pollEvents(nodeIndex);

  frame += 1;
  return true;
};

scheduler.start(loop);
