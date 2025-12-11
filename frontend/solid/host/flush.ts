import { CommandEncoder } from "../native/encoder";
import type { RendererAdapter } from "../native/adapter";
import type { HostNode } from "./node";
import {
  bgColorFromClass,
  extractTransform,
  extractVisual,
  frameFromProps,
  hasAbsoluteClass,
  packColor,
  transformFields,
  visualFields,
} from "./props";
import type { MutationMode, MutationOp } from "./mutation-queue";
import { serializeTree, type SerializedNode } from "./snapshot";

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

const markCreated = (node: HostNode) => {
  node.created = true;
  for (const child of node.children) {
    markCreated(child);
  }
};

const emitPendingListeners = (node: HostNode, ops: MutationOp[]) => {
  for (const [eventType] of node.listeners) {
    if (node.sentListeners.has(eventType)) continue;
    ops.push({ op: "listen", id: node.id, eventType });
    node.sentListeners.add(eventType);
  }
  node.listenersDirty = false;
};

export type FlushController = {
  flush: () => void;
  flushIfPending: () => void;
  hasPendingFlush: () => boolean;
  scheduleFlush: () => void;
};

export type FlushContext = {
  native: RendererAdapter;
  encoder: CommandEncoder;
  root: HostNode;
  nodeIndex: Map<number, HostNode>;
  ops: MutationOp[];
  mutationMode?: MutationMode;
};

export const createFlushController = (ctx: FlushContext): FlushController => {
  const { native, encoder, root, nodeIndex, ops } = ctx;
  const mutationMode: MutationMode = ctx.mutationMode ?? "snapshot_once";
  const treeEncoder = new TextEncoder();
  const mutationsSupported = typeof native.applyOps === "function";

  let flushPending = false;
  let seq = 0;
  let syncedOnce = false;
  let needFullSync = false;
  let framesSinceSnapshot = 0;

  const snapshotEveryFlush = mutationMode === "snapshot_every_flush";
  const snapshotOnceThenMutations = mutationMode === "snapshot_once";
  const mutationsOnlyAfterSnapshot = mutationMode === "mutations_only";

  const flush = () => {
    flushPending = false;
    framesSinceSnapshot += 1;

    const nodes: SerializedNode[] = serializeTree(root.children);

    encoder.reset();
    for (const child of root.children) {
      emitNode(child, encoder, 0);
    }

    for (const node of nodeIndex.values()) {
      if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
        emitPendingListeners(node, ops);
      }
    }

    if (mutationsOnlyAfterSnapshot && ops.length === 0) {
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

    if (mutationsSupported && native.applyOps && ops.length > 0 && !needFullSync && (syncedOnce || mutationsOnlyAfterSnapshot)) {
      const payloadObj = { seq: ++seq, ops };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      const ok = native.applyOps(payload);
      ops.length = 0;
      if (!ok) {
        needFullSync = true;
      }
    }

    const periodicResync = snapshotOnceThenMutations && framesSinceSnapshot >= 300;
    const shouldSnapshot =
      !syncedOnce || snapshotEveryFlush || needFullSync || periodicResync || (!mutationsSupported && native.setSolidTree != null);
    let sentSnapshot = false;

    if (native.setSolidTree && shouldSnapshot) {
      const payloadObj = { nodes };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      native.setSolidTree(payload);
      markCreated(root);
      syncedOnce = true;
      needFullSync = false;
      ops.length = 0;
      framesSinceSnapshot = 0;
      sentSnapshot = true;

      for (const node of nodeIndex.values()) {
        if (node.sentListeners.size > 0) {
          node.sentListeners.clear();
          node.listenersDirty = true;
        }
      }
    }

    if (sentSnapshot && mutationsSupported && native.applyOps) {
      for (const node of nodeIndex.values()) {
        if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
          emitPendingListeners(node, ops);
        }
      }
      const listenOps = ops.filter((op) => op.op === "listen");
      if (listenOps.length > 0) {
        const payloadObj = { seq: ++seq, ops: listenOps };
        const payload = treeEncoder.encode(JSON.stringify(payloadObj));
        const ok = native.applyOps(payload);
        if (!ok) {
          needFullSync = true;
        }
      }
      ops.length = 0;
    }

    native.commit(encoder);
  };

  const scheduleFlush = () => {
    if (flushPending) return;
    flushPending = true;
    queueMicrotask(flush);
  };

  return {
    flush,
    flushIfPending() {
      if (flushPending) flush();
    },
    hasPendingFlush() {
      return flushPending;
    },
    scheduleFlush,
  };
};

export const applyVisualMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  const payload: MutationOp = { op: "set_visual", id: node.id };
  if (name === "background" || name === "textColor") {
    payload[name] = packColor(value as number);
  } else if (name === "clipChildren") {
    payload.clipChildren = Boolean(value);
  } else if (typeof value === "number" && Number.isFinite(value)) {
    payload[name] = value as number;
  }
  const hasField =
    payload.opacity != null ||
    payload.cornerRadius != null ||
    payload.background != null ||
    payload.textColor != null ||
    payload.clipChildren != null;
  if (hasField) {
    ops.push(payload);
  }
};

export const applyTransformMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  if (typeof value === "number" && Number.isFinite(value)) {
    const payload: MutationOp = { op: "set_transform", id: node.id, [name]: value } as MutationOp;
    ops.push(payload);
  }
};

export const isTransformField = (name: string): name is (typeof transformFields)[number] => {
  return (transformFields as readonly string[]).includes(name);
};

export const isVisualField = (name: string): name is (typeof visualFields)[number] => {
  return (visualFields as readonly string[]).includes(name);
};
