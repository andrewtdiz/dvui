import { render } from "solid-js/web";
import "./bridge.js";
import App from "./App.jsx";

function attachRootDiagnostics(root) {
  if (window.__dvuiDiagnosticsInstalled) return;
  const observedEvents = ["click", "mousedown", "mouseup", "keydown", "keyup", "wheel"];
  const log = (event) => {
    if (event.isTrusted) return;
    const source = event.target?.id || event.target?.nodeName || "unknown";
    console.debug(`[dvui] synthetic ${event.type} via DVUI bridge from ${source}`);
  };
  observedEvents.forEach((type) => root.addEventListener(type, log));
  root.addEventListener("click", (event) => {
    const source = event.target?.id || event.target?.nodeName || "unknown";
    console.log(`Root clicked: ${source}`);
  });
  window.__dvuiDiagnosticsInstalled = true;
}

function mount() {
  const root = document.getElementById("root");
  if (!root) {
    throw new Error("Unable to find #root element for DVUI.");
  }
  attachRootDiagnostics(root);
  render(() => <App />, root);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mount, { once: true });
} else {
  mount();
}
