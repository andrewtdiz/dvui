import { createRenderer } from "./universal.js";

let nextId = 1;
const nodes = new Map();
const ops = [];
const handleSymbol = Symbol("solidNodeId");
const handles = new Map();
const registeredSignals = new Map();

function extractSetter(source) {
  if (typeof source === "function") {
    return source;
  }
  if (source && typeof source === "object") {
    if (typeof source.set === "function") {
      return source.set;
    }
    if (typeof source.setter === "function") {
      return source.setter;
    }
  }
  return null;
}

function extractGetter(source) {
  if (source && typeof source === "object") {
    if (typeof source.get === "function") {
      return source.get;
    }
    if (typeof source.getter === "function") {
      return source.getter;
    }
  }
  return null;
}

function extractInitialValue(source) {
  if (source && typeof source === "object" && "value" in source) {
    return source.value;
  }
  return undefined;
}

function push(op) {
  ops.push(op);
}

function getHandle(id) {
  if (handles.has(id)) {
    return handles.get(id);
  }
  const handle = { [handleSymbol]: id };
  handles.set(id, handle);
  return handle;
}

function resolveId(value) {
  if (value == null) return null;
  if (typeof value === "object") {
    const id = value[handleSymbol];
    return typeof id === "number" ? id : null;
  }
  if (typeof value === "number") return value;
  return null;
}

function resetHost(rootId) {
  nodes.clear();
  ops.length = 0;
  nextId = rootId + 1;
  handles.clear();
  nodes.set(rootId, {
    id: rootId,
    handle: getHandle(rootId),
    type: "root",
    tag: "ROOT",
    parent: null,
    children: [],
    props: {},
    listeners: new Map(),
  });
}

function getNode(id) {
  return nodes.get(id);
}

function ensureChildren(record) {
  if (!record.children) {
    record.children = [];
  }
  return record.children;
}

function recordFor(node) {
  const id = resolveId(node);
  if (id == null) return null;
  return nodes.get(id);
}

function idFor(node) {
  return resolveId(node);
}

const host = {
  createElement(tag) {
    const id = nextId++;
    const record = {
      id,
      handle: getHandle(id),
      type: "element",
      tag,
      parent: null,
      children: [],
      props: {},
      listeners: new Map(),
    };
    nodes.set(id, record);
    push({ op: "create", id, tag });
    return record.handle;
  },
  createTextNode(value) {
    const id = nextId++;
    const text = value == null ? "" : String(value);
    const record = {
      id,
      handle: getHandle(id),
      type: "text",
      text,
      parent: null,
      children: [],
      props: {},
      listeners: new Map(),
    };
    nodes.set(id, record);
    push({ op: "text", id, text });
    return record.handle;
  },
  createSlotNode() {
    const id = nextId++;
    const record = {
      id,
      handle: getHandle(id),
      type: "slot",
      parent: null,
      children: [],
      props: {},
      listeners: new Map(),
    };
    nodes.set(id, record);
    push({ op: "slot", id });
    return record.handle;
  },
  isTextNode(node) {
    return recordFor(node)?.type === "text";
  },
  replaceText(node, value) {
    const record = recordFor(node);
    if (!record) return;
    record.text = value == null ? "" : String(value);
    push({ op: "text", id: record.id, text: record.text });
  },
  insertNode(parentRef, childRef, anchorRef) {
    const parentId = idFor(parentRef);
    const childId = idFor(childRef);
    const anchorId = idFor(anchorRef);
    const parent = nodes.get(parentId);
    const child = nodes.get(childId);
    if (!parent || !child) return;
    child.parent = parent.id;

    const children = ensureChildren(parent);
    const childHandle = child.handle;
    const existingIndex = children.indexOf(childHandle);
    if (existingIndex >= 0) {
      children.splice(existingIndex, 1);
    }

    let insertIndex = -1;
    if (anchorId != null && anchorId !== 0) {
      const anchorHandle = getHandle(anchorId);
      insertIndex = children.indexOf(anchorHandle);
    }

    if (insertIndex >= 0) {
      children.splice(insertIndex, 0, childHandle);
    } else {
      children.push(childHandle);
    }

    push({
      op: "insert",
      parent: parent.id,
      id: child.id,
      before: anchorId ?? 0,
    });
  },
  removeNode(parentRef, childRef) {
    const parentId = idFor(parentRef);
    const childId = idFor(childRef);
    const parent = nodes.get(parentId);
    const child = nodes.get(childId);
    if (!child) return;

    if (parent?.children) {
      parent.children = parent.children.filter((handle) => handle !== child.handle);
    }

    removeRecursive(childId);
  },
  setProperty(nodeRef, name, value) {
    const id = idFor(nodeRef);
    const record = nodes.get(id);
    if (!record || typeof name !== "string") {
      return;
    }

    if (name.startsWith("on") && typeof value === "function") {
      const type = name.slice(2).toLowerCase();
      record.listeners.set(type, value);
      push({ op: "listen", id, type });
      return;
    }

    if (record.type === "text" && name === "data") {
      record.text = value == null ? "" : String(value);
      push({ op: "text", id, text: record.text });
      return;
    }

    record.props[name] = value;
    if (value == null) {
      return;
    }

    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean"
    ) {
      push({ op: "set", id, name, value });
    }
  },
  getParentNode(nodeRef) {
    const record = recordFor(nodeRef);
    if (!record || record.parent == null) return null;
    return getHandle(record.parent);
  },
  getFirstChild(nodeRef) {
    const record = recordFor(nodeRef);
    if (!record || !record.children || record.children.length === 0) {
      return null;
    }
    return record.children[0];
  },
  getNextSibling(nodeRef) {
    const record = recordFor(nodeRef);
    if (!record || record.parent == null) return null;
    const parent = nodes.get(record.parent);
    if (!parent || !parent.children) return null;
    const index = parent.children.indexOf(record.handle);
    if (index === -1) return null;
    return parent.children[index + 1] ?? null;
  },
};

