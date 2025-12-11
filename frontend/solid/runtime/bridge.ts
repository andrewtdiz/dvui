import type { HostNode } from "../host/node";

export type RuntimeHostOps = {
  createElement: (tag: string) => HostNode;
  createTextNode: (value: string | number) => HostNode;
  createSlotNode?: () => HostNode;
  replaceText?: (node: HostNode, value: string) => void;
  insertNode?: (parent: HostNode, node: HostNode, anchor?: HostNode) => HostNode;
  removeNode?: (parent: HostNode, node: HostNode) => void;
  setProperty?: (node: HostNode, name: string, value: unknown, prev?: unknown) => void;
  insert?: (parent: HostNode, value: any, marker?: HostNode | null) => unknown;
  spread?: (node: HostNode, props: any, skipChildren?: boolean) => void;
};

type Bridge = {
  scheduleFlush?: () => void;
  registerNode?: (node: HostNode) => void;
  hostOps?: RuntimeHostOps;
};

const bridge: Bridge = {};

export const registerRuntimeBridge = (
  scheduleFlush: () => void,
  registerNode: (node: HostNode) => void,
  hostOps?: RuntimeHostOps
) => {
  bridge.scheduleFlush = scheduleFlush;
  bridge.registerNode = registerNode;
  bridge.hostOps = hostOps;
};

export const notifyRuntimePropChange = () => {
  bridge.scheduleFlush?.();
};

export const registerRuntimeNode = (node: HostNode) => {
  bridge.registerNode?.(node);
};

export const getRuntimeHostOps = () => bridge.hostOps;
