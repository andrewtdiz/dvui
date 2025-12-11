import type { HostNode } from "../host/node";

type Bridge = {
  scheduleFlush?: () => void;
  registerNode?: (node: HostNode) => void;
};

const bridge: Bridge = {};

export const registerRuntimeBridge = (scheduleFlush: () => void, registerNode: (node: HostNode) => void) => {
  bridge.scheduleFlush = scheduleFlush;
  bridge.registerNode = registerNode;
};

export const notifyRuntimePropChange = () => {
  bridge.scheduleFlush?.();
};

export const registerRuntimeNode = (node: HostNode) => {
  bridge.registerNode?.(node);
};
