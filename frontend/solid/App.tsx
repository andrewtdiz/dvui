// @ts-nocheck
import { Button, Checkbox } from "./components/index";
import { createSignal } from "solid-js";

export const App = () => {
  const [count, setCount] = createSignal(0);
  return (
    <div>
      <Button variant="default" onClick={() => setCount(count() + 1)}>Count: {count()}</Button>
      <Checkbox />
    </div>
  );
};
