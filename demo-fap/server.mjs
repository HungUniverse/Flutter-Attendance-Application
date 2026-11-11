import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { basename, delimiter, dirname, join, resolve } from 'node:path';
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
const maxRosterBytes = 20 * 1024 * 1024;
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
      promise: parseClassList([source]).then((data) => ({
        ...data, sourceName: basename(source),
      })),
    };
  }
  try { return await rosterCache.promise; }
  catch (error) { rosterCache = undefined; throw error; }
}

async function parseClassList(args, bytes) {
  const dart = await dartExecutable();
  const run = execFileAsync(dart, ['run', 'demo-fap/markbook_rosters.dart', ...args], {
    cwd: projectRoot,
    windowsHide: true,
    timeout: 30000,
    maxBuffer: 8 * 1024 * 1024,
  });
  const stdin = run.child.stdin;
  // The process may exit before it finishes reading an invalid file.
  stdin.on('error', () => {});
  stdin.end(bytes);
  return JSON.parse((await run).stdout);
}

function sendJson(response, status, data) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  }).end(JSON.stringify(data));
}

async function uploadClassList(request, response, format) {
  if (!['ods', 'xlsx'].includes(format) ||
      request.headers['content-type'] !== 'application/octet-stream') {
    request.resume();
    sendJson(response, 415, { error: 'Chọn tệp danh sách lớp ODS hoặc XLSX.' });
    return;
  }
  try {
    const chunks = [];
    let length = 0;
    for await (const chunk of request.iterator({ destroyOnReturn: false })) {
      length += chunk.length;
      if (length > maxRosterBytes) {
        request.resume();
        sendJson(response, 413, { error: 'Tệp danh sách lớp tối đa 20 MB.' });
        return;
      }
      chunks.push(chunk);
    }
    const roster = await parseClassList(['--stdin', `roster.${format}`], Buffer.concat(chunks));
    sendJson(response, 200, roster);
  } catch {
    sendJson(response, 422, { error: 'Không đọc được danh sách lớp. Kiểm tra định dạng và các cột của tệp.' });
  }
}

createServer(async (request, response) => {
  const url = new URL(request.url || '/', 'http://localhost');
  const { pathname } = url;
  if (pathname === '/markbook-rosters.json' && request.method === 'POST') {
    await uploadClassList(request, response, url.searchParams.get('format'));
    return;
  }
  if (pathname === '/markbook-rosters.json' && request.method === 'GET') {
    try {
      sendJson(response, 200, await markbookRoster());
    } catch {
      sendJson(response, 500, { error: 'Không đọc được danh sách lớp mặc định. Hãy chọn một tệp ODS hoặc XLSX.' });
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
