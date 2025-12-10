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

// Minimal host-only spread helper used by compiled templates.
export const spread = (node: HostNode, props: any) => {
  if (!props) return node;
  for (const [k, v] of Object.entries(props)) {
    setProp(node, k, v);
  }
  return node;
};

// mergeProps helper: last one wins, objects are shallow-merged.
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
  | {
      kind: "open";
      tag: string;
      attrs: Record<string, string>;
      selfClosing: boolean;
    }
  | { kind: "close"; tag: string }
  | { kind: "text"; value: string };

const tokenize = (source: string): Token[] => {
  const tokens: Token[] = [];
  const re = /<\/?[A-Za-z0-9:_-]+(?:\s+[^>]*?)?>|[^<]+/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) !== null) {
    const raw = m[0];
    if (raw.startsWith("</")) {
      const tag = raw.slice(2, -1).trim();
      tokens.push({ kind: "close", tag });
      continue;
    }
    if (raw.startsWith("<")) {
      const selfClosing = raw.endsWith("/>");
      const inner = raw.slice(1, selfClosing ? -2 : -1).trim();
      const [tag, ...rest] = inner.split(/\s+/);
      const attrString = inner.slice(tag.length);
      const attrs: Record<string, string> = {};
      const attrPattern = /([^\s=]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
      let ma: RegExpExecArray | null;
      while ((ma = attrPattern.exec(attrString)) !== null) {
        const name = ma[1];
        const value = ma[2] ?? ma[3] ?? ma[4] ?? "";
        attrs[name] = value;
      }
      tokens.push({ kind: "open", tag, attrs, selfClosing });
      continue;
    }
    const text = raw;
    if (text.length > 0) {
      tokens.push({ kind: "text", value: text });
    }
  }
  return tokens;
};

const buildTreeFromTemplate = (source: string): HostNode => {
  const fragment = new HostNode("slot"); // acts like a fragment/root
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
        // pop until matching tag or root
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
