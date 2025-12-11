/**
 * SolidJS Universal Renderer Runtime
 *
 * This module provides the runtime functions that SolidJS's universal mode expects.
 * When using `generate: "universal"` in babel-preset-solid, the compiled JSX
 * calls these functions instead of DOM-specific ones.
 */

import { createEffect, createMemo, untrack } from "solid-js";
import { HostNode, type EventHandler } from "../host/node";
import { getRuntimeHostOps, notifyRuntimePropChange, registerRuntimeNode } from "./bridge";

// Solid built-in control-flow components are imported from this runtime module
// when using babel-preset-solid in universal mode.
export {
  For,
  Show,
  Switch,
  Match,
  Suspense,
  SuspenseList,
  Index,
  ErrorBoundary,
} from "solid-js";

// Universal runtime helpers expected by babel-plugin-jsx-dom-expressions.
export const memo = (fn: () => any) => createMemo(() => fn());

export const use = (fn: (el: any, arg: any) => any, el: any, arg: any) => {
  return untrack(() => fn(el, arg));
};

// Web-specific built-ins like Portal/Dynamic don't make sense for the native DVUI renderer.
// Provide minimal fallbacks so JSX compiles; they render inline.
export const Portal = (props: any) => props.children;

export const Dynamic = (props: any) => {
  return createMemo(() => {
    const Comp = props.component;
    if (!Comp) return null;
    const { component: _c, ...rest } = props;
    return typeof Comp === "function" ? Comp(rest) : Comp;
  });
};

export const createElement = (tag: string): HostNode => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.createElement) {
    return hostOps.createElement(tag);
  }
  const node = new HostNode(tag);
  registerRuntimeNode(node);
  return node;
};

export const createTextNode = (value: string | number): HostNode => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.createTextNode) {
    return hostOps.createTextNode(value);
  }
  const node = new HostNode("text");
  node.props.text = typeof value === "number" ? `${value}` : value;
  registerRuntimeNode(node);
  return node;
};

export const createSlotNode = (): HostNode => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.createSlotNode) {
    return hostOps.createSlotNode();
  }
  const node = new HostNode("slot");
  registerRuntimeNode(node);
  return node;
};

export const isTextNode = (node: HostNode): boolean => {
  return node.tag === "text";
};

export const replaceText = (node: HostNode, value: string): void => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.replaceText) {
    hostOps.replaceText(node, value);
    return;
  }
  if (node.tag === "text") {
    node.props.text = value;
    notifyRuntimePropChange();
  }
};

export const insertNode = (parent: HostNode, node: HostNode, anchor?: HostNode): HostNode => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.insertNode) {
    return hostOps.insertNode(parent, node, anchor);
  }

  if (anchor) {
    const idx = parent.children.indexOf(anchor);
    if (idx >= 0) {
      parent.add(node, idx);
    } else {
      parent.add(node);
    }
  } else {
    parent.add(node);
  }
  notifyRuntimePropChange();
  return node;
};

export const removeNode = (parent: HostNode, node: HostNode): void => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.removeNode) {
    hostOps.removeNode(parent, node);
    return;
  }
  parent.remove(node);
  notifyRuntimePropChange();
};

export const getParentNode = (node: HostNode): HostNode | undefined => {
  return node.parent;
};

export const getFirstChild = (node: HostNode): HostNode | undefined => {
  return node.firstChild;
};

export const getNextSibling = (node: HostNode): HostNode | undefined => {
  return node.nextSibling;
};

export const setProperty = (node: HostNode, name: string, value: any, prev?: any): void => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.setProperty) {
    hostOps.setProperty(node, name, value, prev);
    return;
  }

  if (name.startsWith("on:")) {
    const eventName = name.slice(3);
    if (prev) node.off(eventName, prev as EventHandler);
    if (value) node.on(eventName, value as EventHandler);
    notifyRuntimePropChange();
    return;
  }

  if (name.startsWith("on") && name.length > 2 && name[2] === name[2].toUpperCase()) {
    const eventName = name.slice(2, 3).toLowerCase() + name.slice(3);
    if (prev) node.off(eventName, prev as EventHandler);
    if (value) node.on(eventName, value as EventHandler);
    notifyRuntimePropChange();
    return;
  }

  if (name === "class" || name === "className") {
    node.props.className = value;
    node.props.class = value;
    notifyRuntimePropChange();
    return;
  }

  node.props[name] = value;
  notifyRuntimePropChange();
};

export const setProp = setProperty;
export const setAttribute = setProperty;

export const createComponent = (Comp: (props: any) => any, props: any) => {
  return Comp(props);
};

const resolveValue = (input: any): any => {
  let resolved = input;
  while (typeof resolved === "function") {
    resolved = resolved();
  }
  return resolved;
};

const appendContent = (parent: HostNode, value: any): boolean => {
  if (value == null || value === true || value === false) return false;

  if (typeof value === "string" || typeof value === "number") {
    const textNode = createTextNode(String(value));
    insertNode(parent, textNode);
    return true;
  }

  if (value instanceof HostNode) {
    insertNode(parent, value);
    return true;
  }

  return false;
};

