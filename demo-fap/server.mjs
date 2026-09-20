import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const root = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(root, '..');
const execFileAsync = promisify(execFile);
const files = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
]);
const port = Number(process.env.FAP_DEMO_PORT || 4173);
let rosterCache;
let dartPathPromise;

async function dartExecutable() {
  if (process.env.DART_EXECUTABLE) return process.env.DART_EXECUTABLE;
  if (process.platform !== 'win32') return 'dart';
  dartPathPromise ??= (async () => {
    const pathDirs = (process.env.Path || process.env.PATH || '').split(delimiter);
    for (const dir of pathDirs) {
      for (const candidate of [join(dir, 'dart.exe'), join(dir, 'cache', 'dart-sdk', 'bin', 'dart.exe')]) {
        try {
          if ((await stat(candidate)).isFile()) return candidate;
        } catch { /* Continue searching PATH. */ }
      }
    }
    throw new Error('Không tìm thấy dart.exe. Hãy cài Flutter SDK hoặc đặt DART_EXECUTABLE.');
  })();
  return dartPathPromise;
}

async function markbookPath() {
  const candidates = process.env.FAP_MARKBOOK_PATH
    ? [process.env.FAP_MARKBOOK_PATH]
    : [resolve(projectRoot, '..', 'FA26_Markbook.ods'), resolve(projectRoot, 'test', 'fixtures', 'FA26_Markbook.ods')];
  for (const path of candidates) {
    try {
      await stat(path);
      return path;
    } catch { /* Try the bundled copy. */ }
  }
  throw new Error('Không tìm thấy FA26_Markbook.ods.');
}

async function markbookRoster() {
  const source = await markbookPath();
  const info = await stat(source);
  const key = `${source}:${info.size}:${info.mtimeMs}`;
  if (rosterCache?.key !== key) {
    rosterCache = {
      key,
      promise: dartExecutable().then((dart) => execFileAsync(dart, ['run', 'demo-fap/markbook_rosters.dart', source], {
        cwd: projectRoot,
        windowsHide: true,
        timeout: 30000,
        maxBuffer: 8 * 1024 * 1024,
      })).then(({ stdout }) => JSON.parse(stdout)),
    };
  }
  try { return await rosterCache.promise; }
  catch (error) { rosterCache = undefined; throw error; }
}

createServer(async (request, response) => {
  const pathname = new URL(request.url || '/', 'http://localhost').pathname;
  if (pathname === '/markbook-rosters.json') {
    try {
      const body = JSON.stringify(await markbookRoster());
      response.writeHead(200, {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      }).end(body);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'application/json; charset=utf-8' })
        .end(JSON.stringify({ error: `Không đọc được markbook: ${error.message}` }));
    }
    return;
  }
  const item = files.get(pathname);
  if (!item) {
    response.writeHead(404).end('Not found');
    return;
  }
  try {
    const body = await readFile(join(root, item[0]));
    response.writeHead(200, {
      'content-type': item[1],
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    }).end(body);
  } catch {
    response.writeHead(500).end('Cannot load demo file');
  }
}).listen(port, '127.0.0.1', () => {
  process.stdout.write(`FAP demo: http://localhost:${port}/\n`);
});
