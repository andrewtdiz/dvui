import { createEffect } from "solid-js";
import { HostNode } from "./solid-host";
import { notifyRuntimePropChange } from "./runtime-bridge";

const asHostNode = (value: any): HostNode | undefined => {
  return value instanceof HostNode ? value : undefined;
};

export const createElement = (tag: string) => {
  return new HostNode(tag);
};

export const setProp = (node: HostNode, name: string, value: any) => {
  node.props[name] = value;
  notifyRuntimePropChange();
};

export const setAttribute = (node: HostNode, name: string, value: any) => {
  setProp(node, name, value);
};

export const createComponent = (Comp: (props: any) => any, props: any) => {
  return Comp(props);
};

const appendText = (parent: HostNode, text: string) => {
  if (parent.tag === "text") {
    parent.props.text = text;
    return;
  }
  const child = new HostNode("text");
  child.props.text = text;
  parent.add(child);
};

const clearChildren = (node: HostNode) => {
  for (const child of node.children) {
    child.parent = undefined;
  }
  node.children.length = 0;
};

const resolveValue = (input: any): any => {
  let resolved = input;
  while (typeof resolved === "function") {
    resolved = resolved();
  }
  return resolved;
};

const applyLeaf = (parent: HostNode, value: any): boolean => {
  if (value == null || value === true || value === false) return false;

  if (typeof value === "string" || typeof value === "number") {
    appendText(parent, String(value));
    return true;
  }

  const node = asHostNode(value);
  if (node) {
    parent.add(node);
    return true;
  }

  return false;
};

const applyInsertValue = (parent: HostNode, value: any) => {
  const resolved = resolveValue(value);
  clearChildren(parent);
  let applied = false;

  if (Array.isArray(resolved)) {
    for (const item of resolved) {
      applied = applyLeaf(parent, resolveValue(item)) || applied;
    }
  } else {
    applied = applyLeaf(parent, resolved);
  }

  if (!applied && parent.tag === "text") {
    parent.props.text = "";
  }

  notifyRuntimePropChange();
};

export const insert = (parent: HostNode, value: any) => {
  applyInsertValue(parent, value);
  if (typeof value === "function") {
    createEffect(() => applyInsertValue(parent, value));
  }
};

export const effect = (fn: (prev?: any) => any, initial?: any) => {
  // Run once immediately so static props apply even if createEffect is a no-op
  // (e.g. when the server build of solid-js is resolved). Reactive updates
  // still flow through the real effect when available.
  fn(initial);
  return createEffect(() => fn(initial));
};

type ParsedTemplate = {
  tag: string;
  attrs: Record<string, string>;
  textContent?: string;
};

const parseTemplate = (source: string): ParsedTemplate => {
  const tagMatch = source.match(/<\s*([a-zA-Z0-9:_-]+)([^>]*)>/);
  if (!tagMatch) return { tag: "text", attrs: {} };

  const [, rawTag, rawAttrs] = tagMatch;
  const attrs: Record<string, string> = {};
  const attrPattern = /([^\s=]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  let m: RegExpExecArray | null;
  while ((m = attrPattern.exec(rawAttrs)) !== null) {
    const name = m[1];
    const value = m[2] ?? m[3] ?? m[4] ?? "";
    attrs[name] = value;
  }

  const textMatch = source.match(new RegExp(`<${rawTag}[^>]*>([^<]*)`, "i"));
  return {
    tag: rawTag,
    attrs,
    textContent: textMatch?.[1],
  };
};

export const template = (source: string) => {
  const parsed = parseTemplate(source);
  const tag = parsed.tag || "text";
  return () => {
    const node = new HostNode(tag);
    for (const [key, val] of Object.entries(parsed.attrs)) {
      node.props[key] = val;
    }
    if (parsed.textContent && parsed.textContent.length > 0) {
      if (tag === "text") {
        node.props.text = parsed.textContent;
      } else {
        appendText(node, parsed.textContent);
      }
    }
    return node;
  };
};
