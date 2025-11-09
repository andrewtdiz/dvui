import { React } from "../runtime/index.js";

/**
 * Thin wrapper so downstream code can import <Button /> without
 * caring about the lowercase native tag that the reconciler expects.
 */
export default function Button(props) {
  return React.createElement("button", props, props.children);
}
