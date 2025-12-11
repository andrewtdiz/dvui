import { COMMAND_HEADER_SIZE, CommandFlag, Opcode, type Frame } from "./command-schema";

export type CommandBuffers = {
  headers: Uint8Array;
  payload: Uint8Array;
  count: number;
};

export class CommandEncoder {
  private readonly headers: ArrayBuffer;
  private readonly headerView: DataView;
  private readonly payload: Uint8Array;
  private readonly textEncoder = new TextEncoder();
  private commandCount = 0;
  private payloadOffset = 0;

  constructor(private readonly maxCommands = 256, private readonly maxPayloadBytes = 16_384) {
    this.headers = new ArrayBuffer(COMMAND_HEADER_SIZE * this.maxCommands);
    this.headerView = new DataView(this.headers);
    this.payload = new Uint8Array(this.maxPayloadBytes);
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
    if (encoded.length + this.payloadOffset > this.payload.byteLength) {
      throw new Error("Command payload buffer exhausted");
    }

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
    if (this.commandCount >= this.maxCommands) {
      throw new Error("Command header buffer exhausted");
    }

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
}