const clearChildren = (node: HostNode) => {
  const existing = [...node.children];
  for (const child of existing) {
    removeNode(node, child);
  }
};

const applyInsertValue = (parent: HostNode, value: any) => {
  const resolved = resolveValue(value);
  clearChildren(parent);

  if (Array.isArray(resolved)) {
    for (const item of resolved) {
      appendContent(parent, resolveValue(item));
    }
  } else {
    appendContent(parent, resolved);
  }

  notifyRuntimePropChange();
};

export const insert = (parent: HostNode, value: any, anchor?: HostNode) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.insert) {
    hostOps.insert(parent, value, anchor ?? null);
    return;
  }

  if (anchor) {
    const wrapper = new HostNode("slot");
    applyInsertValue(wrapper, value);
    for (const child of wrapper.children) {
      insertNode(parent, child, anchor);
    }
  } else {
    applyInsertValue(parent, value);
  }

  if (typeof value === "function") {
    createEffect(() => applyInsertValue(parent, value));
  }
};

export const effect = (fn: (prev?: any) => any, initial?: any) => {
  fn(initial);
  return createEffect(() => fn(initial));
};

export const spread = (node: HostNode, props: any) => {
  const hostOps = getRuntimeHostOps();
  if (hostOps?.spread) {
    hostOps.spread(node, props);
    return node;
  }
  if (!props) return node;
  for (const [k, v] of Object.entries(props)) {
    setProperty(node, k, v);
  }
  return node;
};

export const mergeProps = (...sources: any[]) => {
  const out: Record<string, any> = {};
  for (const src of sources) {
    if (!src) continue;
    for (const [k, v] of Object.entries(src)) {
      out[k] = v;
    }
  }
  return out;
};

type Token =
  | { kind: "open"; tag: string; attrs: Record<string, string>; selfClosing: boolean }
  | { kind: "close"; tag: string }
  | { kind: "text"; value: string };

const tokenize = (source: string): Token[] => {
  const tokens: Token[] = [];
  const re = /<\/?[A-Za-z0-9:_-]+(?:\s+[^>]*?)?>/g;
  let lastIndex = 0;
  let m: RegExpExecArray | null;

  while ((m = re.exec(source)) !== null) {
    if (m.index > lastIndex) {
      const text = source.slice(lastIndex, m.index);
      if (text.trim()) {
        tokens.push({ kind: "text", value: text });
      }
    }
    lastIndex = re.lastIndex;

    const raw = m[0];
    if (raw.startsWith("</")) {
      const tag = raw.slice(2, -1).trim();
      tokens.push({ kind: "close", tag });
    } else {
      const selfClosing = raw.endsWith("/>");
      const inner = raw.slice(1, selfClosing ? -2 : -1).trim();
      const spaceIdx = inner.search(/\s/);
      const tag = spaceIdx === -1 ? inner : inner.slice(0, spaceIdx);
      const attrString = spaceIdx === -1 ? "" : inner.slice(spaceIdx);
      const attrs: Record<string, string> = {};
      const attrPattern = /([^\s=]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
      let ma: RegExpExecArray | null;
      while ((ma = attrPattern.exec(attrString)) !== null) {
        const name = ma[1];
        const value = ma[2] ?? ma[3] ?? ma[4] ?? "";
        attrs[name] = value;
      }
      tokens.push({ kind: "open", tag, attrs, selfClosing });
    }
  }

  if (lastIndex < source.length) {
    const text = source.slice(lastIndex);
    if (text.trim()) {
      tokens.push({ kind: "text", value: text });
    }
  }

  return tokens;
};

const buildTreeFromTemplate = (source: string): HostNode => {
  const fragment = createSlotNode();
  const stack: HostNode[] = [fragment];

  const tokens = tokenize(source);
  for (const tok of tokens) {
    switch (tok.kind) {
      case "open": {
        const node = createElement(tok.tag);
        for (const [k, v] of Object.entries(tok.attrs)) {
          setProperty(node, k, v);
        }
        insertNode(stack[stack.length - 1], node);
        if (!tok.selfClosing) {
          stack.push(node);
        }
        break;
      }
      case "close": {
        while (stack.length > 1) {
          const top = stack.pop()!;
          if (top.tag === tok.tag) break;
        }
        break;
      }
      case "text": {
        const textNode = createTextNode(tok.value);
        insertNode(stack[stack.length - 1], textNode);
        break;
      }
    }
  }

  return fragment.children.length === 1 ? fragment.children[0] : fragment;
};

export const template = (source: string) => {
  return () => buildTreeFromTemplate(source);
};

export const addEventListener = (node: HostNode, name: string, handler: EventHandler) => {
  if (!(node instanceof HostNode)) return;
  if (typeof handler !== "function") return;
  node.on(name, handler);
  notifyRuntimePropChange();
  return () => {
    node.off(name, handler);
  };
};

export const removeEventListener = (node: HostNode, name: string, handler: EventHandler) => {
  if (!(node instanceof HostNode)) return;
  node.off(name, handler);
  notifyRuntimePropChange();
};

export const delegateEvents = (_events: string[]) => {};
