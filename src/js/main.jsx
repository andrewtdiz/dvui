import { createSignal } from "solid-js";
import { render, registerSignal } from "./dvui.js";
import { Button, Image } from "./components/index.js";

const [count, setCount] = createSignal(0);
const [message, setMessage] = createSignal("Hello from Solid!");
registerSignal("zig:count", { get: count, set: setCount });
registerSignal("zig:message", { get: message, set: setMessage });

export default function App() {
  const increment = () => setCount(count() + 1);
  const decrement = () => setCount(count() - 1);
  const reset = () => setCount(0);
  const handleInput = (event) => {
    setMessage(event.currentTarget.value);
  };
  const inputValue = createSignal("");
  const setInputValue = (value) => {
    inputValue(value);
  };
  return (
    <div className="bg-neutral-800 flex flex-col items-start">
      
      <h1>DVUI SolidJS Bridge</h1>
      <h2>Heading level 2</h2>
      <h3>Heading level 3</h3>

      <input
        className="px-3 py-2 rounded bg-transparent border border-neutral-400 text-neutral-100"
        value={inputValue()}
        onInput={setInputValue}
        placeholder="Type a message"
      />
     
      <Button className="bg-green-500 text-neutral-100" onClick={increment}>
        Increment
      </Button>
      <Button className="bg-blue-500 text-neutral-100" onClick={decrement}>
        Decrease
      </Button>
      <Button className="bg-red-500 px-6 text-neutral-100" onClick={reset}>
        Reset
      </Button>
      <p>Count: {count()}</p>
      <p>Message from Zig: {message()}</p>
      <div className="flex p-0 bg-red-500 justify-start items-center gap-2">
        <p>Here is the Zig favicon:</p>
        <Image src="zig-favicon.png" />
        <Image src="zig-favicon.png" />
        <Image src="zig-favicon.png" />
        <Image src="zig-favicon.png" />
      </div>
      {count() > 4 && <p>Greater than 4</p>}
      {count() < 0 && <p>Less than 0</p>}
    </div>
  );
}

render(App);
