/**
 * SolidJS Universal Renderer Runtime
 *
 * This module provides the runtime functions that SolidJS's universal mode expects.
 * When using `generate: "universal"` in babel-preset-solid, the compiled JSX
 * calls these functions instead of DOM-specific ones.
 */

import { createEffect } from "solid-js";
import { HostNode, type EventHandler } from "../host/node";
import { notifyRuntimePropChange, registerRuntimeNode } from "./bridge";

export const createElement = (tag: string): HostNode => {
  const node = new HostNode(tag);
  registerRuntimeNode(node);
  return node;
};

export const createTextNode = (value: string | number): HostNode => {
  const node = new HostNode("text");
  node.props.text = typeof value === "number" ? `${value}` : value;
  registerRuntimeNode(node);
  return node;
};

export const createSlotNode = (): HostNode => {
  const node = new HostNode("slot");
  registerRuntimeNode(node);
  return node;
};

export const isTextNode = (node: HostNode): boolean => {
  return node.tag === "text";
};

export const replaceText = (node: HostNode, value: string): void => {
  if (node.tag === "text") {
    node.props.text = value;
    notifyRuntimePropChange();
  }
};

export const insertNode = (parent: HostNode, node: HostNode, anchor?: HostNode): HostNode => {
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
    const textNode = new HostNode("text");
    textNode.props.text = String(value);
    parent.add(textNode);
    return true;
  }

  if (value instanceof HostNode) {
    parent.add(value);
    return true;
  }

  return false;
};

const clearChildren = (node: HostNode) => {
  for (const child of node.children) {
    child.parent = undefined;
  }
  node.children.length = 0;
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
  const fragment = new HostNode("slot");
  const stack: HostNode[] = [fragment];

  const tokens = tokenize(source);
  for (const tok of tokens) {
    switch (tok.kind) {
      case "open": {
        const node = new HostNode(tok.tag);
        for (const [k, v] of Object.entries(tok.attrs)) {
          node.props[k] = v;
        }
        stack[stack.length - 1].add(node);
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
        const textNode = new HostNode("text");
        textNode.props.text = tok.value;
        stack[stack.length - 1].add(textNode);
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
