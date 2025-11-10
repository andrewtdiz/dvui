import { renderApp } from "./solid/host.js";

let tickConnected = false;

function ensureFrameLoop() {
  if (tickConnected) return;
  const tick = globalThis.editor?.Tick;
  if (tick && typeof tick.Connect === "function") {
    tick.Connect((frame) => {
      return frame?.position ?? 0;
    });
  } else {
    globalThis.runFrame = (frame) => frame?.position ?? 0;
  }
  tickConnected = true;
}

export function render(App) {
  if (typeof App !== "function") {
    throw new Error("dvui.render expects a component function");
  }
  ensureFrameLoop();
  renderApp(App, 0);
}
