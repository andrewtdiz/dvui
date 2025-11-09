import { React } from "../runtime/index.js";

export default function Label(props) {
  return React.createElement("label", props, props.children);
}
