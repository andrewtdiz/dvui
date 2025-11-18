import { createSignal } from "solid-js";
import { render, registerSignal } from "./dvui.js";
import { Button, Image } from "./components/index.js";

const [count, setCount] = createSignal(0);
const [message, setMessage] = createSignal("Hello from Solid!");
const [mousePosition, setMousePosition] = createSignal({ x: 0, y: 0 });
registerSignal("zig:count", { get: count, set: setCount });
registerSignal("zig:message", { get: message, set: setMessage });
registerSignal("zig:mousePosition", {
  get: mousePosition,
  set: (value) => {
    try {
      if (typeof value === "string") {
        const parsed = JSON.parse(value);
        if (typeof parsed?.x === "number" && typeof parsed?.y === "number") {
          setMousePosition({ x: parsed.x, y: parsed.y });
          return;
        }
      } else if (value && typeof value === "object") {
        const nextX = typeof value.x === "number" ? value.x : 0;
        const nextY = typeof value.y === "number" ? value.y : 0;
        setMousePosition({ x: nextX, y: nextY });
        return;
      }
    } catch (error) {
      console.error("Failed to parse zig:mousePosition payload", error);
    }
  },
});

export default function App() {
  const increment = () => setCount(count() + 1);
  const decrement = () => setCount(count() - 1);
  const reset = () => setCount(0);
  const handleInput = (event) => {
    setMessage(event.currentTarget.value);
  };
  const [inputValue, setInputValue] = createSignal("");

  const trackerWidth = 320;
  const trackerHeight = 200;
  const followerSize = 32;

  const trackerStyle = {
    width: `${trackerWidth}`,
    height: `${trackerHeight}`,
  };

  const followerStyle = () => {
    const position = mousePosition();
    const halfSize = followerSize / 2;
    const clampedX = Math.max(Math.min(position.x - halfSize, trackerWidth - followerSize), 0);
    const clampedY = Math.max(Math.min(position.y - halfSize, trackerHeight - followerSize), 0);
    return {
      width: `${followerSize}`,
      height: `${followerSize}`,
      "margin-left": `${clampedX}`,
      "margin-top": `${clampedY}`,
      background: "#22d3ee",
      "border-radius": "6",
    };
  };

  return (
    // <div className="draggable absolute top-0 left-0 bg-neutral-800 flex flex-col items-start">
      
    //   <h1>DVUI SolidJS Bridge</h1>
    //   <h2>Heading level 2</h2>
    //   <h3>Heading level 3</h3>

    //   <input
    //     className="px-3 py-2 rounded bg-transparent border border-neutral-400 text-neutral-100"
    //     value={inputValue()}
    //     onInput={setInputValue}
    //     placeholder="Type a message"
    //   />
     
    //   <Button className="bg-green-500 text-neutral-100" onClick={increment}>
    //     Increment
    //   </Button>
    //   <Button className="bg-blue-500 text-neutral-100" onClick={decrement}>
    //     Decrease
    //   </Button>
    //   <Button className="bg-red-500 px-6 text-neutral-100" onClick={reset}>
    //     Reset
    //   </Button>
    //   <p>Count: {count()}</p>
    //   <p>Message from Zig: {message()}</p>
    //   <div className="flex p-0 bg-red-500 justify-start items-center gap-2">
    //     <p>Here is the Zig favicon:</p>
    //     <Image src="zig-favicon.png" />
    //   </div>
    //   {count() > 4 && <p>Greater than 4</p>}
    //   {count() < 0 && <p>Less than 0</p>}

    // </div>

    <div className="mt-6 w-full">
    <p className="text-neutral-300">
      Mouse position: {mousePosition().x}, {mousePosition().y}
    </p>
    <p className="text-neutral-400 text-sm mb-2">Move the cursor to stress reactive updates.</p>
  </div>
  );
}

render(App);
