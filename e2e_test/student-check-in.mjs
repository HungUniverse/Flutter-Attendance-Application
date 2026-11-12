import { createRequire } from "node:module";
const require = createRequire(new URL("../web/package.json", import.meta.url));
const { initializeApp, deleteApp } = require("firebase/app");
const {
  getAuth,
  connectAuthEmulator,
  signInWithCredential,
  GoogleAuthProvider,
} = require("firebase/auth");
const {
  getFirestore,
  connectFirestoreEmulator,
  doc,
  runTransaction,
  serverTimestamp,
  terminate,
} = require("firebase/firestore");

const [sessionId, email] = process.argv.slice(2);
if (!sessionId || !email?.endsWith("@example.com"))
  throw new Error("Only synthetic example.com accounts are supported.");
const app = initializeApp({
  apiKey: "fake-api-key",
  projectId: "demo-fap-final",
  appId: "1:123:web:emulator",
});
const auth = getAuth(app),
  db = getFirestore(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
connectFirestoreEmulator(db, "127.0.0.1", 8080);
const encode = (value) =>
  Buffer.from(JSON.stringify(value)).toString("base64url");
const token = `${encode({ alg: "none", typ: "JWT" })}.${encode({ sub: email, email, email_verified: true, iss: "https://accounts.google.com", aud: "fake", iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
try {
  const user = (
    await signInWithCredential(auth, GoogleAuthProvider.credential(token))
  ).user;
  const ref = doc(db, "attendanceSessions", sessionId, "checkIns", user.uid);
  const alreadySent = await runTransaction(db, async (tx) => {
    if ((await tx.get(ref)).exists()) return true;
    tx.set(ref, {
      uid: user.uid,
      email: user.email.toLowerCase(),
      at: serverTimestamp(),
    });
    return false;
  });
  console.log(JSON.stringify({ accepted: true, alreadySent }));
} catch (error) {
  console.log(JSON.stringify({ accepted: false, code: error.code }));
} finally {
  await terminate(db);
  await deleteApp(app);
}
