/** @jsxImportSource solid-js */
import { createRenderer } from "solid-js/universal";
import { CommandEncoder, type RendererAdapter } from "./native-renderer";
import { registerRuntimeBridge } from "./runtime-bridge";

type ColorInput = string | number | [number, number, number] | Uint8Array | Uint8ClampedArray;

type NodeProps = {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  color?: ColorInput;
  text?: string;
  class?: string;
  className?: string;
};

type EventHandler = (payload: Uint8Array) => void;

let nextId = 1;

export class HostNode {
  readonly id = nextId++;
  readonly tag: string;
  parent?: HostNode;
  children: HostNode[] = [];
  props: NodeProps = {};
  listeners = new Map<string, Set<EventHandler>>();

  constructor(tag: string) {
    this.tag = tag;
  }

  add(child: HostNode, index = this.children.length) {
    child.parent = this;
    this.children.splice(index, 0, child);
  }

  remove(child: HostNode) {
    const idx = this.children.indexOf(child);
    if (idx >= 0) {
      this.children.splice(idx, 1);
    }
    child.parent = undefined;
  }

  on(event: string, handler: EventHandler) {
    const bucket = this.listeners.get(event) ?? new Set<EventHandler>();
    bucket.add(handler);
    this.listeners.set(event, bucket);
  }

  off(event: string, handler?: EventHandler) {
    if (!handler) {
      this.listeners.delete(event);
      return;
    }
    const bucket = this.listeners.get(event);
    if (!bucket) return;
    bucket.delete(handler);
    if (bucket.size === 0) {
      this.listeners.delete(event);
    }
  }
}

const toByte = (value: number) => {
  if (Number.isNaN(value) || !Number.isFinite(value)) return 0;
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value | 0;
};

const packColor = (value?: ColorInput): number => {
  if (typeof value === "number") return value >>> 0;
  if (!value) return 0xffffffff;

  if (Array.isArray(value) || value instanceof Uint8Array || value instanceof Uint8ClampedArray) {
    const r = toByte(value[0]);
    const g = toByte(value[1]);
    const b = toByte(value[2]);
    const a = toByte(value[3] ?? 255);
    return ((r << 24) | (g << 16) | (b << 8) | a) >>> 0;
  }

  const normalized = value.startsWith("#") ? value.slice(1) : value;
  const expanded = normalized.length === 6 ? `${normalized}ff` : normalized.length === 8 ? normalized : normalized.padEnd(8, "f");
  const parsed = Number.parseInt(expanded, 16);
  if (Number.isNaN(parsed)) return 0xffffffff;
  return parsed >>> 0;
};

const frameFromProps = (props: NodeProps) => ({
  x: props.x ?? 0,
  y: props.y ?? 0,
  width: props.width ?? 0,
  height: props.height ?? 0,
});

const hasAbsoluteClass = (props: NodeProps) => {
  const raw = props.className ?? props.class;
  if (!raw) return false;
  return raw
    .split(/\s+/)
    .map((c) => c.trim())
    .filter(Boolean)
    .includes("absolute");
};

const bgColorFromClass = (props: NodeProps): ColorInput | undefined => {
  const raw = props.className ?? props.class;
  if (!raw) return undefined;
  const tokens = raw.split(/\s+/).filter(Boolean);

  const named: Record<string, [number, number, number]> = {
    black: [0, 0, 0],
    white: [255, 255, 255],
    "gray-900": [17, 24, 39],
    "gray-800": [31, 41, 55],
    "gray-700": [55, 65, 81],
    "gray-600": [75, 85, 99],
    "gray-500": [107, 114, 128],
    "gray-400": [156, 163, 175],
    "blue-900": [30, 58, 138],
    "blue-800": [30, 64, 175],
    "blue-700": [29, 78, 216],
    "blue-600": [37, 99, 235],
    "blue-500": [59, 130, 246],
    "blue-400": [96, 165, 250],
  };

  for (const token of tokens) {
    if (!token.startsWith("bg-")) continue;
    const name = token.slice(3);
    if (name.startsWith("[") && name.endsWith("]")) {
      const inner = name.slice(1, -1);
      const hex = inner.startsWith("#") ? inner.slice(1) : inner;
      const parsed = Number.parseInt(hex, 16);
      if (!Number.isNaN(parsed)) {
        if (hex.length === 6) {
          const r = (parsed >> 16) & 0xff;
          const g = (parsed >> 8) & 0xff;
          const b = parsed & 0xff;
          return [r, g, b, 255];
        }
        if (hex.length === 8) {
          const r = (parsed >> 24) & 0xff;
          const g = (parsed >> 16) & 0xff;
          const b = (parsed >> 8) & 0xff;
          const a = parsed & 0xff;
          return [r, g, b, a];
        }
      }
    }
    if (name in named) {
      const [r, g, b] = named[name];
      return [r, g, b, 255];
    }
  }
  return undefined;
};

