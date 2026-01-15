/** @jsxImportSource solid-js */
import { createRenderer } from "solid-js/universal";
import { registerRuntimeBridge } from "../runtime/bridge";
import type { RendererAdapter } from "../native/adapter";
import { CommandEncoder } from "../native/encoder";
import {
  applyAccessibilityMutation,
  applyAnchorMutation,
  applyFocusMutation,
  applyScrollMutation,
  applyTransformMutation,
  applyVisualMutation,
  createFlushController,
  isAccessibilityField,
  isAnchorField,
  isFocusField,
  isScrollField,
  isTransformField,
  isVisualField,
} from "./flush";
import { HostNode, type EventHandler } from "./node";
import { createMutationQueue, type MutationOp } from "./mutation-queue";
import {
  clipChildrenFromClass,
  extractAccessibility,
  extractAnchor,
  extractFocus,
  extractScroll,
  extractTransform,
  extractVisual,
  normalizeAriaName,
} from "./props";

const removeFromIndex = (node: HostNode, index: Map<number, HostNode>) => {
  index.delete(node.id);
  for (const child of node.children) {
    removeFromIndex(child, index);
  }
};

const nodeClass = (node: HostNode) => node.props.className ?? node.props.class;

const normalizeTag = (tagName: string) => {
  if (tagName === "img") return "image";
  return tagName;
};

