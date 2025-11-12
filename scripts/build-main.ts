// Run with `npx tsx scripts/build-main.ts` or your preferred TypeScript runner.
import { mkdir, copyFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, "..");
const outDir = join(projectRoot, "zig-out", "web");

async function ensureOutputDir() {
  await mkdir(outDir, { recursive: true });
}

async function bundle() {
  await build({
    entryPoints: [join(projectRoot, "src/js/main.jsx")],
    outfile: join(outDir, "main.js"),
    bundle: true,
    format: "esm",
    sourcemap: true,
    jsx: "automatic",
    target: ["es2020"],
    define: {
      "process.env.NODE_ENV": JSON.stringify(process.env.NODE_ENV ?? "development"),
    },
  });
}

async function copyTemplate() {
  const src = join(projectRoot, "src/backends/index.html");
  const dst = join(outDir, "index.html");
  await copyFile(src, dst);
}

async function main() {
  await ensureOutputDir();
  await bundle();
  await copyTemplate();
}

main().catch((err) => {
  console.error("[build-main] failed", err);
  process.exit(1);
});
