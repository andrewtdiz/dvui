import { CommandEncoder } from "../native/encoder";
import type { RendererAdapter } from "../native/adapter";
import type { HostNode } from "./node";
import {
  accessibilityFields,
  anchorFields,
  bgColorFromClass,
  extractAnchor,
  extractTransform,
  extractVisual,
  frameFromProps,
  hasAbsoluteClass,
  packColor,
  focusFields,
  scrollFields,
  transformFields,
  visualFields,
} from "./props";
import type { MutationMode, MutationOp } from "./mutation-queue";
import { serializeTree, type SerializedNode } from "./snapshot";

const emitNode = (node: HostNode, encoder: CommandEncoder, parentId: number) => {
  let downstreamParent = parentId;
  const isPassthrough = node.tag === "slot" || node.tag === "portal";

  if (node.tag !== "root" && !isPassthrough) {
    const frame = frameFromProps(node.props);
    const flags = hasAbsoluteClass(node.props) ? 1 : 0;
    const resolvedColor = node.props.color ?? bgColorFromClass(node.props);
    const packedBackground = resolvedColor == null ? 0x00000000 : packColor(resolvedColor);

    if (node.tag === "text") {
      encoder.pushText(node.id, parentId, frame, node.props.text ?? "", packColor(node.props.color), flags);
    } else {
      encoder.pushQuad(node.id, parentId, frame, packedBackground, flags);
    }

    downstreamParent = node.id;
  } else if (!isPassthrough) {
    downstreamParent = node.id;
  }

  const nextParent = isPassthrough ? parentId : downstreamParent;
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

type PendingListener = {
  node: HostNode;
  eventType: string;
};

const queuePendingListeners = (node: HostNode, ops: MutationOp[], pending: PendingListener[]) => {
  for (const [eventType] of node.listeners) {
    if (node.sentListeners.has(eventType)) continue;
    ops.push({ op: "listen", id: node.id, eventType });
    pending.push({ node, eventType });
  }
};

const commitPendingListeners = (pending: PendingListener[]) => {
  if (pending.length === 0) return;
  const touched = new Set<HostNode>();
  for (const entry of pending) {
    entry.node.sentListeners.add(entry.eventType);
    touched.add(entry.node);
  }
  for (const node of touched) {
    if (node.sentListeners.size >= node.listeners.size) {
      node.listenersDirty = false;
    }
  }
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
  let mutationsOnlySynced = false;

  const snapshotEveryFlush = mutationMode === "snapshot_every_flush";
  const snapshotOnceThenMutations = mutationMode === "snapshot_once";
  const mutationsOnlyAfterSnapshot = mutationMode === "mutations_only";

  const flush = () => {
    flushPending = false;

    let nodes: SerializedNode[] | null = null;
    const ensureNodes = () => {
      if (!nodes) nodes = serializeTree(root.children);
      return nodes;
    };
    let shouldEncodeCommands = native.setSolidTree == null;
    const pendingListeners: PendingListener[] = [];

    for (const node of nodeIndex.values()) {
      if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
        queuePendingListeners(node, ops, pendingListeners);
      }
    }

    const needsCreateOps = mutationsOnlyAfterSnapshot && !mutationsOnlySynced && ops.length === 0;
    if (needsCreateOps) {
      for (const n of ensureNodes()) {
        if (n.id === 0) continue;
        const createOp: MutationOp = {
          op: "create",
          id: n.id,
          parent: n.parent ?? 0,
          before: null,
          tag: n.tag,
          className: n.className,
          text: n.text,
          src: n.src,
          value: n.value,
          placeholder: n.placeholder,
          rotation: n.rotation,
          scaleX: n.scaleX,
          scaleY: n.scaleY,
          anchorX: n.anchorX,
          anchorY: n.anchorY,
          translateX: n.translateX,
          translateY: n.translateY,
          opacity: n.opacity,
          cornerRadius: n.cornerRadius,
          background: n.background,
          textColor: n.textColor,
          clipChildren: n.clipChildren,
          scroll: n.scroll,
          scrollX: n.scrollX,
          scrollY: n.scrollY,
          canvasWidth: n.canvasWidth,
          canvasHeight: n.canvasHeight,
          autoCanvas: n.autoCanvas,
          tabIndex: n.tabIndex,
          focusTrap: n.focusTrap,
          roving: n.roving,
          modal: n.modal,
          anchorId: n.anchorId,
          anchorSide: n.anchorSide,
          anchorAlign: n.anchorAlign,
          anchorOffset: n.anchorOffset,
          role: n.role,
          ariaLabel: n.ariaLabel,
          ariaDescription: n.ariaDescription,
          ariaExpanded: n.ariaExpanded,
          ariaSelected: n.ariaSelected,
          ariaChecked: n.ariaChecked,
          ariaPressed: n.ariaPressed,
          ariaHidden: n.ariaHidden,
          ariaDisabled: n.ariaDisabled,
          ariaHasPopup: n.ariaHasPopup,
          ariaModal: n.ariaModal,
        };
        ops.push(createOp);
      }
      shouldEncodeCommands = true;
    }

    if (mutationsSupported && native.applyOps && ops.length > 0 && !needFullSync && (syncedOnce || mutationsOnlyAfterSnapshot)) {
      const payloadObj = { seq: ++seq, ops };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      const ok = native.applyOps(payload);
      if (ok) {
        commitPendingListeners(pendingListeners);
        if (mutationsOnlyAfterSnapshot) {
          mutationsOnlySynced = true;
        }
      } else {
        const resyncRequested = !needFullSync;
        needFullSync = true;
        if (resyncRequested) scheduleFlush();
      }
      ops.length = 0;
    }
    pendingListeners.length = 0;

    const shouldSnapshot =
      !syncedOnce || snapshotEveryFlush || needFullSync || (!mutationsSupported && native.setSolidTree != null);
    let sentSnapshot = false;

    if (native.setSolidTree && shouldSnapshot) {
      const payloadObj = { nodes: ensureNodes() };
      const payload = treeEncoder.encode(JSON.stringify(payloadObj));
      native.setSolidTree(payload);
      markCreated(root);
      syncedOnce = true;
      if (mutationsOnlyAfterSnapshot) {
        mutationsOnlySynced = true;
      }
      needFullSync = false;
      ops.length = 0;
      sentSnapshot = true;
      shouldEncodeCommands = true;

      for (const node of nodeIndex.values()) {
        if (node.sentListeners.size > 0) {
          node.sentListeners.clear();
          node.listenersDirty = true;
        }
      }
    }

    if (sentSnapshot && mutationsSupported && native.applyOps) {
      pendingListeners.length = 0;
      for (const node of nodeIndex.values()) {
        if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
          queuePendingListeners(node, ops, pendingListeners);
        }
      }
      if (ops.length > 0) {
        const payloadObj = { seq: ++seq, ops };
        const payload = treeEncoder.encode(JSON.stringify(payloadObj));
        const ok = native.applyOps(payload);
        if (ok) {
          commitPendingListeners(pendingListeners);
        } else {
          const resyncRequested = !needFullSync;
          needFullSync = true;
          if (resyncRequested) scheduleFlush();
        }
      }
      ops.length = 0;
      pendingListeners.length = 0;
    }

    if (shouldEncodeCommands) {
      encoder.reset();
      for (const child of root.children) {
        emitNode(child, encoder, 0);
      }
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

export const applyScrollMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  const payload: MutationOp = { op: "set_scroll", id: node.id };
  if (name === "scroll") {
    payload.scroll = Boolean(value);
  } else if (name === "autoCanvas") {
    payload.autoCanvas = Boolean(value);
  } else if (typeof value === "number" && Number.isFinite(value)) {
    if (name === "scrollX") payload.scrollX = value;
    if (name === "scrollY") payload.scrollY = value;
    if (name === "canvasWidth") payload.canvasWidth = value;
    if (name === "canvasHeight") payload.canvasHeight = value;
  }
  const hasField =
    payload.scroll != null ||
    payload.scrollX != null ||
    payload.scrollY != null ||
    payload.canvasWidth != null ||
    payload.canvasHeight != null ||
    payload.autoCanvas != null;
  if (hasField) {
    ops.push(payload);
  }
};

export const applyFocusMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  const payload: MutationOp = { op: "set_focus", id: node.id };
  if (name === "tabIndex" && typeof value === "number" && Number.isFinite(value)) {
    payload.tabIndex = value;
  } else if (name === "focusTrap") {
    payload.focusTrap = Boolean(value);
  } else if (name === "roving") {
    payload.roving = Boolean(value);
  } else if (name === "modal") {
    payload.modal = Boolean(value);
  }
  const hasField =
    payload.tabIndex != null || payload.focusTrap != null || payload.roving != null || payload.modal != null;
  if (hasField) {
    ops.push(payload);
  }
};

