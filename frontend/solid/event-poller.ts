/**
 * Event Ring Buffer Poller
 * 
 * Polls the Zig event ring buffer after each frame and dispatches
 * events to registered Solid.js handlers.
 */

import type { HostNode } from "./solid-host";

/** Event kinds matching Zig EventKind enum */
export const EventKind = {
  click: 0,
  input: 1,
  focus: 2,
  blur: 3,
  mouseenter: 4,
  mouseleave: 5,
  keydown: 6,
  keyup: 7,
  change: 8,
  submit: 9,
} as const;

export type EventKindValue = (typeof EventKind)[keyof typeof EventKind];

/** Reverse lookup from kind value to name */
const eventKindToName: Record<number, string> = Object.fromEntries(
  Object.entries(EventKind).map(([name, value]) => [value, name])
);

/** Size of EventEntry struct in bytes (packed) */
const EVENT_ENTRY_SIZE = 12; // u8 + u8 + u32 + u32 + u16

/** Header struct layout */
export interface EventRingHeader {
  readHead: number;
  writeHead: number;
  capacity: number;
  detailCapacity: number;
}

/** Parsed event entry */
export interface EventEntry {
  kind: EventKindValue;
  nodeId: number;
  detailOffset: number;
  detailLen: number;
}

/**
 * Poll events from the shared ring buffer and dispatch to handlers.
 * 
 * @param headerPtr - Pointer to the header struct from getEventRingHeader
 * @param bufferPtr - Pointer to the event buffer from getEventRingBuffer  
 * @param detailPtr - Pointer to the detail buffer from getEventRingDetail
 * @param nodeIndex - Map of node IDs to HostNode instances
 * @param acknowledgeEvents - FFI function to update read head
 */
export function pollEvents(
  header: EventRingHeader,
  bufferView: DataView,
  detailBuffer: Uint8Array,
  nodeIndex: Map<number, HostNode>,
  acknowledgeEvents: (newReadHead: number) => void
): number {
  const { readHead, writeHead, capacity } = header;
  
  if (readHead === writeHead) {
    return 0; // No events pending
  }
  
  const decoder = new TextDecoder();
  let current = readHead;
  let dispatched = 0;
  
  while (current < writeHead) {
    const idx = current % capacity;
    const offset = idx * EVENT_ENTRY_SIZE;
    
    // Read packed EventEntry
    const kind = bufferView.getUint8(offset) as EventKindValue;
    // skip pad byte at offset + 1
    const nodeId = bufferView.getUint32(offset + 2, true);
    const detailOffset = bufferView.getUint32(offset + 6, true);
    const detailLen = bufferView.getUint16(offset + 10, true);
    
    const node = nodeIndex.get(nodeId);
    if (node) {
      const eventName = eventKindToName[kind] ?? "unknown";
      const handlers = node.listeners.get(eventName);
      
      if (handlers && handlers.size > 0) {
        // Read detail string if present
        let detail: string | undefined;
        if (detailLen > 0 && detailOffset + detailLen <= detailBuffer.length) {
          detail = decoder.decode(
            detailBuffer.subarray(detailOffset, detailOffset + detailLen)
          );
        }
        
        // Create payload with node ID (matches existing format)
        const payload = new Uint8Array(4 + (detail?.length ?? 0));
        const payloadView = new DataView(payload.buffer);
        payloadView.setUint32(0, nodeId, true);
        if (detail) {
          const encoder = new TextEncoder();
          payload.set(encoder.encode(detail), 4);
        }
        
        // Dispatch to all handlers
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
  
  // Acknowledge consumed events
  if (current !== readHead) {
    acknowledgeEvents(current);
  }
  
  return dispatched;
}

/**
 * Create a DataView over the event buffer from a raw pointer.
 */
export function createEventBufferView(
  ptr: number,
  capacity: number
): DataView {
  const byteLength = capacity * EVENT_ENTRY_SIZE;
  const buffer = new ArrayBuffer(byteLength);
  // Note: In actual FFI, this would use Bun.FFI.toArrayBuffer or similar
  return new DataView(buffer);
}

/**
 * Create a Uint8Array view over the detail buffer from a raw pointer.
 */
export function createDetailBufferView(
  ptr: number,
  capacity: number
): Uint8Array {
  // Note: In actual FFI, this would use Bun.FFI.toArrayBuffer or similar
  return new Uint8Array(capacity);
}
