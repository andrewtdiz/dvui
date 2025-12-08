export type Frame = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export enum Opcode {
  Quad = 1,
  Text = 2,
}

export enum CommandFlag {
  Absolute = 1,
}

// Bytes per command header in the encoded command buffer.
export const COMMAND_HEADER_SIZE = 40;

// Bytes used to store the command count prefix.
export const COMMAND_COUNT_BYTES = 4;
