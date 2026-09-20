import { build } from 'esbuild';
import { cp, mkdir, rm } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });
await build({
  entryPoints: ['src/popup.ts', 'src/content.ts', 'src/picker_bridge.ts'],
  bundle: true,
  outdir: 'dist',
  format: 'iife',
  target: 'chrome120',
  sourcemap: true,
});
await Promise.all([
  cp('public/manifest.json', 'dist/manifest.json'),
  cp('public/popup.html', 'dist/popup.html'),
  cp('public/popup.css', 'dist/popup.css'),
  cp('public/picker.html', 'dist/picker.html'),
]);
