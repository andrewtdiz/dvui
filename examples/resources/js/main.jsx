import { React, createRoot, render } from "./runtime/index.js";
import { Button, Label } from "./components/index.js";
import EventManager from "./runtime/eventManager.js";
import { serializeContainer } from "./runtime/serializer.js";
import { installListenerBridge } from "./bridge/events.js";
import { ensureNativeAppState, publishRenderSnapshot } from "./bridge/native.js";

const useState = React.useState;
const eventManager = new EventManager();

ensureNativeAppState();

let renderInFlight = false;
let rerenderQueued = false;

const root = createRoot();

installListenerBridge(eventManager, () => {
  queueMicrotask(() => {
    syncRenderTree();
  });
});

function App() {
  const [count, setCount] = useState(0);

  return (
    <>
      <Button className="" onClick={() => setCount(count + 1)}>
        Button Count: {count}
      </Button>
      <Label className="">hey it's me!</Label>
      {count > 4 && <Label>Greater than 4</Label>}
    </>
  );
}

async function syncRenderTree() {
  if (renderInFlight) {
    rerenderQueued = true;
    return;
  }

  renderInFlight = true;

  try {
    eventManager.reset();
    const container = await render(<App />, root);
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
      queueMicrotask(() => {
        syncRenderTree();
      });
    }
  }
}

editor.Tick.Connect(({ position }) => {
  return position;
});

syncRenderTree();
