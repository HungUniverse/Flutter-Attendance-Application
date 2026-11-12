import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { adminApp, projectId } from './admin-client.mjs';

const email = process.argv[2]?.trim().toLowerCase();
if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Usage: npm run provision:teacher -- lecturer@example.com');
const app = adminApp();
const auth = getAuth(app);
let user;
try { user = await auth.getUserByEmail(email); }
catch (error) {
  if (error.code !== 'auth/user-not-found') throw error;
  user = await auth.createUser({email});
}
await getFirestore(app).doc(`users/${user.uid}`).set({role: 'teacher', email, provisionedAt: FieldValue.serverTimestamp()}, {merge: true});
const profile = await getFirestore(app).doc(`users/${user.uid}`).get();
if (profile.data()?.role !== 'teacher') throw new Error('Teacher role verification failed.');
console.log(`Verified teacher role for ${email} in ${projectId}. Google Sign-In is required by Rules.`);
