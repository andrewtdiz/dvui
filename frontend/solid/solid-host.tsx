/** @jsxImportSource solid-js */
import { createRenderer } from "solid-js/universal";
import { CommandEncoder, type RendererAdapter } from "./native-renderer";
import { registerRuntimeBridge } from "./runtime-bridge";

type ColorInput =
  | string
  | number
  | [number, number, number]
  | [number, number, number, number]
  | Uint8Array
  | Uint8ClampedArray;

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

type SerializedNode = {
  id: number;
  tag: string;
  parent?: number;
  text?: string;
  className?: string;
};

type MutationOp = {
  op: "create" | "remove" | "move" | "set_text" | "set_class";
  id: number;
  parent?: number;
  before?: number | null;
  tag?: string;
  text?: string;
  className?: string;
};

type MutationMode = "snapshot_once" | "snapshot_every_flush" | "mutations_only";

let nextId = 1;

export class HostNode {
  readonly id = nextId++;
  readonly tag: string;
  parent?: HostNode;
  children: HostNode[] = [];
  props: NodeProps = {};
  listeners = new Map<string, Set<EventHandler>>();
  // Tracks whether a create op has been sent to the native side.
  created = false;

  constructor(tag: string) {
    this.tag = tag;
  }

  // DOM-like accessors used by the compiled Solid runtime template helpers.
  get firstChild(): HostNode | undefined {
    return this.children[0];
  }

  get lastChild(): HostNode | undefined {
    return this.children.length > 0
      ? this.children[this.children.length - 1]
      : undefined;
  }

  get textContent(): string {
    if (this.tag === "text") return this.props.text ?? "";
    return this.children.map((c) => c.textContent).join("");
  }

  set textContent(val: string) {
    if (this.tag === "text") {
      this.props.text = val;
      return;
    }
    // replace children with a single text node
    this.children = [];
    const child = new HostNode("text");
    child.props.text = val;
    this.add(child);
  }

  // aliases to match DOM text node expectations
  get nodeValue(): string {
    return this.textContent;
  }
  set nodeValue(val: string) {
    this.textContent = val;
  }
  get data(): string {
    return this.textContent;
  }
  set data(val: string) {
    this.textContent = val;
  }

  get nextSibling(): HostNode | undefined {
    if (!this.parent) return undefined;
    const idx = this.parent.children.indexOf(this);
    if (idx === -1) return undefined;
    return this.parent.children[idx + 1];
  }

  get previousSibling(): HostNode | undefined {
    if (!this.parent) return undefined;
    const idx = this.parent.children.indexOf(this);
    if (idx <= 0) return undefined;
    return this.parent.children[idx - 1];
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

  if (
    Array.isArray(value) ||
    value instanceof Uint8Array ||
    value instanceof Uint8ClampedArray
  ) {
    const r = toByte(value[0]);
    const g = toByte(value[1]);
    const b = toByte(value[2]);
    const a = toByte(value[3] ?? 255);
    return ((r << 24) | (g << 16) | (b << 8) | a) >>> 0;
  }

  const normalized = value.startsWith("#") ? value.slice(1) : value;
  const expanded =
    normalized.length === 6
      ? `${normalized}ff`
      : normalized.length === 8
      ? normalized
      : normalized.padEnd(8, "f");
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
          return [r, g, b, 255] as [number, number, number, number];
        }
        if (hex.length === 8) {
          const r = (parsed >> 24) & 0xff;
          const g = (parsed >> 16) & 0xff;
          const b = (parsed >> 8) & 0xff;
          const a = parsed & 0xff;
          return [r, g, b, a] as [number, number, number, number];
        }
      }
    }
    if (name in named) {
      const [r, g, b] = named[name];
      return [r, g, b, 255] as [number, number, number, number];
    }
  }
  return undefined;
};

