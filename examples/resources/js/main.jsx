import { React, render } from "./dvui.js";
import { Button, Image } from "./components/index.js";

const useState = React.useState;

function App() {
  const [count, setCount] = useState(0);

  return (
    <div className="bg-neutral-800 flex items-center w-full justify-between">
      {/* <h1>DVUI React Bridge</h1>
      <h2>Heading level 2</h2>
      <h3>Heading level 3</h3> */}
      <Button className="bg-green-500 text-neutral-100" onClick={() => setCount(count + 1)}>Increment</Button>
      <Button className="bg-blue-500 text-neutral-100" onClick={() => setCount(count - 1)}>Decrease</Button>
      <Button className="bg-red-500 text-neutral-100" onClick={() => setCount(0)}>Reset</Button>
      <p>Count: {count}</p>
      <p>Here is the Zig favicon:</p>
      {/* <Image src="zig-favicon.png" /> */}
      {count > 4 && <p>Greater than 4</p>}
      {count < 0 && <p>Less than 0</p>}
    </div>
  );
}

render(<App />);