export const applyAnchorMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  const payload: MutationOp = { op: "set_anchor", id: node.id };
  if (name === "anchorId" && typeof value === "number" && Number.isFinite(value)) {
    payload.anchorId = value;
  } else if (name === "anchorSide" && typeof value === "string") {
    payload.anchorSide = value;
  } else if (name === "anchorAlign" && typeof value === "string") {
    payload.anchorAlign = value;
  } else if (name === "anchorOffset" && typeof value === "number" && Number.isFinite(value)) {
    payload.anchorOffset = value;
  }
  const hasField =
    payload.anchorId != null ||
    payload.anchorSide != null ||
    payload.anchorAlign != null ||
    payload.anchorOffset != null;
  if (hasField) {
    ops.push(payload);
  }
};

const normalizeAriaBool = (value: unknown) => {
  if (value == null) return false;
  if (typeof value === "boolean") return value;
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true") return true;
    if (lowered === "false") return false;
  }
  return Boolean(value);
};

const normalizeAriaChecked = (value: unknown) => {
  if (value == null) return "false";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") {
    const lowered = value.toLowerCase();
    if (lowered === "true" || lowered === "false" || lowered === "mixed") return lowered;
  }
  return undefined;
};

const normalizeAriaHasPopup = (value: unknown) => {
  if (value == null || value === false) return "";
  if (typeof value === "string") return value;
  if (value === true) return "menu";
  return "";
};