function removeRecursive(nodeId) {
  const record = nodes.get(nodeId);
  if (!record) return;

  if (record.children) {
    for (const childHandle of record.children) {
      const childId = resolveId(childHandle);
      if (typeof childId === "number") {
        removeRecursive(childId);
      }
    }
  }

  nodes.delete(nodeId);
  handles.delete(nodeId);
  push({ op: "remove", id: nodeId });
}

const renderer = createRenderer(host);
const {
  render,
  createElement,
  createTextNode,
  createSlotNode,
  isTextNode,
  replaceText,
  insert,
  insertNode,
  removeNode,
  setProp,
  mergeProps,
  effect,
  memo,
  createComponent,
  use,
  spread,
} = renderer;
let dispose = null;

export function renderApp(AppFn, rootKey = 0) {
  if (typeof AppFn !== "function") {
    throw new Error("renderApp expects a function component");
  }

  resetHost(rootKey);
  dispose?.();
  const rootHandle = getHandle(rootKey);
  dispose = render(AppFn, rootHandle);
}

export function flushOps() {
  if (ops.length === 0) {
    return [];
  }
  return ops.splice(0, ops.length);
}

export function dispatchEvent(nodeId, type, detail) {
  const record = nodes.get(nodeId);
  if (!record || !record.listeners) return;
  const handler = record.listeners.get(type);
  if (typeof handler === "function") {
    let currentValue = "";
    if (detail && typeof detail === "object" && "value" in detail) {
      currentValue = detail.value ?? "";
    } else if (typeof detail === "string") {
      currentValue = detail;
    }
    const target = {
      nodeId,
      value: currentValue,
    };
    handler({
      currentTarget: target,
      target: target,
      detail: detail ?? null,
      preventDefault() {},
    });
  }
}

export function registerSignal(key, source) {
  if (typeof key !== "string") {
    console.error(`Invalid signal key: ${key}`);
    return;
  }

  const setter = extractSetter(source);
  if (typeof setter !== "function") {
    console.error(`registerSignal expected a setter for key: ${key}`);
    return;
  }

  const getter = extractGetter(source);
  let lastKnown = extractInitialValue(source);
  if (typeof getter === "function") {
    try {
      lastKnown = getter();
    } catch (error) {
      console.error(`Failed to read initial value for signal '${key}'`, error);
    }
  }

  registeredSignals.set(key, {
    setter,
    getter: typeof getter === "function" ? getter : null,
    lastKnown,
  });
}

export function updateState(key, value) {
  const entry = registeredSignals.get(key);
  if (entry && typeof entry.setter === "function") {
    entry.lastKnown = value;
    entry.setter(value);
    return;
  }
  console.error(`No signal registered for key: ${key}`);
}

export function getSignalValue(key) {
  const entry = registeredSignals.get(key);
  if (!entry) {
    console.error(`No signal registered for key: ${key}`);
    return undefined;
  }
  if (typeof entry.getter === "function") {
    try {
      const current = entry.getter();
      entry.lastKnown = current;
      return current;
    } catch (error) {
      console.error(`Failed to read signal '${key}'`, error);
    }
  }
  return entry.lastKnown;
}

export const SolidHost = {
  renderApp,
  flushOps,
  dispatchEvent,
  registerSignal,
  updateState,
  getSignalValue,
};

globalThis.SolidHost = SolidHost;

export {
  renderer,
  createElement,
  createTextNode,
  createSlotNode,
  isTextNode,
  replaceText,
  insert,
  insertNode,
  removeNode,
  setProp,
  mergeProps,
  effect,
  memo,
  createComponent,
  use,
  spread,
};