const emitNode = (node: HostNode, encoder: CommandEncoder, parentId: number) => {
  let downstreamParent = parentId;

  if (node.tag !== "root" && node.tag !== "slot") {
    const frame = frameFromProps(node.props);
    const flags = hasAbsoluteClass(node.props) ? 1 : 0;
    const resolvedColor = node.props.color ?? bgColorFromClass(node.props);

    if (node.tag === "text") {
      encoder.pushText(node.id, parentId, frame, node.props.text ?? "", packColor(node.props.color), flags);
    } else {
      encoder.pushQuad(node.id, parentId, frame, packColor(resolvedColor), flags);
    }

    downstreamParent = node.id;
  } else if (node.tag !== "slot") {
    downstreamParent = node.id;
  }

  const nextParent = node.tag === "slot" ? parentId : downstreamParent;

  for (const child of node.children) {
    emitNode(child, encoder, nextParent);
  }
};

const removeFromIndex = (node: HostNode, index: Map<number, HostNode>) => {
  index.delete(node.id);
  for (const child of node.children) {
    removeFromIndex(child, index);
  }
};

export const createSolidNativeHost = (native: RendererAdapter) => {
  const encoder = native.encoder;
  const root = new HostNode("root");
  const nodeIndex = new Map<number, HostNode>([[root.id, root]]);
  let flushPending = false;

  const flush = () => {
    flushPending = false;
    encoder.reset();
    for (const child of root.children) {
      emitNode(child, encoder, 0);
    }
    native.commit(encoder);
  };

  const scheduleFlush = () => {
    if (flushPending) return;
    flushPending = true;
    queueMicrotask(flush);
  };

  registerRuntimeBridge(scheduleFlush);

  native.onEvent((name, payload) => {
    if (payload.byteLength < 4) return;
    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const targetId = view.getUint32(0, true);

    const targets = targetId === 0 ? Array.from(nodeIndex.values()) : [nodeIndex.get(targetId)].filter((node): node is HostNode => !!node);
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

  const registerNode = (node: HostNode) => {
    nodeIndex.set(node.id, node);
    return node;
  };

  const renderer = createRenderer<HostNode>({
    createElement(tagName: string) {
      return registerNode(new HostNode(tagName));
    },
    createTextNode(value: string | number) {
      const node = registerNode(new HostNode("text"));
      node.props.text = typeof value === "number" ? `${value}` : value;
      return node;
    },
    createSlotNode() {
      return registerNode(new HostNode("slot"));
    },
    isTextNode(node) {
      return node.tag === "text";
    },
    replaceText(node, value: string) {
      if (node.tag !== "text") return;
      node.props.text = value;
      scheduleFlush();
    },
    insertNode(parent, node, anchor) {
      const targetIndex = anchor ? parent.children.indexOf(anchor) : parent.children.length;
      parent.add(node, targetIndex === -1 ? parent.children.length : targetIndex);
      scheduleFlush();
    },
    removeNode(parent, node) {
      parent.remove(node);
      removeFromIndex(node, nodeIndex);
      scheduleFlush();
    },
    setProperty(node, name, value, prev) {
      if (name.startsWith("on:")) {
        const eventName = name.slice(3);
        if (typeof prev === "function") node.off(eventName, prev);
        if (typeof value === "function") node.on(eventName, value);
        return;
      }

      node.props[name] = value;
      scheduleFlush();
    },
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
  });

  return {
    render(view: () => any) {
      return renderer.render(view, root);
    },
    flush,
    root,
  };
};
