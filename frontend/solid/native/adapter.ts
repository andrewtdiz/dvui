import { ptr, toArrayBuffer, type Pointer } from "bun:ffi";
import { CommandEncoder, type CommandBuffers } from "./encoder";
import {
  createCallbackBundle,
  loadNativeLibrary,
  type CallbackBundle,
  type NativeCallbacks,
  type NativeLibrary,
} from "./ffi";

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

    const headerBuffer = new Uint8Array(16);
    const copied = this.lib.symbols.getEventRingHeader(this.handle, headerBuffer, headerBuffer.length);
    if (Number(copied) !== headerBuffer.length) return 0;

    const headerView = new DataView(headerBuffer.buffer);
    const readHead = headerView.getUint32(0, true);
    const writeHead = headerView.getUint32(4, true);
    const capacity = headerView.getUint32(8, true);
    const detailCapacity = headerView.getUint32(12, true);

    if (readHead === writeHead || capacity === 0) return 0;

    const bufferPtr = this.lib.symbols.getEventRingBuffer(this.handle);
    const detailPtr = this.lib.symbols.getEventRingDetail(this.handle);
    if (!bufferPtr) return 0;

    const EVENT_ENTRY_SIZE = 16;
    const bufferView = new DataView(toArrayBuffer(bufferPtr, 0, capacity * EVENT_ENTRY_SIZE));
    const detailBuffer = detailPtr ? new Uint8Array(toArrayBuffer(detailPtr, 0, detailCapacity)) : new Uint8Array(0);

    const decoder = new TextDecoder();
    const eventKindToName: Record<number, string> = {
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
    };

    let current = readHead;
    let dispatched = 0;

    while (current < writeHead) {
      const idx = current % capacity;
      const offset = idx * EVENT_ENTRY_SIZE;

      const kind = bufferView.getUint8(offset);
      const nodeId = bufferView.getUint32(offset + 4, true);
      const detailOffset = bufferView.getUint32(offset + 8, true);
      const detailLen = bufferView.getUint16(offset + 12, true);

      const eventName = eventKindToName[kind] ?? "unknown";
      const node = nodeIndex.get(nodeId);

      if (node) {
        const handlers = node.listeners.get(eventName);
        if (handlers && handlers.size > 0) {
          let detail: string | undefined;
          if (detailLen > 0 && detailOffset + detailLen <= detailBuffer.length) {
            detail = decoder.decode(detailBuffer.subarray(detailOffset, detailOffset + detailLen));
          }

          const payload = new Uint8Array(4);
          new DataView(payload.buffer).setUint32(0, nodeId, true);

          for (const handler of handlers) {
            try {
              handler(payload);
            } catch (err) {
              console.error(`Event handler error for ${eventName} on node ${nodeId}:`, err);
            }
          }
          dispatched++;
        }
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
