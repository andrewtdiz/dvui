#!/usr/bin/env bun

import { fileURLToPath } from "node:url";
import path from "node:path";
import solidTransformPlugin from "./solid-plugin.ts";
import App from "../main.jsx";

console.log(App);

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(currentDir, "..");
const entry = path.join(projectRoot, "main.jsx");
const outdir = projectRoot;

const result = await Bun.build({
  entrypoints: [entry],
  outdir,
  target: "browser",
  format: "esm",
  naming: {
    entry: "[name].js",
  },
  splitting: false,
  minify: false,
  plugins: [solidTransformPlugin],
});

if (!result.success) {
  for (const message of result.logs) {
    console.error(message);
  }
  throw new Error("Solid bundle failed");
}
