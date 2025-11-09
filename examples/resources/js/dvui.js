import { React, createRoot, render as reconcilerRender } from "./runtime/index.js";
import EventManager from "./runtime/eventManager.js";
import { serializeContainer } from "./runtime/serializer.js";
import { installListenerBridge } from "./bridge/events.js";
import { ensureNativeAppState, publishRenderSnapshot } from "./bridge/native.js";

const eventManager = new EventManager();
const root = createRoot();
let renderInFlight = false;
let rerenderQueued = false;
let componentFactory = null;

ensureNativeAppState();

installListenerBridge(eventManager, () => {
  queueMicrotask(syncRenderTree);
});

editor.Tick.Connect(({ position }) => position);

function createComponent() {
  if (!componentFactory) return null;
  try {
    return componentFactory();
  } catch (error) {
    console.error("Failed to create root component:", error);
    throw error;
  }
}

async function syncRenderTree() {
  if (!componentFactory) return;

  if (renderInFlight) {
    rerenderQueued = true;
    return;
  }

  renderInFlight = true;

  try {
    eventManager.reset();
    const component = createComponent();
    if (!component) {
      throw new Error("No component available to render");
    }
    const container = await reconcilerRender(component, root);
    const snapshot = serializeContainer(container, { eventManager });
    publishRenderSnapshot(snapshot);
  } catch (error) {
    console.error("Failed to render React bridge:", error);
    if (error && typeof error === "object") {
      if ("message" in error) console.error("Message:", error.message);
      if ("stack" in error) console.error("Stack:", error.stack);
    }
  } finally {
    renderInFlight = false;
    if (rerenderQueued) {
      rerenderQueued = false;
      queueMicrotask(syncRenderTree);
    }
  }
}

export function render(component) {
  componentFactory = buildComponentFactory(component);
  (async () => {
    await syncRenderTree();
  })();
}

function buildComponentFactory(component) {
  if (typeof component === "function") {
    // Allow passing component constructors directly.
    return () => React.createElement(component);
  }

  if (React && typeof React.isValidElement === "function" && React.isValidElement(component)) {
    return () => React.cloneElement(component);
  }

  // Fallback for already-created nodes or primitives.
  return () => component;
}

export { React };
