import type { HostNode } from "./node";
import { extractTransform, extractVisual } from "./props";

export type SerializedNode = {
  id: number;
  tag: string;
  parent?: number;
  text?: string;
  className?: string;
  rotation?: number;
  scaleX?: number;
  scaleY?: number;
  anchorX?: number;
  anchorY?: number;
  translateX?: number;
  translateY?: number;
  opacity?: number;
  cornerRadius?: number;
  background?: number;
  textColor?: number;
  clipChildren?: boolean;
};

export const serializeTree = (roots: HostNode[]): SerializedNode[] => {
  const nodes: SerializedNode[] = [];
  const serialize = (node: HostNode, parentId: number) => {
    const className = node.props.className ?? node.props.class;
    const entry: SerializedNode = {
      id: node.id,
      tag: node.tag,
      parent: parentId,
    };
    if (className) entry.className = className;
    if (node.tag === "text") {
      entry.text = node.props.text ?? "";
    }
    Object.assign(entry, extractTransform(node.props), extractVisual(node.props));
    nodes.push(entry);
    for (const child of node.children) {
      serialize(child, node.id);
    }
  };

  for (const child of roots) {
    serialize(child, 0);
  }
  return nodes;
};
