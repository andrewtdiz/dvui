const DEFAULT_COMPONENT_STATE = Object.freeze({});

export class EventManager {
  constructor() {
    this.nextListenerId = 1;
    this.listenerRegistry = new Map();
    this.componentState = new Map();
  }

  reset() {
    this.nextListenerId = 1;
    this.listenerRegistry.clear();
  }

  registerListener(handler) {
    if (typeof handler !== "function") {
      return null;
    }
    const id = `listener:${this.nextListenerId++}`;
    this.listenerRegistry.set(id, handler);
    return id;
  }

  invokeListener(listenerId) {
    const handler = this.listenerRegistry.get(listenerId);
    if (typeof handler !== "function") {
      console.warn("Missing listener:", listenerId);
      return false;
    }
    try {
      handler();
    } catch (error) {
      console.error("Listener threw:", error);
    }
    return true;
  }

  getComponentState(componentId) {
    if (componentId == null) {
      return DEFAULT_COMPONENT_STATE;
    }
    return this.componentState.get(componentId) ?? DEFAULT_COMPONENT_STATE;
  }

  updateComponentState(componentId, nextState) {
    if (componentId == null || nextState == null) {
      return;
    }
    const currentState = this.componentState.get(componentId) ?? {};
    this.componentState.set(componentId, { ...currentState, ...nextState });
  }
}

export default EventManager;
