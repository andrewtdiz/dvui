import type { HostNode } from "./node";
import {
  extractAccessibility,
  extractAnchor,
  extractFocus,
  extractIcon,
  extractScroll,
  extractTransform,
  extractVisual,
} from "./props";

export type SerializedNode = {
  id: number;
  tag: string;
  parent?: number;
  text?: string;
  value?: string;
  src?: string;
  iconKind?: string;
  iconGlyph?: string;
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
  scroll?: boolean;
  scrollX?: number;
  scrollY?: number;
  canvasWidth?: number;
  canvasHeight?: number;
  autoCanvas?: boolean;
  tabIndex?: number;
  focusTrap?: boolean;
  roving?: boolean;
  modal?: boolean;
  anchorId?: number;
  anchorSide?: string;
  anchorAlign?: string;
  anchorOffset?: number;
  role?: string;
  ariaLabel?: string;
  ariaDescription?: string;
  ariaExpanded?: boolean;
  ariaSelected?: boolean;
  ariaChecked?: string;
  ariaPressed?: string;
  ariaHidden?: boolean;
  ariaDisabled?: boolean;
  ariaHasPopup?: string;
  ariaModal?: boolean;
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
    if (node.props.value != null) entry.value = String(node.props.value);
    if (node.props.src != null) entry.src = String(node.props.src);
    Object.assign(
      entry,
      extractTransform(node.props),
      extractVisual(node.props),
      extractScroll(node.props),
      extractFocus(node.props),
      extractAnchor(node.props),
      extractIcon(node.props),
      extractAccessibility(node.props)
    );
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
