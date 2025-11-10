#!/usr/bin/env bun
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const currentDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(currentDir, '..');
const entry = path.join(projectRoot, 'main.jsx');
const outdir = projectRoot;
while (true) {
  const result = await Bun.build({
    entrypoints: [entry],
    outdir,
    target: 'browser',
    format: 'esm',
    naming: { entry: '[name].js' },
    splitting: false,
    minify: false,
    watch: true,
  });
  if (!result.success) {
    for (const message of result.logs) {
      console.error(message);
    }
  }
}
