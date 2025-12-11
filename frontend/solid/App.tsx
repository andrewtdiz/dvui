// @ts-nocheck
import { createSignal } from "solid-js";
import { getElapsedSeconds, getDeltaSeconds } from "./state/time";

export const App = () => {
  const [count, setCount] = createSignal(0);
  const elapsed = getElapsedSeconds;
  const delta = getDeltaSeconds;

  return (
    <div class="relative w-full h-full bg-gray-500">
      <div class="absolute bottom-0 right-0 flex flex-col items-start justify-start gap-3 bg-red-500 border border-red-500 w-64 h-64 p-3 rounded-md">
        <p class="bg-blue-400 text-gray-100 rounded-sm px-2 py-1 text-center">
          Centered Text
        </p>

        <p class="bg-green-500 text-white">Does render on the UI</p>
        <p class="text-white">Doesnt render on the UI</p>

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
