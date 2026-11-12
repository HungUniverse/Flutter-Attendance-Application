import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, query, where } from 'firebase/firestore';

let env;
const google = email => ({email, email_verified: true, firebase: {sign_in_provider: 'google.com'}});
const dbFor = (uid, email = `${uid}@example.com`, claims = {}) => env.authenticatedContext(uid, {...google(email), ...claims}).firestore();
const now = Date.now();
const meeting = (state = 'active') => ({
  id: 'm1', number: 1, startAt: new Date(now).toISOString(), endAt: new Date(now + 3600000).toISOString(), state,
  dayStart: Timestamp.fromMillis(now - 3600000), dayEnd: Timestamp.fromMillis(now + 3600000), records: {}, auditEvents: [],
});
const session = () => ({
  ownerUid: 'teacher', classId: 'c1', localClassId: 'local1', meetingId: 'm1', label: 'PRM393 · SE1',
  receiving: true, expiresAt: Timestamp.fromMillis(Date.now() + 90000), createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});
const mark = status => ({status, source: 'manual', recordedAt: new Date().toISOString()});
const checkIn = (uid = 'student', email = 'student@example.com') => ({uid, email, at: serverTimestamp()});
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-fap-final', firestore: {rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'users/teacher'), {role: 'teacher'}),
      setDoc(doc(db, 'users/other'), {role: 'teacher'}),
      setDoc(doc(db, 'workspaces/w1'), {ownerUid: 'teacher', revision: 1, mutationId: 'seed', data: {}, layout: {c1: ['m1']}, updatedAt: serverTimestamp()}),
      setDoc(doc(db, 'classes/c1'), {ownerUid: 'teacher', workspaceId: 'w1', archived: false, data: {}, roster: {'student@example.com': 'S1'}}),
      setDoc(doc(db, 'classes/c1/meetings/m1'), meeting()),
      setDoc(doc(db, 'attendanceSessions/s1'), session()),
      setDoc(doc(db, 'announcements/a1'), {ownerUid: 'teacher', recipientUid: 'student', title: 'Notice', body: 'Class today', at: serverTimestamp(), classId: 'c1', meetingId: 'm1'}),
      setDoc(doc(db, 'reportMetadata/r1'), {ownerUid: 'teacher', classId: 'c1', meetingId: 'm1', fileName: 'report.pdf', format: 'pdf', bytes: 100, at: serverTimestamp()}),
    ]);
  });
});

