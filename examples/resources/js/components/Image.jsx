import { React } from "../runtime/index.js";

export default function Image(props) {
  return React.createElement("image", props, props.children);
}
