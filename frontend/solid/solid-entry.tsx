// @ts-nocheck
import { type RendererAdapter, createSolidNativeHost } from "./index";
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
      <div class="flex flex-col gap-4 items-start justify-start bg-red-500 border border-red-500 w-60 h-60 p-3 rounded-md">
        {/* Demo: text-center alignment */}
        <p class="bg-blue-400 text-gray-100 rounded-sm px-2 py-1 text-center">Centered Text</p>
        
        {/* Demo: opacity-50 (semi-transparent) */}
        <p class="bg-green-500 text-white rounded-sm px-2 py-1 opacity-50">50% Opacity</p>
        
        {/* Demo: hidden (should NOT appear) */}
        <p class="bg-yellow-500 hidden">This is hidden!</p>
        
        {/* Demo: items-stretch makes this button full width */}
        <button
          class="bg-blue-400 text-gray-100 px-4 py-2 rounded"
          onClick={(payload: Uint8Array) => {
            const view = new DataView(payload.buffer);
            const nodeId = view.getUint32(0, true);
            console.log("[event demo] click payload nodeId=", nodeId);
          }}
        >
          Full Width Button
        </button>
        
        {/* Demo: text-right alignment */}
        <p class="bg-purple-500 text-white rounded-sm px-2 py-1 text-right">Right Aligned</p>
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