export const applyAccessibilityMutation = (node: HostNode, name: string, value: unknown, ops: MutationOp[]) => {
  const payload: MutationOp = { op: "set_accessibility", id: node.id };
  if (name === "role") {
    payload.role = value == null ? "" : String(value);
  } else if (name === "ariaLabel") {
    payload.ariaLabel = value == null ? "" : String(value);
  } else if (name === "ariaDescription") {
    payload.ariaDescription = value == null ? "" : String(value);
  } else if (name === "ariaExpanded") {
    payload.ariaExpanded = normalizeAriaBool(value);
  } else if (name === "ariaSelected") {
    payload.ariaSelected = normalizeAriaBool(value);
  } else if (name === "ariaChecked") {
    const checked = normalizeAriaChecked(value);
    if (checked != null) payload.ariaChecked = checked;
  } else if (name === "ariaPressed") {
    const pressed = normalizeAriaChecked(value);
    if (pressed != null) payload.ariaPressed = pressed;
  } else if (name === "ariaHidden") {
    payload.ariaHidden = normalizeAriaBool(value);
  } else if (name === "ariaDisabled") {
    payload.ariaDisabled = normalizeAriaBool(value);
  } else if (name === "ariaHasPopup") {
    payload.ariaHasPopup = normalizeAriaHasPopup(value);
  } else if (name === "ariaModal") {
    payload.ariaModal = normalizeAriaBool(value);
  }
  const hasField =
    payload.role != null ||
    payload.ariaLabel != null ||
    payload.ariaDescription != null ||
    payload.ariaExpanded != null ||
    payload.ariaSelected != null ||
    payload.ariaChecked != null ||
    payload.ariaPressed != null ||
    payload.ariaHidden != null ||
    payload.ariaDisabled != null ||
    payload.ariaHasPopup != null ||
    payload.ariaModal != null;
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

export const isScrollField = (name: string): name is (typeof scrollFields)[number] => {
  return (scrollFields as readonly string[]).includes(name);
};

export const isFocusField = (name: string): name is (typeof focusFields)[number] => {
  return (focusFields as readonly string[]).includes(name);
};

export const isAnchorField = (name: string): name is (typeof anchorFields)[number] => {
  return (anchorFields as readonly string[]).includes(name);
};

export const isAccessibilityField = (name: string): name is (typeof accessibilityFields)[number] => {
  return (accessibilityFields as readonly string[]).includes(name);
};
