import { build } from 'esbuild';
import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(fileURLToPath(new URL('.', import.meta.url)));
const outputDir = resolve(projectRoot, 'dist');
if (dirname(outputDir) !== projectRoot) throw new Error('Build output must stay inside the extension directory.');
await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await build({
  entryPoints: ['src/popup.ts', 'src/content.ts'],
  bundle: true,
  outdir: outputDir,
  format: 'iife',
  target: 'chrome120',
  sourcemap: true,
});
await Promise.all([
  cp('public/manifest.json', 'dist/manifest.json'),
  cp('public/popup.html', 'dist/popup.html'),
  cp('public/popup.css', 'dist/popup.css'),
]);
