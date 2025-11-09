import { React, render } from "./dvui.js";
import { Button } from "./components/index.js";
const useState = React.useState;
function App() {
  const [count, setCount] = useState(0);
  return /* @__PURE__ */ React.createElement("div", { className: "bg-neutral-800 flex items-center w-full justify-between" }, /* @__PURE__ */ React.createElement(Button, { className: "bg-green-500 text-neutral-100", onClick: () => setCount(count + 1) }, "Increment"), /* @__PURE__ */ React.createElement(Button, { className: "bg-blue-500 text-neutral-100", onClick: () => setCount(count - 1) }, "Decrease"), /* @__PURE__ */ React.createElement(Button, { className: "bg-red-500 text-neutral-100", onClick: () => setCount(0) }, "Reset"), /* @__PURE__ */ React.createElement("p", null, "Count: ", count), count > 4 && /* @__PURE__ */ React.createElement("p", null, "Greater than 4"), count < 0 && /* @__PURE__ */ React.createElement("p", null, "Less than 0"));
}
render(/* @__PURE__ */ React.createElement(App, null));
