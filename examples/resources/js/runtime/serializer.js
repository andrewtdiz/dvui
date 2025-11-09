import { parseClassNames } from "./styleParser.js";

export function serializeContainer(container, { eventManager } = {}) {
  const commands = [];
  const rootIds = [];

  if (!container || !Array.isArray(container.rootChildren)) {
    return { commands, rootIds };
  }

  for (const node of container.rootChildren) {
    const id = serializeNode(node, commands, eventManager);
    if (id) {
      rootIds.push(id);
    }
  }

  return { commands, rootIds };
}

export default serializeContainer;

function serializeNode(node, commands, eventManager) {
  if (!node) return null;

  const nodeId = String(node.id);
  if (node.text !== undefined) {
    commands.push({
      id: nodeId,
      type: "text-content",
      text: node.text,
    });
    return nodeId;
  }

  const childIds = [];
  let textContent = "";

  if (Array.isArray(node.children)) {
    for (const child of node.children) {
      if (child && typeof child.text === "string") {
        textContent += child.text;
      }
      const childId = serializeNode(child, commands, eventManager);
      if (childId) {
        childIds.push(childId);
      }
    }
  }

  const command = {
    id: nodeId,
    type: node.type || "unknown",
    children: childIds,
  };

  if (node.props && typeof node.props === "object") {
    const sanitized = sanitizeProps(node.props);
    if (sanitized) {
      command.props = sanitized;
    }
    attachStyle(command, node, eventManager);
    attachEventListeners(command, node, eventManager);
  }

  if (textContent.length > 0) {
    command.textContent = textContent;
  }

  commands.push(command);
  return nodeId;
}

function attachStyle(command, node, eventManager) {
  const className = node.props?.className;
  const componentState = eventManager?.getComponentState(node.id) ?? undefined;
  const style = parseClassNames(className, componentState);
  if (style) {
    command.style = style;
  }
}

function attachEventListeners(command, node, eventManager) {
  if (!eventManager) return;
  if (node.type === "button") {
    const listenerId = eventManager.registerListener(node.props?.onClick);
    if (listenerId) {
      command.onClickId = listenerId;
    }
  }
}

function sanitizeProps(props) {
  const result = {};
  for (const [key, value] of Object.entries(props)) {
    if (key === "children") continue;
    const type = typeof value;
    if (type === "string" || type === "number" || type === "boolean") {
      result[key] = value;
    }
  }
  return Object.keys(result).length > 0 ? result : null;
}
