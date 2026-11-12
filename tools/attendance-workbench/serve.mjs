#!/usr/bin/env node
// Opt-in static server for the local UI. It binds only to loopback and serves
// the UI files, its workbench modules and backend utility modules as read-only.
import { createServer } from 'node:http';
import { readFile, realpath } from 'node:fs/promises';
import { extname, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const host = '127.0.0.1';
const contentTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.ico', 'image/x-icon'],
]);
const interfaceAssets = new Set(['app.js', 'styles.css']);

function isAllowed(pathname) {
  return pathname === '/tools/attendance-workbench' ||
    pathname.startsWith('/tools/attendance-workbench/') ||
    pathname.startsWith('/backend/');
}

async function serve(request, response) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { Allow: 'GET, HEAD' });
    response.end('Method not allowed');
    return;
  }
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, `http://${host}`).pathname);
  } catch {
    response.writeHead(400);
    response.end('Bad request');
    return;
  }
  if (!isAllowed(pathname)) {
    response.writeHead(404);
    response.end('Not found');
    return;
  }
  if (pathname.startsWith('/backend/') && extname(pathname).toLowerCase() !== '.mjs') {
    response.writeHead(404);
    response.end('Not found');
    return;
  }
  if (pathname === '/tools/attendance-workbench' || pathname === '/tools/attendance-workbench/') {
    pathname = '/tools/attendance-workbench/www/index.html';
  } else if (pathname.startsWith('/tools/attendance-workbench/') &&
      interfaceAssets.has(pathname.slice('/tools/attendance-workbench/'.length))) {
    pathname = `/tools/attendance-workbench/www/${pathname.slice('/tools/attendance-workbench/'.length)}`;
  }
  const target = resolve(root, `.${pathname}`);
  const pathFromRoot = relative(root, target);
  if (pathFromRoot.startsWith(`..${sep}`) || pathFromRoot === '..') {
    response.writeHead(404);
    response.end('Not found');
    return;
  }
  try {
    const actual = await realpath(target);
    const actualRelative = relative(root, actual);
    if (actualRelative.startsWith(`..${sep}`) || actualRelative === '..') throw new Error('path outside root');
    if (!isAllowed(`/${actualRelative.split(sep).join('/')}`)) throw new Error('path outside workbench');
    const contents = await readFile(actual);
    response.writeHead(200, {
      'Content-Type': contentTypes.get(extname(actual).toLowerCase()) ?? 'application/octet-stream',
      'Content-Length': contents.length,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'self' blob: data:; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      'Referrer-Policy': 'no-referrer',
    });
    response.end(request.method === 'HEAD' ? undefined : contents);
  } catch (error) {
    response.writeHead(error.code === 'ENOENT' ? 404 : 403);
    response.end(error.code === 'ENOENT' ? 'Not found' : 'Forbidden');
  }
}

const server = createServer((request, response) => {
  serve(request, response).catch(() => {
    if (!response.headersSent) response.writeHead(500);
    response.end('Internal server error');
  });
});

const requestedPort = Number(process.env.ATTENDANCE_WORKBENCH_PORT ?? 0);
if (!Number.isInteger(requestedPort) || requestedPort < 0 || requestedPort > 65535) {
  process.stderr.write('ATTENDANCE_WORKBENCH_PORT must be an integer from 0 to 65535.\n');
  process.exitCode = 1;
} else {
  server.listen(requestedPort, host, () => {
    const { port } = server.address();
    process.stdout.write(`Attendance Workbench: http://${host}:${port}/tools/attendance-workbench/\n`);
    process.stdout.write('Press Ctrl+C to stop.\n');
  });
  server.on('error', (error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