for (const path of ['users/teacher', 'workspaces/w1', 'classes/c1', 'classes/c1/meetings/m1', 'attendanceSessions/s1', 'announcements/a1', 'reportMetadata/r1']) {
  test(`anonymous cannot read ${path}`, () => assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path))));
}
test('profile owner reads own role, cannot grant or edit teacher privileges', async () => {
  await assertSucceeds(getDoc(doc(dbFor('teacher'), 'users/teacher')));
  await assertFails(setDoc(doc(dbFor('student'), 'users/student'), {role: 'teacher'}));
  await assertFails(updateDoc(doc(dbFor('teacher'), 'users/teacher'), {role: 'teacher', admin: true}));
  await assertFails(getDoc(doc(dbFor('other'), 'users/teacher')));
});
for (const path of ['workspaces/w1', 'classes/c1', 'classes/c1/meetings/m1', 'reportMetadata/r1']) {
  test(`teacher owns ${path}, other teacher and student are denied`, async () => {
    await assertSucceeds(getDoc(doc(dbFor('teacher'), path)));
    await assertFails(getDoc(doc(dbFor('other'), path)));
    await assertFails(getDoc(doc(dbFor('student'), path)));
  });
}
test('teacher queries own workspaces and sessions', async () => {
  for (const name of ['workspaces', 'attendanceSessions']) {
    await assertSucceeds(getDocs(query(collection(dbFor('teacher'), name), where('ownerUid', '==', 'teacher'))));
    await assertFails(getDocs(collection(dbFor('student'), name)));
  }
});
test('workspace increments revision, denies stale revision and wrong owner', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('teacher'), 'workspaces/w1'), {revision: 2, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(dbFor('teacher'), 'workspaces/w1'), {revision: 2, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(dbFor('other'), 'workspaces/w1'), {revision: 3, updatedAt: serverTimestamp()}));
});
test('new workspace class and meetings commit atomically', async () => {
  const db = dbFor('teacher'), batch = writeBatch(db);
  batch.set(doc(db, 'workspaces/new'), {ownerUid: 'teacher', revision: 1, mutationId: 'first', data: {}, layout: {new: ['m1']}, updatedAt: serverTimestamp()});
  batch.set(doc(db, 'classes/new'), {ownerUid: 'teacher', workspaceId: 'new', archived: false, data: {}, roster: {}});
  batch.set(doc(db, 'classes/new/meetings/m1'), meeting('upcoming'));
  await assertSucceeds(batch.commit());
});
test('class updates require workspace revision in same batch', async () => {
  const db = dbFor('teacher');
  await assertFails(updateDoc(doc(db, 'classes/c1'), {archived: true}));
  const batch = writeBatch(db);
  batch.update(doc(db, 'workspaces/w1'), {revision: 2, updatedAt: serverTimestamp()});
  batch.update(doc(db, 'classes/c1'), {archived: true});
  await assertSucceeds(batch.commit());
});
test('verified roster student creates own immutable check-in', async () => {
  const db = dbFor('student'), ref = doc(db, 'attendanceSessions/s1/checkIns/student');
  await assertSucceeds(setDoc(ref, checkIn()));
  await assertSucceeds(getDoc(ref));
  await assertFails(setDoc(ref, checkIn()));
  await assertFails(deleteDoc(ref));
  await assertSucceeds(getDocs(collection(dbFor('teacher'), 'attendanceSessions/s1/checkIns')));
  await assertFails(getDocs(collection(db, 'attendanceSessions/s1/checkIns')));
  await assertFails(getDoc(doc(dbFor('outsider'), ref.path)));
});
test('check-in denies impersonation, self-entered email, extra fields and forged time', async () => {
  const db = dbFor('student');
  await assertFails(setDoc(doc(db, 'attendanceSessions/s1/checkIns/another'), checkIn('another')));
  await assertFails(setDoc(doc(dbFor('outsider'), 'attendanceSessions/s1/checkIns/outsider'), checkIn('outsider', 'student@example.com')));
  await assertFails(setDoc(doc(db, 'attendanceSessions/s1/checkIns/student'), {...checkIn(), rollNumber: 'S1'}));
  await assertFails(setDoc(doc(db, 'attendanceSessions/s1/checkIns/student'), {...checkIn(), at: Timestamp.fromMillis(now - 60000)}));
});
for (const [label, claims] of [['unverified', {email_verified: false}], ['password provider', {firebase: {sign_in_provider: 'password'}}]]) {
  test(`check-in denies ${label}`, () => assertFails(setDoc(doc(dbFor('student', 'student@example.com', claims), 'attendanceSessions/s1/checkIns/student'), checkIn())));
}
for (const state of ['closed', 'expired', 'meeting closed', 'archived class']) {
  test(`check-in denies ${state}`, async () => {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      if (state === 'closed') await updateDoc(doc(db, 'attendanceSessions/s1'), {receiving: false});
      if (state === 'expired') await updateDoc(doc(db, 'attendanceSessions/s1'), {expiresAt: Timestamp.fromMillis(now - 1000)});
      if (state === 'meeting closed') await updateDoc(doc(db, 'classes/c1/meetings/m1'), {state: 'closed'});
      if (state === 'archived class') await updateDoc(doc(db, 'classes/c1'), {archived: true});
    });
    await assertFails(setDoc(doc(dbFor('student'), 'attendanceSessions/s1/checkIns/student'), checkIn()));
  });
}
test('teacher opens and stops session, student and other teacher cannot', async () => {
  await assertSucceeds(setDoc(doc(dbFor('teacher'), 'attendanceSessions/new'), session()));
  await assertSucceeds(updateDoc(doc(dbFor('teacher'), 'attendanceSessions/new'), {receiving: false, updatedAt: serverTimestamp()}));
  await assertFails(setDoc(doc(dbFor('student'), 'attendanceSessions/forged'), session()));
  await assertFails(updateDoc(doc(dbFor('other'), 'attendanceSessions/s1'), {receiving: false, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(dbFor('teacher'), 'attendanceSessions/s1'), {ownerUid: 'other', updatedAt: serverTimestamp()}));
});
test('freeze acknowledgment rejects every subsequent student check-in', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('teacher'), 'attendanceSessions/s1'), {receiving: false, updatedAt: serverTimestamp()}));
  await assertFails(setDoc(doc(dbFor('student'), 'attendanceSessions/s1/checkIns/student'), checkIn()));
});
test('closed meeting corrections need a matching reason and append-only audit', async () => {
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), 'classes/c1/meetings/m1'), {state: 'closed', records: {S1: mark('A')}}));
  const db = dbFor('teacher');
  const edit = async (changes, revision = 2) => {
    const batch = writeBatch(db);
    batch.update(doc(db, 'workspaces/w1'), {revision, updatedAt: serverTimestamp()});
    batch.update(doc(db, 'classes/c1/meetings/m1'), changes);
    return batch.commit();
  };
  await assertFails(edit({records: {S1: mark('P')}}));
  const audit = {id: 'a1', createdAt: new Date().toISOString(), action: 'attendance_override', meetingId: 'm1', rollNumber: 'S1', oldValue: 'A', newValue: 'P', reason: 'Verified correction'};
  await assertSucceeds(edit({records: {S1: {...mark('P'), note: audit.reason}}, auditEvents: [audit]}));
  await assertFails(edit({state: 'active'}, 3));
  await assertFails(edit({records: {S1: {...mark('A'), note: ' '}}, auditEvents: [audit, {...audit, oldValue: 'P', newValue: 'A', reason: ' '}]}, 3));
});
test('student cannot write teacher collections', async () => {
  const db = dbFor('student');
  for (const path of ['workspaces/forged', 'classes/forged', 'classes/c1/meetings/m1']) {
    await assertFails(setDoc(doc(db, path), {ownerUid: 'student', role: 'teacher'}));
  }
  await assertSucceeds(getDoc(doc(db, 'users/student')));
});
test('server calendar rejects opening a future meeting or reopening an active meeting as upcoming', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'classes/c1/meetings/m1'), {state: 'upcoming', dayStart: Timestamp.fromMillis(Date.now() + 86400000), dayEnd: Timestamp.fromMillis(Date.now() + 172800000)});
  });
  const db = dbFor('teacher'), batch = writeBatch(db);
  batch.update(doc(db, 'workspaces/w1'), {revision: 2, updatedAt: serverTimestamp()});
  batch.update(doc(db, 'classes/c1/meetings/m1'), {state: 'active'});
  await assertFails(batch.commit());
});
test('sessions reject excessive expiration and malformed receiving state', async () => {
  const db = dbFor('teacher');
  await assertFails(setDoc(doc(db, 'attendanceSessions/too-long'), {...session(), expiresAt: Timestamp.fromMillis(Date.now() + 600000)}));
  await assertFails(setDoc(doc(db, 'attendanceSessions/bad-type'), {...session(), receiving: 'true'}));
});
test('announcements are addressed to the correct recipient', async () => {
  await assertSucceeds(getDoc(doc(dbFor('student'), 'announcements/a1')));
  await assertSucceeds(getDoc(doc(dbFor('teacher'), 'announcements/a1')));
  await assertFails(getDoc(doc(dbFor('outsider'), 'announcements/a1')));
  const notice = {ownerUid: 'teacher', recipientUid: 'student', title: 'Hello', body: 'Body', at: serverTimestamp(), classId: 'c1', meetingId: 'm1'};
  await assertSucceeds(setDoc(doc(dbFor('teacher'), 'announcements/a2'), notice));
  await assertFails(setDoc(doc(dbFor('student'), 'announcements/a3'), notice));
});
test('report metadata is teacher-owned and requires a finalized meeting', async () => {
  const data = {ownerUid: 'teacher', classId: 'c1', meetingId: 'm1', fileName: 'report.pdf', format: 'pdf', bytes: 100, at: serverTimestamp()};
  await assertFails(setDoc(doc(dbFor('teacher'), 'reportMetadata/new'), data));
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), 'classes/c1/meetings/m1'), {state: 'closed'}));
  await assertSucceeds(setDoc(doc(dbFor('teacher'), 'reportMetadata/new'), data));
  await assertFails(setDoc(doc(dbFor('student'), 'reportMetadata/forged'), data));
  assert.equal((await getDoc(doc(dbFor('teacher'), 'reportMetadata/new'))).data().format, 'pdf');
});
