// @ts-nocheck
import { type RendererAdapter, createSolidNativeHost } from "./index";
import { createSignal } from "solid-js";
import { App } from "./App";

type SolidTextApp = {
  host: ReturnType<typeof createSolidNativeHost>;
  setMessage: (value: string | ((prev: string) => string)) => void;
  dispose: () => void;
};

export const createSolidTextApp = (renderer: RendererAdapter): SolidTextApp => {
  const host = createSolidNativeHost(renderer);
  const [message, setMessage] = createSignal("Solid to Zig text");

  const dispose = host.render(App);

  host.flush();

  return {
    host,
    setMessage,
    dispose: dispose ?? (() => {}),
  };
};