export const createSolidHost = (native: RendererAdapter) => {
  const encoder: CommandEncoder = native.encoder;
  const root = new HostNode("root");
  const nodeIndex = new Map<number, HostNode>([[root.id, root]]);
  const { ops, push } = createMutationQueue();
  const flushController = createFlushController({
    native,
    encoder,
    root,
    nodeIndex,
    ops,
  });

  const enqueueCreateOrMove = (parent: HostNode, node: HostNode, anchor?: HostNode) => {
    const parentId = parent === root ? 0 : parent.id;
    const beforeId = anchor ? anchor.id : undefined;
    if (!node.created) {
      node.created = true;
      const createOp: MutationOp = {
        op: "create",
        id: node.id,
        parent: parentId,
        before: beforeId,
        tag: node.tag,
      };
      if (node.tag === "text") createOp.text = node.props.text ?? "";
      const cls = nodeClass(node);
      if (cls) createOp.className = cls;
      if (node.props.src != null) createOp.src = String(node.props.src);
      if (node.props.value != null) createOp.value = String(node.props.value);
      Object.assign(
        createOp,
        extractTransform(node.props),
        extractVisual(node.props),
        extractScroll(node.props),
        extractFocus(node.props),
        extractAnchor(node.props),
        extractAccessibility(node.props)
      );
      push(createOp);

      return;
    }
    push({
      op: "move",
      id: node.id,
      parent: parentId,
      before: beforeId,
    });
  };

  const enqueueText = (node: HostNode) => {
    if (node.tag !== "text") return;
    push({
      op: "set_text",
      id: node.id,
      text: node.props.text ?? "",
    });
  };

  const registerNode = (node: HostNode) => {
    nodeIndex.set(node.id, node);
    return node;
  };

  const runtimeOps = {
    createElement(tagName: string) {
      return registerNode(new HostNode(normalizeTag(tagName)));
    },
    createTextNode(value: string | number) {
      const node = registerNode(new HostNode("text"));
      node.props.text = typeof value === "number" ? `${value}` : value;
      return node;
    },
    createSlotNode() {
      return registerNode(new HostNode("slot"));
    },
    replaceText(node: HostNode, value: string) {
      if (node.tag !== "text") return;
      node.props.text = value;
      if (node.created) {
        enqueueText(node);
      }
      flushController.scheduleFlush();
    },
    insertNode(parent: HostNode, node: HostNode, anchor?: HostNode) {
      const targetIndex = anchor ? parent.children.indexOf(anchor) : parent.children.length;
      parent.add(node, targetIndex === -1 ? parent.children.length : targetIndex);
      enqueueCreateOrMove(parent, node, anchor);
      flushController.scheduleFlush();
      return node;
    },
    removeNode(parent: HostNode, node: HostNode) {
      parent.remove(node);
      removeFromIndex(node, nodeIndex);
      node.created = false;
      push({ op: "remove", id: node.id });
      flushController.scheduleFlush();
    },
    setProperty(node: HostNode, name: string, value: unknown, prev?: unknown) {
      let eventName: string | null = null;
      if (name.startsWith("on:")) {
        eventName = name.slice(3);
      } else if (name.startsWith("prop:on") || name.startsWith("prop:On")) {
        const afterPropOn = name.slice(7);
        eventName = afterPropOn.charAt(0).toLowerCase() + afterPropOn.slice(1);
      } else if (name.startsWith("on") && name.length > 2 && name[2] === name[2].toUpperCase()) {
        const rest = name.slice(2);
        eventName = rest.charAt(0).toLowerCase() + rest.slice(1);
      }

      if (eventName) {
        const normalized = eventName.toLowerCase();
        if (typeof prev === "function") node.off(normalized, prev as unknown as EventHandler);
        if (typeof value === "function") node.on(normalized, value as unknown as EventHandler);
        flushController.scheduleFlush();
        return;
      }

      const propName = normalizeAriaName(name);
      node.props[propName] = value;
      if (propName === "class" || propName === "className") {
        const cls = value == null ? "" : String(value);
        if (node.created) {
          push({ op: "set_class", id: node.id, className: cls });
        }
        const nextClip = clipChildrenFromClass(node.props);
        if (nextClip || node.props.clipChildren != null) {
          if (node.props.clipChildren !== nextClip) {
            node.props.clipChildren = nextClip;
            if (node.created) {
              applyVisualMutation(node, "clipChildren", nextClip, ops);
            }
          }
        }
      } else if (propName === "src") {
        if (node.created) {
          const src = value == null ? "" : String(value);
          push({ op: "set", id: node.id, name: "src", src });
        }
      } else if (propName === "value") {
        if (node.created) {
          const nextValue = value == null ? "" : String(value);
          push({ op: "set", id: node.id, name: "value", value: nextValue });
        }
      } else if (node.created && isAccessibilityField(propName)) {
        applyAccessibilityMutation(node, propName, value, ops);
      } else if (node.created && isTransformField(propName)) {
        applyTransformMutation(node, propName, value, ops);
      } else if (node.created && isVisualField(propName)) {
        applyVisualMutation(node, propName, value, ops);
      } else if (node.created && isScrollField(propName)) {
        applyScrollMutation(node, propName, value, ops);
      } else if (node.created && isFocusField(propName)) {
        applyFocusMutation(node, propName, value, ops);
      } else if (node.created && isAnchorField(propName)) {
        applyAnchorMutation(node, propName, value, ops);
      }
      flushController.scheduleFlush();
    },
  };

  const renderer = createRenderer<HostNode>({
    createElement: runtimeOps.createElement,
    createTextNode: runtimeOps.createTextNode,
    createFragment: runtimeOps.createSlotNode,
    isTextNode(node) {
      return node.tag === "text";
    },
    replaceText: runtimeOps.replaceText,
    insertNode: runtimeOps.insertNode,
    removeNode: runtimeOps.removeNode,
    setProperty: runtimeOps.setProperty,
    getParentNode(node) {
      return node.parent;
    },
    getFirstChild(node) {
      return node.children[0];
    },
    getNextSibling(node) {
      if (!node.parent) return undefined;
      const idx = node.parent.children.indexOf(node);
      if (idx === -1 || idx === node.parent.children.length - 1) return undefined;
      return node.parent.children[idx + 1];
    },
  } as any);

  registerRuntimeBridge(flushController.scheduleFlush, registerNode, {
    ...runtimeOps,
    insert: renderer.insert,
    spread: renderer.spread,
  });

  native.onEvent((name, payload) => {
    if (payload.byteLength < 4) return;
    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const targetId = view.getUint32(0, true);

    const targets =
      targetId === 0
        ? Array.from(nodeIndex.values())
        : [nodeIndex.get(targetId)].filter((node): node is HostNode => !!node);
    if (!targets.length) return;

    const sliced = payload.subarray(4);
    for (const node of targets) {
      const handlers = node.listeners.get(name);
      if (!handlers?.size) continue;
      for (const handler of handlers) {
        queueMicrotask(() => handler(sliced));
      }
    }
  });

  return {
    render(view: () => any) {
      return renderer.render(view, root);
    },
    flush: flushController.flush,
    flushIfPending: flushController.flushIfPending,
    hasPendingFlush: flushController.hasPendingFlush,
    root,
    getNodeIndex() {
      return nodeIndex;
    },
  };
};

export type SolidHost = ReturnType<typeof createSolidHost>;
export const createSolidNativeHost = createSolidHost;