const emitNode = (
  node: HostNode,
  encoder: CommandEncoder,
  parentId: number
) => {
  let downstreamParent = parentId;

  if (node.tag !== "root" && node.tag !== "slot") {
    const frame = frameFromProps(node.props);
    const flags = hasAbsoluteClass(node.props) ? 1 : 0;
    const resolvedColor = node.props.color ?? bgColorFromClass(node.props);

    if (node.tag === "text") {
      encoder.pushText(
        node.id,
        parentId,
        frame,
        node.props.text ?? "",
        packColor(node.props.color),
        flags
      );
    } else {
      encoder.pushQuad(
        node.id,
        parentId,
        frame,
        packColor(resolvedColor),
        flags
      );
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

const markCreated = (node: HostNode) => {
  node.created = true;
  for (const child of node.children) {
    markCreated(child);
  }
};

export const createSolidNativeHost = (native: RendererAdapter) => {
  const encoder = native.encoder;
  const root = new HostNode("root");
  const nodeIndex = new Map<number, HostNode>([[root.id, root]]);
  let flushPending = false;
  const treeEncoder = new TextEncoder();
  const ops: MutationOp[] = [];
  const mutationsSupported = typeof native.applyOps === "function";
  let seq = 0;

  // Default: seed once with a snapshot, then rely on mutations; periodic safety resyncs keep state aligned.
  const mutationMode: MutationMode = "snapshot_once";
  const snapshotEveryFlush = mutationMode === "snapshot_every_flush";
  const snapshotOnceThenMutations = mutationMode === "snapshot_once";
  const mutationsOnlyAfterSnapshot = mutationMode === "mutations_only";
  let syncedOnce = false;
  let needFullSync = false;
  let framesSinceSnapshot = 0;

  const nodeClass = (node: HostNode) => node.props.className ?? node.props.class;

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
      ops.push(createOp);
      return;
    }
    ops.push({
      op: "move",
      id: node.id,
      parent: parentId,
      before: beforeId,
    });
  };

  const enqueueText = (node: HostNode) => {
    if (node.tag !== "text") return;
    ops.push({
      op: "set_text",
      id: node.id,
      text: node.props.text ?? "",
    });
  };

  const flush = () => {
    flushPending = false;
    framesSinceSnapshot += 1;

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
    nodes.push(entry);
    for (const child of node.children) {
      serialize(child, node.id);
    }
  };

    encoder.reset();
    for (const child of root.children) {
      serialize(child, 0);
      emitNode(child, encoder, 0);
    }

    // If we are in mutations-only mode and somehow collected nothing, synthesize create ops from the serialized tree.
    if (mutationsOnlyAfterSnapshot && ops.length == 0) {
      for (const n of nodes) {
        if (n.id === 0) continue;
        const createOp: MutationOp = {
          op: "create",
          id: n.id,
          parent: n.parent ?? 0,
          before: null,
          tag: n.tag,
          className: n.className,
          text: n.text,
        };
        ops.push(createOp);
      }
    }

    // Mutations path (after initial snapshot unless forced otherwise).
    if (mutationsSupported && native.applyOps && ops.length > 0 && !needFullSync && (syncedOnce || mutationsOnlyAfterSnapshot)) {
      const payload = treeEncoder.encode(JSON.stringify({ seq: ++seq, ops }));
      const ok = native.applyOps(payload);
      ops.length = 0;
      if (!ok) {
        needFullSync = true;
      }
    }

    const periodicResync = snapshotOnceThenMutations && framesSinceSnapshot >= 300;

    const shouldSnapshot =
      !syncedOnce ||
      snapshotEveryFlush ||
      needFullSync ||
      periodicResync ||
      (!mutationsSupported && native.setSolidTree != null);

    if (native.setSolidTree && shouldSnapshot) {
      const payload = treeEncoder.encode(JSON.stringify({ nodes }));
      native.setSolidTree(payload);
      markCreated(root);
      syncedOnce = true;
      needFullSync = false;
      ops.length = 0;
      framesSinceSnapshot = 0;
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
    const view = new DataView(
      payload.buffer,
      payload.byteOffset,
      payload.byteLength
    );
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
    createFragment() {
      return registerNode(new HostNode("slot"));
    },
    isTextNode(node) {
      return node.tag === "text";
    },
  replaceText(node, value: string) {
    if (node.tag !== "text") return;
    node.props.text = value;
    if (node.created) {
      enqueueText(node);
    }
      scheduleFlush();
    },
  insertNode(parent, node, anchor) {
    const targetIndex = anchor
      ? parent.children.indexOf(anchor)
      : parent.children.length;
    parent.add(
      node,
      targetIndex === -1 ? parent.children.length : targetIndex
    );
    enqueueCreateOrMove(parent, node, anchor);
    scheduleFlush();
  },
  removeNode(parent, node) {
    parent.remove(node);
    removeFromIndex(node, nodeIndex);
    node.created = false;
    ops.push({ op: "remove", id: node.id });
    scheduleFlush();
  },
  setProperty(node, name, value, prev) {
      if (name.startsWith("on:")) {
        const eventName = name.slice(3);
    if (typeof prev === "function")
      node.off(eventName, prev as unknown as EventHandler);
    if (typeof value === "function")
      node.on(eventName, value as unknown as EventHandler);
    return;
  }

  node.props[name] = value;
  if (name === "class" || name === "className") {
    if (node.created) {
      const cls = value == null ? "" : String(value);
      ops.push({ op: "set_class", id: node.id, className: cls });
    }
  }
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
      if (idx === -1 || idx === node.parent.children.length - 1)
        return undefined;
      return node.parent.children[idx + 1];
    },
  } as any);

  return {
    render(view: () => any) {
      return renderer.render(view, root);
    },
    flush,
    flushIfPending() {
      if (flushPending) flush();
    },
    hasPendingFlush() {
      return flushPending;
    },
    root,
  };
};
