import { type RendererAdapter, CommandEncoder, type CommandBuffers } from "../index";
import { createCoreSession, BackendKind } from "./dvui-core";
import { ptr } from "bun:ffi";

type EventHandler = (name: string, payload: Uint8Array) => void;

export class CoreRenderer implements RendererAdapter {
  readonly encoder: CommandEncoder;
  readonly capabilities = { window: true };
  disposed = false;

  private readonly core = createCoreSession({ backend: BackendKind.raylib, width: 800, height: 450, vsync: true, title: "dvui core" });
  private pending?: CommandBuffers;
  private readonly eventHandlers = new Set<EventHandler>();

  constructor(maxCommands = 512, maxPayload = 64_000) {
    this.encoder = new CommandEncoder(maxCommands, maxPayload);
  }

  commit(commands: CommandEncoder | CommandBuffers) {
    if (this.disposed) return;
    this.pending = commands instanceof CommandEncoder ? commands.finalize() : commands;
  }

  present() {
    if (this.disposed) return;
    // Begin frame, commit any pending commands, end frame.
    this.core.beginFrame();
    if (this.pending) {
      const { headers, payload, count } = this.pending;
      this.core.commit(headers, payload, count);
      this.pending = undefined;
    }
    this.core.endFrame();
  }

  resize(_width: number, _height: number) {
    // No-op for now; raylib path owns window sizing.
  }

  onEvent(handler?: EventHandler) {
    if (!handler) {
      this.eventHandlers.clear();
      return;
    }
    this.eventHandlers.add(handler);
  }

  close() {
    if (this.disposed) return;
    this.core.deinit();
    this.disposed = true;
  }
}




