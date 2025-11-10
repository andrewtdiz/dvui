import { transformAsync } from "@babel/core"
// @ts-expect-error - Types not important.
import ts from "@babel/preset-typescript"
// @ts-expect-error - Types not important.
import solid from "babel-preset-solid"
import { type BunPlugin } from "bun"
import path from "node:path"
import { fileURLToPath } from "node:url"

const runtimeSpecifier = "dvui-solid-runtime"
const currentDir = path.dirname(fileURLToPath(import.meta.url))
const projectRoot = path.resolve(currentDir, "..")
const runtimePath = path.join(projectRoot, "solid/universal-runtime.js")

const solidTransformPlugin: BunPlugin = {
  name: "bun-plugin-solid",
  setup: (build) => {
    build.onResolve({ filter: new RegExp(`^${runtimeSpecifier}$`) }, () => {
      return { path: runtimePath }
    })
    build.onLoad({ filter: /\/node_modules\/solid-js\/dist\/server\.js$/ }, async (args) => {
      const path = args.path.replace("server.js", "solid.js")
      const file = Bun.file(path)
      const code = await file.text()
      return { contents: code, loader: "js" }
    })
    build.onLoad({ filter: /\/node_modules\/solid-js\/store\/dist\/server\.js$/ }, async (args) => {
      const path = args.path.replace("server.js", "store.js")
      const file = Bun.file(path)
      const code = await file.text()
      return { contents: code, loader: "js" }
    })
    build.onLoad({ filter: /\.(js|ts)x$/ }, async (args) => {
      const file = Bun.file(args.path)
      const code = await file.text()
      const transforms = await transformAsync(code, {
        filename: args.path,
        // env: {
        //   development: {
        //     plugins: [["solid-refresh/babel", { "bundler": "esm" }]],
        //   },
        // },
        // plugins: [["solid-refresh/babel", { bundler: "esm" }]],
        presets: [
          [
            solid,
            {
              generate: "universal",
              hydratable: false,
              moduleName: runtimeSpecifier,
            },
          ],
          [ts],
        ],
      })
      return {
        contents: transforms?.code ?? "",
        loader: "js",
      }
    })
  },
}

export default solidTransformPlugin
