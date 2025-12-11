// @ts-nocheck
import { type RendererAdapter } from "./native-renderer";
import { createSolidNativeHost } from "./solid-host";
import { TextDisplay } from "./components/TextDisplay";
import { createSignal } from "solid-js";

type SolidTextApp = {
  host: ReturnType<typeof createSolidNativeHost>;
  setMessage: (value: string | ((prev: string) => string)) => void;
  dispose: () => void;
};

export const createSolidTextApp = (renderer: RendererAdapter): SolidTextApp => {
  const host = createSolidNativeHost(renderer);
  const [message, setMessage] = createSignal("Solid to Zig text");

  const screen = { w: 800, h: 450 };
  const flexBox = { size: 240 };
  const anchorPad = 24;
  const textRowPad = 16;
  const textRowHeight = 28;
  const textSegmentWidth = (flexBox.size - textRowPad * 2) / 3;

  const dispose = host.render(() => (
    <div class="flex justify-center items-center w-full h-full bg-gray-500">
      <div class="flex items-center justify-start bg-red-500 border border-red-500 w-60 h-60 p-1 rounded-md">
        <p class="bg-blue-400 text-gray-100 rounded-sm">Left anchor</p>
      </div>
    </div>
  ));

  host.flush();

  return {
    host,
    setMessage,
    dispose: dispose ?? (() => {}),
  };
};
