import assert from "node:assert/strict";
import { initializeApp, deleteApp } from "firebase/app";
import { getFirestore, connectFirestoreEmulator, doc, getDocFromServer, getDocsFromServer, query, where, collection } from "firebase/firestore";
import { AdminRepository } from "../src/admin/repository.js";
import { parseRoster, hashId } from "../src/admin/model.js";
import { createRequest } from "../src/student/repository.js";

// Invoked by the Rules suite, which seeds through its explicit emulator-only bypass.
export async function exerciseAdminFlow(seedClosedMeeting) {
  const apps=[];
  function actor(uid) {
    const app=initializeApp({projectId:"demo-fap-final",apiKey:"fake-key",appId:`test:${uid}`},`web-${uid}-${crypto.randomUUID()}`);
    apps.push(app);
    const db=getFirestore(app);
    connectFirestoreEmulator(db,"127.0.0.1",8080,{mockUserToken:{sub:uid,user_id:uid,email:`${uid}@example.com`,email_verified:true,firebase:{sign_in_provider:"google.com"}}});
    return db;
  }
  try {
    const teacherDb=actor("teacher"),studentDb=actor("student"),outsiderDb=actor("outsider");
    const repo=new AdminRepository(teacherDb,"teacher","teacher@example.com");
    await repo.requireTeacher();
    await assert.rejects(new AdminRepository(studentDb,"student").requireTeacher());
    const input={semester:"FA26",start:"2026-11-09",courseCode:"PRM393",classCode:"WEB1",scheduleCode:"11",weeks:1,perWeek:2};
    const students=parseRoster("S1 | Nguyễn An | student@example.com\nS2 | Trần Bình | second@example.com");
    const ids=await repo.createClass(input,students);
    let data=await repo.loadWorkspace(ids.workspaceId);
    assert.equal(data.classes.length,1);
    assert.equal(data.classes[0].meetings.length,2);
    const originalRevision=data.workspace.revision;
    await repo.editClass(data.classes[0],students,{courseCode:"PRM393",classCode:"WEB2"},originalRevision);
    await assert.rejects(repo.editClass(data.classes[0],students,{courseCode:"X",classCode:"Y"},originalRevision),e=>e.code==="conflict");
    data=await repo.loadWorkspace(ids.workspaceId);
    const course=data.classes[0],meeting=course.meetings[0];
    const sessionId=await hashId(`${course.id}/${meeting.id}`);
    await seedClosedMeeting({course,meeting,sessionId});
    const user={uid:"student",email:"student@example.com"};
    await createRequest(studentDb,user,{session:sessionId,status:"P",reason:"Đề nghị đối chiếu minh chứng"});
    await assert.rejects(createRequest(studentDb,user,{session:sessionId,status:"P",reason:"Gửi trùng"}));
    await assert.rejects(createRequest(outsiderDb,{uid:"outsider",email:"outsider@example.com"},{session:sessionId,status:"P",reason:"Không thuộc lớp"}));
    const before=await repo.counts();assert.equal(before.pending,1);
    const id=`${course.id}_${meeting.id}_student`;
    await repo.decide(id,"approved","Đã xác minh có mặt");
    const result=await getDocFromServer(doc(studentDb,"attendanceRequests",id));
    assert.equal(result.data().state,"approved");
    data=await repo.loadWorkspace(ids.workspaceId);
    const corrected=data.classes[0].meetings[0];
    assert.equal(corrected.records.S1.status,"P");
    assert.equal(corrected.records.S2.status,"A");
    assert.equal(corrected.auditEvents.at(-1).id,id);
    assert.equal(data.workspace.revision,originalRevision+2);
    await assert.rejects(repo.decide(id,"rejected","Xử lý lại"));
    await assert.rejects(repo.editClass(data.classes[0],[students[0]],input,data.workspace.revision));
    const received=await getDocsFromServer(query(collection(studentDb,"announcements"),where("recipientUid","==","student")));
    assert.equal(received.size,2); // Existing fixture notice + this decision.
    await repo.sendAnnouncement(data.classes[0],{audience:"class",meetingId:"",title:"Thông báo lớp",body:"Buổi học tiếp theo giữ nguyên lịch."});
    await repo.sendAnnouncement(data.classes[0],{audience:"self",meetingId:meeting.id,title:"Ghi chú giảng viên",body:"Kiểm tra kết quả đã duyệt."});
    const emailInbox=await getDocsFromServer(query(collection(studentDb,"announcements"),where("recipientEmail","==","student@example.com")));
    assert.equal(emailInbox.size,1); // Class message; decisions are addressed by verified UID.
    await assert.rejects(getDocFromServer(doc(outsiderDb,"announcements",`request-${id}`)));
    const after=await repo.counts();assert.equal(after.pending,0);
    await repo.archiveClass(data.classes[0],data.workspace.revision);
    const archived=await repo.loadWorkspace(ids.workspaceId);
    assert.equal(archived.classes.length,0);
    assert.equal((await repo.archivedClasses()).length,1);
    return {classCreated:true,staleEditRejected:true,studentRequestApproved:true,otherResultPreserved:true,auditRetained:true,duplicateDecisionRejected:true,studentInboxReceived:true,outsiderDenied:true,archiveRetainsHistory:true};
  } finally { await Promise.all(apps.map(app=>deleteApp(app))); }
}
