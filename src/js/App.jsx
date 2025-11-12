import { createSignal, For, Show } from "solid-js";

export default function App() {
  const [status, setStatus] = createSignal("Hybrid runtime ready");
  const [bubbleLog, setBubbleLog] = createSignal([]);

  const handleClick = () => {
    setStatus("Dispatching action to Zig backend…");
    window.dvui?.native?.performAction("toggle-devtools", { timestamp: Date.now() });
    setTimeout(() => setStatus("Action dispatched"), 120);
  };

  const appendBubbleLog = (source, event) => {
    const entryId =
      globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    setBubbleLog((prev) => {
      const next = [...prev, { id: entryId, source, type: event.type }];
      return next.slice(-6);
    });
  };

  const handleBubbleContainer = (event) => {
    appendBubbleLog("container", event);
  };

  const handleBubbleTarget = (event) => {
    appendBubbleLog("button", event);
  };

  return (
    <main class="dvui-shell">
      <header class="dvui-shell__header">
        <h1>DVUI Webview Shell</h1>
        <p>{status()}</p>
      </header>

      <section class="dvui-shell__content">
        <p>
          The SolidJS application now renders inside standard HTML/CSS. Native events from the Zig runtime are
          re-injected as DOM events, enabling a much simpler component model.
        </p>
        <button type="button" onClick={handleClick}>
          Ping Zig Native Host
        </button>

        <div
          class="dvui-shell__bubble-demo"
          onClick={handleBubbleContainer}
          role="group"
          aria-label="Event bubbling demo"
        >
          <p>
            Click the nested button to see how events bubble through the DOM. Native mouse events forwarded from
            Zig travel the same path.
          </p>
          <button id="bubble-target" type="button" onClick={handleBubbleTarget}>
            Bubble Target
          </button>
          <ul class="dvui-shell__bubble-log">
            <For each={bubbleLog()}>
              {(entry) => (
                <li>
                  <code>{entry.type}</code> seen by <strong>{entry.source}</strong>
                </li>
              )}
            </For>
            <Show when={bubbleLog().length === 0}>
              <li>Interact to populate the log.</li>
            </Show>
          </ul>
        </div>
      </section>
    </main>
  );
}
