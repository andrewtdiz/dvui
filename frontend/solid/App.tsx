// @ts-nocheck
import { createEffect, createSignal } from "solid-js";
import { getElapsedSeconds, getDeltaSeconds } from "./state/time";

export const App = () => {
  const [count, setCount] = createSignal(0);
  const [x, setX] = createSignal(0);
  const [y, setY] = createSignal(0);
  const elapsed = getElapsedSeconds;
  const delta = getDeltaSeconds;

  const radius = 50;
  const center_x = 200;
  const center_y = 150;
  const speed = 3.0; // radians per second

  createEffect(() => {
    const t = elapsed();
    const angle = t * speed;
    setX(center_x + Math.cos(angle) * radius);
    setY(center_y + Math.sin(angle) * radius);
  });

  return (
    <div class="w-full h-full bg-neutral-900">

      <div class="absolute top-15 left-15 flex flex-col items-start justify-start border-2 border-red-700 gap-3 bg-red-500 w-64 h-64 p-3 rounded-md">
      <p class="absolute top-0 right-0 bg-blue-400 text-gray-100 px-2 py-1 text-center">
          Centered Text
        </p>

        <button
          class="bg-blue-400 text-gray-100 px-4 py-2 rounded"
          onClick={(payload: Uint8Array) => {
            const view = new DataView(payload.buffer);
            const nodeId = view.getUint32(0, true);
            console.log("[event demo] click payload nodeId=", nodeId);
            setCount((prev) => prev + 1);
          }}
        >
          {count()}
        </button>

        <div class="w-32 h-32 bg-neutral-800 border border-white rounded-sm">
          <div class="absolute top-6 left-6 w-20 h-20 bg-blue-500 z-20 flex items-center justify-center text-white text-sm rounded-sm">
            <p>z-20</p>
          </div>
          <div class={`absolute top-2 left-2 w-20 h-20 bg-green-400 z-${count()}`}>
            <p>z-0</p>
          </div>
        </div>

        {/* clipping demo: yellow child should be cut off by parent */}
        <div class="w-32 h-32 bg-neutral-800 border border-white overflow-hidden rounded-sm relative">
          <div class="absolute top-0 left-0 w-48 h-48 bg-yellow-400"></div>
          <p class="absolute bottom-1 right-1 text-black text-xs bg-white px-1 rounded-sm">
            clipped
          </p>
        </div>

        <Show when={(count() > 0) && (count() < 10)}>
          <p class="bg-purple-500 text-white rounded-sm">
            Right {count()}
          </p>
        </Show>
        {(count() > 0) && (count() < 10) && (
          <p class="bg-purple-500 text-white rounded-sm">
            Right {count()}
          </p>
        )}

        <p class="bg-purple-500 text-white rounded-sm">
          Right {count()}
        </p>
      </div>
    </div>
  );
};
