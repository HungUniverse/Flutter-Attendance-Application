import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { FirestoreWorkspaceStore } from './workspaces.mjs';
import { createRelay, SessionStore } from './relay.mjs';

const { FIREBASE_PROJECT_ID, PUBLIC_ORIGIN, TEACHER_EMAILS, FIREBASE_WEB_CONFIG } = process.env;
if (!FIREBASE_PROJECT_ID || !PUBLIC_ORIGIN || !TEACHER_EMAILS || !FIREBASE_WEB_CONFIG) {
  throw new Error('Set FIREBASE_PROJECT_ID, PUBLIC_ORIGIN, TEACHER_EMAILS and FIREBASE_WEB_CONFIG; see README.md');
}
initializeApp({ credential: applicationDefault(), projectId: FIREBASE_PROJECT_ID });
const server = createRelay({
  store: new SessionStore(process.env.DATA_DIR ?? fileURLToPath(new URL('./data', import.meta.url))),
  verifyIdentity: token => getAuth().verifyIdToken(token, true),
  teachers: TEACHER_EMAILS.split(','), publicOrigin: PUBLIC_ORIGIN,
  webConfig: JSON.parse(FIREBASE_WEB_CONFIG),
  studentHtml: await readFile(new URL('./student.html', import.meta.url), 'utf8'),
  desktopHtml: await readFile(new URL('./desktop-login.html', import.meta.url), 'utf8'),
  workspaceStore: new FirestoreWorkspaceStore(getFirestore()),
});
server.listen(Number(process.env.PORT ?? 8789), process.env.HOST ?? '127.0.0.1', () => {
  console.log('Attendance relay ready. Session tokens and credentials are not logged.');
});
