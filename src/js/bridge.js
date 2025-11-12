const DEFAULT_TARGET = "#root";

function resolveTarget(selector) {
  if (typeof selector === "string" && selector.length > 0) {
    return document.querySelector(selector);
  }
  if (selector instanceof Element) {
    return selector;
  }
  return document.querySelector(DEFAULT_TARGET) ?? document.body;
}

function baseEventInit(eventLike) {
  return {
    bubbles: true,
    cancelable: true,
    clientX: eventLike.clientX ?? 0,
    clientY: eventLike.clientY ?? 0,
    movementX: eventLike.movementX ?? 0,
    movementY: eventLike.movementY ?? 0,
    deltaX: eventLike.deltaX ?? 0,
    deltaY: eventLike.deltaY ?? 0,
    button: eventLike.button ?? 0,
    pointerId: eventLike.pointerId ?? 0,
    pointerType: eventLike.pointerType ?? "mouse",
    key: eventLike.key ?? "",
    code: eventLike.code ?? "",
    repeat: Boolean(eventLike.repeat),
    shiftKey: Boolean(eventLike.shiftKey),
    ctrlKey: Boolean(eventLike.ctrlKey),
    altKey: Boolean(eventLike.altKey),
    metaKey: Boolean(eventLike.metaKey),
    data: eventLike.data ?? null,
    detail: eventLike.detail ?? null,
  };
}

function createDomEvent(type, init, fallbackDetail) {
  try {
    switch (type) {
      case "mousedown":
      case "mouseup":
      case "mousemove":
      case "click":
        return new MouseEvent(type, init);
      case "wheel":
        return new WheelEvent("wheel", init);
      case "pointerdown":
      case "pointerup":
      case "pointermove":
        return new PointerEvent(type, init);
      case "keydown":
      case "keyup":
        return new KeyboardEvent(type, init);
      case "beforeinput":
        return new InputEvent("beforeinput", init);
      case "focus":
        return new FocusEvent("focus", init);
      default:
        return new CustomEvent(type, {
          bubbles: true,
          cancelable: true,
          detail: fallbackDetail,
        });
    }
  } catch (err) {
    console.warn("Falling back to document.createEvent for", type, err);
    const legacy = document.createEvent("Event");
    legacy.initEvent(type, true, true);
    Object.assign(legacy, init);
    if (fallbackDetail !== undefined) {
      legacy.detail = fallbackDetail;
    }
    return legacy;
  }
}

function dispatchNativeEvent(eventLike) {
  if (!eventLike || typeof eventLike.type !== "string") return;
  const target = resolveTarget(eventLike.target ?? dvui.targetSelector);
  if (!target) return;

  const init = baseEventInit(eventLike);
  const domEvent = createDomEvent(eventLike.type, init, eventLike.detail ?? eventLike);
  target.dispatchEvent(domEvent);
}

function postToHost(message) {
  if (dvui.host?.postMessage) {
    dvui.host.postMessage(message);
    return;
  }
  if (window.chrome?.webview?.postMessage) {
    window.chrome.webview.postMessage(JSON.parse(message));
    return;
  }
  if (window.external?.invoke) {
    window.external.invoke(message);
    return;
  }
  dvui.pendingMessages.push(message);
  console.warn("DVUI native bridge missing; command queued", message);
}

const dvui = {
  host: null,
  pendingMessages: [],
  targetSelector: DEFAULT_TARGET,

  attachHost(host) {
    this.host = host;
  },

  setTargetSelector(selector) {
    this.targetSelector = selector || DEFAULT_TARGET;
  },

  dispatchNativeEvent,

  native: {
    performAction(actionName, payload = {}) {
      if (!actionName) {
        console.warn("dvui.native.performAction called without an action name");
        return;
      }
      const envelope = { action: actionName, payload };
      postToHost(JSON.stringify(envelope));
    },
  },

  flushPendingActions() {
    const copy = this.pendingMessages.slice();
    this.pendingMessages.length = 0;
    return copy;
  },

  test(message = "native-bridge-online") {
    const payload = typeof message === "string" ? message : JSON.stringify(message);
    console.info(`[dvui] test from Zig: ${payload}`);
    return payload;
  },
};

Object.defineProperty(window, "dvui", {
  configurable: false,
  enumerable: false,
  writable: false,
  value: dvui,
});

export default dvui;
