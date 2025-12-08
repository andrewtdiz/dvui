import { transformAsync } from "@babel/core";
import ts from "@babel/preset-typescript";
import solid from "babel-preset-solid";
import { type BunPlugin } from "bun";

// Transforms TS/TSX with Solid JSX into our custom runtime (solid/runtime.ts).
export const solidTransformPlugin: BunPlugin = {
  name: "solid-transform",
  setup(build) {
    build.onLoad({ filter: /\.(t|j)sx$/ }, async (args) => {
      const code = await Bun.file(args.path).text();
      const result = await transformAsync(code, {
        filename: args.path,
        presets: [
          [
            solid,
            {
              generate: "dom",
              moduleName: "#solid-runtime",
            },
          ],
          [ts],
        ],
      });

      return {
        contents: result?.code ?? "",
        loader: "js",
      };
    });
  },
};

export default solidTransformPlugin;
