import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const sourceExtensions = new Set(['.dart', '.html', '.js', '.mjs', '.json', '.yaml', '.yml']);
const ignoredDirectories = new Set(['node_modules', 'dist', '.git', '.dart_tool', 'build']);

async function listFiles(directory) {
  let entries;
  try { entries = await readdir(directory, { withFileTypes: true }); }
  catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const nested = await Promise.all(entries.map(async (entry) => {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) return [];
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return listFiles(path);
    return [path];
  }));
  return nested.flat();
}

async function applicationReferences() {
  const candidates = [
    ...(await listFiles(join(root, 'lib'))),
    ...(await listFiles(join(root, 'web'))),
    ...['pubspec.yaml', 'package.json', 'firebase.json'].map((name) => join(root, name)),
  ];
  const sourceFiles = candidates.filter((path) => sourceExtensions.has(extname(path).toLowerCase()));
  const references = [];
  for (const path of sourceFiles) {
    let contents;
    try { contents = await readFile(path, 'utf8'); }
    catch (error) {
      if (error.code === 'ENOENT') continue;
      throw error;
    }
    if (/attendance-workbench|tools[\\/]attendance-workbench/i.test(contents)) references.push(path);
  }
  return references;
}

test('the Flutter and web application entry sources do not import the optional workbench', async () => {
  assert.deepEqual(await applicationReferences(), []);
});

test('the local server is loopback-only, read-only and has no network-capable page policy', async () => {
  const server = await readFile(join(root, 'tools/attendance-workbench/serve.mjs'), 'utf8');
  assert.match(server, /const host = '127\.0\.0\.1'/);
  assert.match(server, /request\.method !== 'GET' && request\.method !== 'HEAD'/);
  assert.match(server, /connect-src 'none'/);
  assert.match(server, /Cache-Control': 'no-store'/);
  assert.doesNotMatch(server, /writeFile|createWriteStream|fetch\(/);
});

test('CLI commands read explicit paths and emit results to stdout without file writes or networking', async () => {
  const cli = await readFile(join(root, 'tools/attendance-workbench/cli.mjs'), 'utf8');
  assert.match(cli, /import \{ readFile \} from 'node:fs\/promises'/);
  assert.match(cli, /process\.stdout\.write\(await runCommand/);
  assert.doesNotMatch(cli, /writeFile|createWriteStream|fetch\(|node:https|node:http/);
});
