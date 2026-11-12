import { getAuth } from "firebase-admin/auth";
import { adminApp, projectId } from "./admin-client.mjs";

const email=process.argv[2]?.trim().toLowerCase();
if(!email || !/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(email))throw new Error("Usage: node firebase/provision-admin.mjs admin@gmail.com");
const app=adminApp(),auth=getAuth(app);
let user;
try{user=await auth.getUserByEmail(email);}catch(error){if(error.code!=="auth/user-not-found")throw error;user=await auth.createUser({email});}
const {access_token}=await app.options.credential.getAccessToken();
const base=`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
const headers={Authorization:`Bearer ${access_token}`,"Content-Type":"application/json"};
async function read(path){const r=await fetch(`${base}/${path}`,{headers});if(r.status===404)return undefined;if(!r.ok)throw new Error(`Read failed HTTP ${r.status}`);return r.json();}
async function write(path,fields,mask){
  const params=new URLSearchParams();for(const key of mask || Object.keys(fields))params.append("updateMask.fieldPaths",key);
  const r=await fetch(`${base}/${path}?${params}`,{method:"PATCH",headers,body:JSON.stringify({fields})});
  if(!r.ok)throw new Error(`Write failed HTTP ${r.status}`);
}
const at=new Date().toISOString();
await write(`users/${user.uid}`,{role:{stringValue:"admin"},email:{stringValue:email},provisionedAt:{timestampValue:at}});
if((await read(`users/${user.uid}`))?.fields?.role?.stringValue!=="admin")throw new Error("Admin verification failed.");
// Migrate existing teacher grants once. Rerunning this tool must not restore
// directory entries that an administrator deliberately deleted later.
const marker=await read("system/teacher-directory-v1");
let migrated=0;
if(!marker){
  let token;
  do{
    const params=new URLSearchParams({pageSize:"1000",...(token?{pageToken:token}:{})});
    const response=await fetch(`${base}/users?${params}`,{headers});if(!response.ok)throw new Error(`User inventory HTTP ${response.status}`);
    const page=await response.json();token=page.nextPageToken;
    for(const profile of page.documents || []){
      const fields=profile.fields || {},address=fields.email?.stringValue?.toLowerCase();
      if(fields.role?.stringValue!=="teacher" || !address || !/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(address))continue;
      if(await read(`teacherDirectory/${encodeURIComponent(address)}`))continue;
      await write(`teacherDirectory/${encodeURIComponent(address)}`,{
        email:{stringValue:address},displayName:{stringValue:fields.displayName?.stringValue || address.split("@")[0]},
        staffCode:{stringValue:""},department:{stringValue:""},status:{stringValue:"active"},
        createdAt:{timestampValue:at},updatedAt:{timestampValue:at},createdBy:{stringValue:user.uid},updatedBy:{stringValue:user.uid},
      });migrated++;
    }
  }while(token);
  await write("system/teacher-directory-v1",{completedAt:{timestampValue:at},actorUid:{stringValue:user.uid}});
}
const verified=await read(`users/${user.uid}`);
if(verified.fields?.role?.stringValue!=="admin" || verified.fields?.email?.stringValue!==email)throw new Error("Admin read-back mismatch.");
console.log(JSON.stringify({adminEmail:email,adminVerified:true,migratedTeacherProfiles:migrated,migrationAlreadyComplete:Boolean(marker),projectId}));
