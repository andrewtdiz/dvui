import { COMMAND_HEADER_SIZE, CommandFlag, Opcode, type Frame } from "./command-schema";

export type CommandBuffers = {
  headers: Uint8Array;
  payload: Uint8Array;
  count: number;
};

export class CommandEncoder {
  private headers: ArrayBuffer;
  private headerView: DataView;
  private payload: Uint8Array;
  private headerCapacity: number;
  private payloadCapacity: number;
  private readonly textEncoder = new TextEncoder();
  private commandCount = 0;
  private payloadOffset = 0;

  constructor(maxCommands = 256, maxPayloadBytes = 16_384) {
    this.headerCapacity = Math.max(1, maxCommands);
    this.payloadCapacity = Math.max(1, maxPayloadBytes);
    this.headers = new ArrayBuffer(COMMAND_HEADER_SIZE * this.headerCapacity);
    this.headerView = new DataView(this.headers);
    this.payload = new Uint8Array(this.payloadCapacity);
  }

  reset() {
    this.commandCount = 0;
    this.payloadOffset = 0;
  }

  pushQuad(nodeId: number, parentId: number, frame: Frame, rgba: number, flags: CommandFlag | number = 0) {
    this.writeHeader({
      opcode: Opcode.Quad,
      nodeId,
      parentId,
      frame,
      payloadOffset: 0,
      payloadLength: 0,
      flags,
      extra: rgba >>> 0,
    });
  }

  pushText(
    nodeId: number,
    parentId: number,
    frame: Frame,
    text: string,
    color?: number,
    flags: CommandFlag | number = 0
  ) {
    const encoded = this.textEncoder.encode(text);
    this.ensurePayloadCapacity(this.payloadOffset + encoded.length);

    const payloadOffset = this.payloadOffset;
    this.payload.set(encoded, payloadOffset);
    this.payloadOffset += encoded.length;

    this.writeHeader({
      opcode: Opcode.Text,
      nodeId,
      parentId,
      frame,
      payloadOffset,
      payloadLength: encoded.length,
      flags,
      extra: color ?? 0,
    });
  }

  finalize(): CommandBuffers {
    const headerBytes = this.commandCount * COMMAND_HEADER_SIZE;
    return {
      headers: new Uint8Array(this.headers, 0, headerBytes),
      payload: this.payload.subarray(0, this.payloadOffset),
      count: this.commandCount,
    };
  }

  private writeHeader(params: {
    opcode: Opcode;
    nodeId: number;
    parentId: number;
    frame: Frame;
    payloadOffset: number;
    payloadLength: number;
    flags?: number;
    extra: number;
  }) {
    this.ensureHeaderCapacity(this.commandCount + 1);

    const base = this.commandCount * COMMAND_HEADER_SIZE;
    this.headerView.setUint8(base, params.opcode);
    this.headerView.setUint8(base + 1, params.flags ?? 0);
    this.headerView.setUint16(base + 2, 0, true);
    this.headerView.setUint32(base + 4, params.nodeId >>> 0, true);
    this.headerView.setUint32(base + 8, params.parentId >>> 0, true);
    this.headerView.setFloat32(base + 12, params.frame.x, true);
    this.headerView.setFloat32(base + 16, params.frame.y, true);
    this.headerView.setFloat32(base + 20, params.frame.width, true);
    this.headerView.setFloat32(base + 24, params.frame.height, true);
    this.headerView.setUint32(base + 28, params.payloadOffset >>> 0, true);
    this.headerView.setUint32(base + 32, params.payloadLength >>> 0, true);
    this.headerView.setUint32(base + 36, params.extra >>> 0, true);

    this.commandCount += 1;
  }

  private ensureHeaderCapacity(requiredCommands: number) {
    if (requiredCommands <= this.headerCapacity) return;
    let next = this.headerCapacity;
    while (next < requiredCommands) {
      next = next > 0 ? next * 2 : 1;
    }
    const nextBuffer = new ArrayBuffer(COMMAND_HEADER_SIZE * next);
    const nextView = new DataView(nextBuffer);
    const used = this.commandCount * COMMAND_HEADER_SIZE;
    new Uint8Array(nextBuffer).set(new Uint8Array(this.headers, 0, used));
    this.headers = nextBuffer;
    this.headerView = nextView;
    this.headerCapacity = next;
  }

  private ensurePayloadCapacity(requiredBytes: number) {
    if (requiredBytes <= this.payloadCapacity) return;
    let next = this.payloadCapacity;
    while (next < requiredBytes) {
      next = next > 0 ? next * 2 : 1;
    }
    const nextPayload = new Uint8Array(next);
    nextPayload.set(this.payload.subarray(0, this.payloadOffset));
    this.payload = nextPayload;
    this.payloadCapacity = next;
  }
}
