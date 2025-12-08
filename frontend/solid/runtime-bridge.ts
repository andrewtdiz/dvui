type Bridge = {
  scheduleFlush?: () => void;
};

const bridge: Bridge = {};

export const registerRuntimeBridge = (scheduleFlush: () => void) => {
  bridge.scheduleFlush = scheduleFlush;
};

export const notifyRuntimePropChange = () => {
  bridge.scheduleFlush?.();
};
