import { type RendererAdapter } from "./native-renderer";
import { createSolidNativeHost } from "./solid-host";
import { TextDisplay } from "./components/TextDisplay";
import { createSignal } from "solid-js";
import { rgba } from "./color";

type SolidTextApp = {
  host: ReturnType<typeof createSolidNativeHost>;
  setMessage: (value: string | ((prev: string) => string)) => void;
  dispose: () => void;
};

export const createSolidTextApp = (renderer: RendererAdapter): SolidTextApp => {
  const host = createSolidNativeHost(renderer);
  const [message, setMessage] = createSignal("Solid to Zig text");

  const screen = { w: 800, h: 450 };
  const container = { w: 360, h: 200 };
  const containerPos = {
    x: (screen.w - container.w) / 2,
    y: (screen.h - container.h) / 2,
  };

  const dispose = host.render(() => (
    <div
      class="absolute bg-white"
      x={containerPos.x}
      y={containerPos.y}
      width={container.w}
      height={container.h}
      color={rgba(59, 130, 246, 255)}
    />
  ));

  host.flush();

  return {
    host,
    setMessage,
    dispose: dispose ?? (() => {}),
  };
};
