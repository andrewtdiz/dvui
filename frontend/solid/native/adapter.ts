import { ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { CommandEncoder, type CommandBuffers } from "./encoder";
import {
  createCallbackBundle,
  loadNativeLibrary,
  type CallbackBundle,
  type NativeCallbacks,
  type NativeLibrary,
} from "./ffi";

const EVENT_KIND_TO_NAME: Record<number, string> = {
  0: "click",
  1: "input",
  2: "focus",
  3: "blur",
  4: "mouseenter",
  5: "mouseleave",
  6: "keydown",
  7: "keyup",
  8: "change",
  9: "submit",
  20: "scroll",
};

const EVENT_DECODER = new TextDecoder();

export type RendererCapabilities = {
  window: boolean;
};

export type RendererAdapter = {
  encoder: CommandEncoder;
  commit(commands: CommandEncoder | CommandBuffers): void;
  present(): void;
  resize(width: number, height: number): void;
  onEvent(handler?: NativeCallbacks["onEvent"]): void;
  close(): void;
  applyOps?(payload: Uint8Array): boolean;
  capabilities: RendererCapabilities;
  readonly disposed?: boolean;
  setText?(text: string): void;
  setSolidTree?(payload: Uint8Array): void;
  onLog?(handler?: NativeCallbacks["onLog"]): void;
};

export class NativeRenderer implements RendererAdapter {
  private readonly lib: NativeLibrary;
  private readonly callbacks: CallbackBundle;
  private readonly handle: Pointer;
  private readonly eventHandlers = new Set<NativeCallbacks["onEvent"]>();
  private readonly logHandlers = new Set<NativeCallbacks["onLog"]>();
  private readonly textEncoder = new TextEncoder();
  private callbackDepth = 0;
  private closeDeferred = false;
  private lastEventOverflow = 0;
  private lastDetailOverflow = 0;
  private headerMismatchLogged = false;
  readonly encoder: CommandEncoder;
  readonly capabilities: RendererCapabilities = { window: true };
  disposed = false;

  constructor(
    options: {
      callbacks?: NativeCallbacks;
      libPath?: string;
      maxCommands?: number;
      maxPayload?: number;
    } = {}
  ) {
    this.lib = loadNativeLibrary(options.libPath);
    if (options.callbacks?.onEvent) {
      this.eventHandlers.add(options.callbacks.onEvent);
    }
    if (options.callbacks?.onLog) {
      this.logHandlers.add(options.callbacks.onLog);
    }

    this.callbacks = createCallbackBundle({
      onEvent: (name, payload) =>
        this.enterCallback(() => {
          for (const handler of this.eventHandlers) {
            handler?.(name, payload);
          }
        }),
      onLog: (level, message) =>
        this.enterCallback(() => {
          for (const handler of this.logHandlers) {
            handler?.(level, message);
          }
        }),
    });
    this.encoder = new CommandEncoder(options.maxCommands, options.maxPayload);
    this.handle = this.lib.symbols.createRenderer(this.callbacks.log.ptr, this.callbacks.event.ptr);

    if (!this.handle) {
      throw new Error("Failed to create native renderer handle");
    }
  }

  commit(commands: CommandEncoder | CommandBuffers) {
    if (this.disposed) return;
    const buffers = commands instanceof CommandEncoder ? commands.finalize() : commands;
    const headersPtr = buffers.headers.byteLength > 0 ? ptr(buffers.headers) : 0;
    const payloadPtr = buffers.payload.byteLength > 0 ? ptr(buffers.payload) : 0;
    this.lib.symbols.commitCommands(
      this.handle,
      headersPtr,
      buffers.headers.byteLength,
      payloadPtr,
      buffers.payload.byteLength,
      buffers.count
    );
  }

  present() {
    if (this.disposed) return;
    this.lib.symbols.presentRenderer(this.handle);
  }

  resize(width: number, height: number) {
    if (this.disposed) return;
    this.lib.symbols.resizeRenderer(this.handle, width, height);
  }

  setText(text: string) {
    if (this.disposed) return;
    const encoded = this.textEncoder.encode(text);
    this.lib.symbols.setRendererText(this.handle, ptr(encoded), encoded.byteLength);
  }

  setSolidTree(payload: Uint8Array) {
    if (this.disposed) return;
    const dataPtr = payload.byteLength > 0 ? ptr(payload) : 0;
    this.lib.symbols.setRendererSolidTree(this.handle, dataPtr, payload.byteLength);
  }

  applyOps(payload: Uint8Array): boolean {
    if (this.disposed) return false;
    const dataPtr = payload.byteLength > 0 ? ptr(payload) : 0;
    return this.lib.symbols.applyRendererSolidOps(this.handle, dataPtr, payload.byteLength);
  }

  onEvent(handler?: NativeCallbacks["onEvent"]) {
    if (!handler) {
      this.eventHandlers.clear();
      return;
    }
    this.eventHandlers.add(handler);
  }

  onLog(handler?: NativeCallbacks["onLog"]) {
    if (!handler) {
      this.logHandlers.clear();
      return;
    }
    this.logHandlers.add(handler);
  }

  close() {
    if (this.disposed) return;
    this.lib.symbols.destroyRenderer(this.handle);
    this.disposed = true;
    this.closeDeferred = true;
    this.flushDeferredClose();
  }

  pollEvents(nodeIndex: Map<number, import("../host/node").HostNode>): number {
    if (this.disposed) return 0;

    const expectedHeaderSize = 24;
    const minimumHeaderSize = 16;
    const headerBuffer = new Uint8Array(expectedHeaderSize);
    const copied = Number(this.lib.symbols.getEventRingHeader(this.handle, headerBuffer, headerBuffer.length));
    if (copied === 0) return 0;
    if (copied !== expectedHeaderSize && !this.headerMismatchLogged) {
      console.warn(`[native] Event ring header size mismatch (expected ${expectedHeaderSize}, got ${copied}).`);
      this.headerMismatchLogged = true;
    }
    if (copied < minimumHeaderSize) return 0;

    const headerView = new DataView(headerBuffer.buffer, 0, copied);
    const readHead = headerView.getUint32(0, true);
    const writeHead = headerView.getUint32(4, true);
    const capacity = headerView.getUint32(8, true);
    const detailCapacity = headerView.getUint32(12, true);
    const hasDroppedCounters = copied >= expectedHeaderSize;
    const droppedEvents = hasDroppedCounters ? headerView.getUint32(16, true) : 0;
    const droppedDetails = hasDroppedCounters ? headerView.getUint32(20, true) : 0;

    if (hasDroppedCounters && (droppedEvents !== this.lastEventOverflow || droppedDetails !== this.lastDetailOverflow)) {
      const eventDelta =
        droppedEvents >= this.lastEventOverflow ? droppedEvents - this.lastEventOverflow : droppedEvents;
      const detailDelta =
        droppedDetails >= this.lastDetailOverflow ? droppedDetails - this.lastDetailOverflow : droppedDetails;
      if (eventDelta > 0 || detailDelta > 0) {
        const parts: string[] = [];
        if (eventDelta > 0) parts.push(`${eventDelta} events`);
        if (detailDelta > 0) parts.push(`${detailDelta} detail payloads`);
        console.warn(`[native] Event ring overflow: dropped ${parts.join(" and ")}.`);
      }
      this.lastEventOverflow = droppedEvents;
      this.lastDetailOverflow = droppedDetails;
    }

    if (readHead === writeHead || capacity === 0) return 0;

    const bufferPtr = this.lib.symbols.getEventRingBuffer(this.handle);
    const detailPtr = this.lib.symbols.getEventRingDetail(this.handle);
    if (!bufferPtr) return 0;

    const EVENT_ENTRY_SIZE = 16;
    const bufferView = new DataView(toArrayBuffer(bufferPtr, 0, capacity * EVENT_ENTRY_SIZE));
    const detailBuffer = detailPtr ? new Uint8Array(toArrayBuffer(detailPtr, 0, detailCapacity)) : new Uint8Array(0);

    let current = readHead;
    let dispatched = 0;

    while (current < writeHead) {
      const idx = current % capacity;
      const offset = idx * EVENT_ENTRY_SIZE;

      const kind = bufferView.getUint8(offset);
      const nodeId = bufferView.getUint32(offset + 4, true);
      const detailOffset = bufferView.getUint32(offset + 8, true);
      const detailLen = bufferView.getUint16(offset + 12, true);

      const eventName = EVENT_KIND_TO_NAME[kind] ?? "unknown";
      const node = nodeIndex.get(nodeId);

      if (node) {
        const handlers = node.listeners.get(eventName);
        if (handlers && handlers.size > 0) {
          let detail: string | undefined;
          if (detailLen > 0 && detailOffset + detailLen <= detailBuffer.length) {
            detail = EVENT_DECODER.decode(detailBuffer.subarray(detailOffset, detailOffset + detailLen));
          }

          const isKeyEvent = eventName === "keydown" || eventName === "keyup";
          const keyValue = isKeyEvent ? detail : undefined;

          // Construct a mock event object that SolidJS expects
          // We include 'target' and 'currentTarget' which point to an object with properties
          // like 'value' for input elements.
          const eventObj = {
            type: eventName,
            target: { id: nodeId, value: detail, tagName: node.tag },
            currentTarget: { id: nodeId, value: detail, tagName: node.tag },
            detail: detail,
            key: keyValue,
            // Fallback for handlers that still expect Uint8Array for some reason
            _nativePayload: new Uint8Array([nodeId & 0xff, (nodeId >> 8) & 0xff, (nodeId >> 16) & 0xff, (nodeId >> 24) & 0xff]),
          };

          // console.log(`[JS Event] Dispatching ${eventName} to node ${nodeId} (detail=${detail})`);

          for (const handler of handlers) {
            try {
              // Cast to any because our InternalEventHandler type in host might be too strict
              (handler as any)(eventObj);
            } catch (err) {
              console.error(`Event handler error for ${eventName} on node ${nodeId}:`, err);
            }
          }
          dispatched++;
        } else {
          // console.warn(`[JS Event] Received ${eventName} for node ${nodeId} but no JS listeners found`);
        }
      } else {
        // console.warn(`[JS Event] Received ${eventName} for unknown node ${nodeId}`);
      }
      current++;
    }

    if (current !== readHead) {
      this.lib.symbols.acknowledgeEvents(this.handle, current);
    }

    return dispatched;
  }

  private enterCallback<T>(fn: () => T): T {
    this.callbackDepth += 1;
    try {
      return fn();
    } finally {
      this.callbackDepth -= 1;
      this.flushDeferredClose();
    }
  }

  private flushDeferredClose() {
    if (!this.closeDeferred || this.callbackDepth > 0) return;
    this.closeDeferred = false;
    this.callbacks.log.close();
    this.callbacks.event.close();
  }
}
