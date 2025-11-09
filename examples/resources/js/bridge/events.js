export function installListenerBridge(eventManager, requestRender) {
  if (typeof requestRender !== "function") {
    throw new Error("requestRender callback required");
  }
  if (!eventManager) {
    throw new Error("eventManager missing");
  }

  globalThis.dvuiInvokeListener = function dvuiInvokeListener(listenerId) {
    const handled = eventManager.invokeListener(listenerId);
    if (handled) {
      requestRender();
    }
    return handled;
  };
}
