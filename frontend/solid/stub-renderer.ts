import { CommandEncoder, type CommandBuffers, type RendererAdapter, type RendererCapabilities } from "./native-renderer";

type CommitRecord = {
  headers: Uint8Array;
  payload: Uint8Array;
  count: number;
};

export class StubRenderer implements RendererAdapter {
  readonly encoder: CommandEncoder;
  readonly capabilities: RendererCapabilities = { window: false };
  disposed = false;

  commits: CommitRecord[] = [];

  constructor(options: { maxCommands?: number; maxPayload?: number } = {}) {
    this.encoder = new CommandEncoder(options.maxCommands, options.maxPayload);
  }

  commit(commands: CommandEncoder | CommandBuffers) {
    if (this.disposed) return;
    const buffers = commands instanceof CommandEncoder ? commands.finalize() : commands;
    this.commits.push({ headers: buffers.headers, payload: buffers.payload, count: buffers.count });
  }

  present() {
    // no-op
  }

  resize() {
    // no-op
  }

  onEvent() {
    // no-op
  }

  setText() {
    // no-op
  }

  close() {
    this.disposed = true;
    this.commits.length = 0;
  }
}
