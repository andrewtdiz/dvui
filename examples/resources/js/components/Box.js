import { React } from "../runtime/index.js";

export default function Box(props) {
  return React.createElement("box", props, props.children);
}
