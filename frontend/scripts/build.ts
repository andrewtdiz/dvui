import { join } from "path";
import process from "process";
import solidTransformPlugin from "./solid-plugin";

const root = join(import.meta.dir, "..");
const outdir = join(root, "dist");

const result = await Bun.build({
  entrypoints: [join(root, "index.ts")],
  outdir,
  target: "bun",
  splitting: false,
  conditions: ["browser"],
  plugins: [solidTransformPlugin],
});

if (!result.success) {
  console.error("Build failed", result.logs);
  process.exit(1);
}

console.log(`Built to ${outdir}`);
