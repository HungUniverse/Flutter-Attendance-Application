import {
  collection, doc, query, where, getDocsFromServer, getDocFromServer,
  getCountFromServer, runTransaction, serverTimestamp, Timestamp, onSnapshot, writeBatch,
} from "firebase/firestore";
import { AdminError, semesterCode, required, validDate, hashId, generateMeetings, rosterMap, protectHistory, correction } from "./model.js";

const rows = snapshot => snapshot.docs.map(d => ({ ...d.data(), id: d.id }));
export class AdminRepository {
  constructor(db, uid, email = "") { this.db = db; this.uid = uid; this.email = email; }
  ref(path) { return doc(this.db, path); }
  ownQuery(name, ...filters) { return query(collection(this.db, name), where("ownerUid", "==", this.uid), ...filters); }
  async requireTeacher() {
    const profile = await getDocFromServer(this.ref(`users/${this.uid}`));
    if (profile.data()?.role !== "teacher") throw new AdminError("Tài khoản chưa được cấp quyền giảng viên.", "teacher-required");
  }
  watch(name, next, error) { return onSnapshot(this.ownQuery(name), s => next(rows(s)), error); }
  async counts() {
    const queries = [this.ownQuery("classes", where("archived","==",false)), this.ownQuery("attendanceRequests",where("state","==","pending")), this.ownQuery("reportMetadata")];
    const counts = await Promise.all(queries.map(q => getCountFromServer(q)));
    return { classes: counts[0].data().count, pending: counts[1].data().count, reports: counts[2].data().count };
  }
  async loadWorkspace(id) {
    return runTransaction(this.db, async tx => {
      const w = await tx.get(this.ref(`workspaces/${id}`));
      if (!w.exists()) throw new AdminError("Không tìm thấy học kỳ.");
      const workspace = { ...w.data(), id };
      const classes = [];
      for (const [classId, meetingIds] of Object.entries(workspace.layout)) {
        const course = await tx.get(this.ref(`classes/${classId}`));
        if (!course.exists() || course.data().archived) throw new AdminError("Dữ liệu lớp chưa nhất quán. Hãy tải lại.");
        const meetings = [];
        for (const m of meetingIds) {
          const row = await tx.get(this.ref(`classes/${classId}/meetings/${m}`));
          if (!row.exists()) throw new AdminError("Thiếu dữ liệu buổi học. Hãy tải lại.");
          meetings.push(row.data());
        }
        classes.push({ ...course.data(), id: classId, meetings });
      }
      return { workspace, classes };
    });
  }
  advance(tx, workspace, changes = {}) {
    tx.set(this.ref(`workspaces/${workspace.id}`), {
      ownerUid: this.uid, revision: workspace.revision + 1, mutationId: crypto.randomUUID(),
      data: workspace.data, layout: workspace.layout, ...changes, updatedAt: serverTimestamp(),
    });
  }
  checkRevision(snapshot, expected) {
    if (!snapshot.exists() || snapshot.data().revision !== expected) throw new AdminError("Dữ liệu đã thay đổi trên thiết bị khác. Đóng biểu mẫu và tải lại trước khi sửa.", "conflict");
    return { ...snapshot.data(), id: snapshot.id };
  }
  async createClass(input, students, expectedRevision = 0) {
    const semester = semesterCode(input.semester), start = input.start;
    validDate(start);
    const courseCode = required(input.courseCode,"Mã môn",32).toUpperCase();
    const classCode = required(input.classCode,"Mã lớp",40).toUpperCase();
    if (!/^[A-Z0-9_-]+$/.test(courseCode) || !/^[A-Z0-9_-]+$/.test(classCode)) throw new AdminError("Mã môn và mã lớp chỉ gồm chữ, số, gạch ngang hoặc gạch dưới.");
    const localId = `${semester}_${input.scheduleCode}_${courseCode}_${classCode}`;
    const workspaceId = await hashId(`${this.uid}/${semester}`);
    const classId = await hashId(`${this.uid}/${semester}/${localId}`);
    const weeks = Number(input.weeks), meetingsPerWeek = Number(input.perWeek);
    const meetings = generateMeetings(localId,input.scheduleCode,start,weeks,meetingsPerWeek);
    return runTransaction(this.db, async tx => {
      const w = await tx.get(this.ref(`workspaces/${workspaceId}`));
      const c = await tx.get(this.ref(`classes/${classId}`));
      if ((w.data()?.revision || 0) !== expectedRevision) throw new AdminError("Học kỳ đã thay đổi. Đóng biểu mẫu, tải lại rồi thêm lớp.","conflict");
      if (c.exists()) throw new AdminError("Lớp trùng mã môn, mã lớp và lịch đã tồn tại hoặc được lưu trữ. Chọn mã lớp khác.");
      const workspace = w.exists() ? { ...w.data(), id: workspaceId } : {
        id: workspaceId, revision: 0, layout: {},
        data: { schemaVersion: 1, id: semester, semester, semesterStart: `${start}T00:00:00.000`, teacherEmail: this.email, updatedAt: null },
      };
      this.advance(tx, workspace, { layout: { ...workspace.layout, [classId]: meetings.map(m=>m.id) } });
      tx.set(this.ref(`classes/${classId}`), {
        ownerUid: this.uid, workspaceId, archived: false,
        data: { id: localId, courseCode, classCode, scheduleCode: input.scheduleCode, students,
          scheduleRule: { scheduleCode: input.scheduleCode, semesterStart: `${start}T00:00:00.000`, weeks, meetingsPerWeek, weekdays: [], excludedDates: [], additionalStarts: [] } },
        roster: rosterMap(students),
      });
      for (const m of meetings) tx.set(this.ref(`classes/${classId}/meetings/${m.id}`), { ...m, dayStart: Timestamp.fromDate(m.dayStart), dayEnd: Timestamp.fromDate(m.dayEnd) });
      return { workspaceId, classId };
    });
  }
  async editClass(course, students, input, expectedRevision) {
    const courseCode = required(input.courseCode,"Mã môn",32).toUpperCase();
    const classCode = required(input.classCode,"Mã lớp",40).toUpperCase();
    if (!/^[A-Z0-9_-]+$/.test(courseCode) || !/^[A-Z0-9_-]+$/.test(classCode)) throw new AdminError("Mã môn hoặc mã lớp không hợp lệ.");
    return runTransaction(this.db, async tx => {
      const w = this.checkRevision(await tx.get(this.ref(`workspaces/${course.workspaceId}`)),expectedRevision);
      const current = await tx.get(this.ref(`classes/${course.id}`));
      if (!current.exists() || current.data().archived) throw new AdminError("Lớp đã được lưu trữ.");
      const meetings = [];
      for (const id of w.layout[course.id] || []) meetings.push((await tx.get(this.ref(`classes/${course.id}/meetings/${id}`))).data());
      protectHistory(students, meetings);
      this.advance(tx,w);
      tx.update(current.ref, { data: { ...current.data().data, courseCode, classCode, students }, roster: rosterMap(students) });
    });
  }
  async archiveClass(course, expectedRevision) {
    return runTransaction(this.db, async tx => {
      const w = this.checkRevision(await tx.get(this.ref(`workspaces/${course.workspaceId}`)),expectedRevision);
      const current = await tx.get(this.ref(`classes/${course.id}`));
      if (!current.exists() || current.data().archived) throw new AdminError("Lớp đã được lưu trữ.");
      for (const id of w.layout[course.id] || []) {
        if ((await tx.get(this.ref(`classes/${course.id}/meetings/${id}`))).data()?.state === "active") throw new AdminError("Hãy chốt các buổi đang điểm danh trên app trước khi lưu trữ lớp.");
      }
      const layout = { ...w.layout }; delete layout[course.id];
      this.advance(tx,w,{ layout });
      tx.update(current.ref,{ archived: true });
    });
  }
  async decide(requestId, decision, reason) {
    reason = required(reason,"Lý do xử lý",1000);
    if (!["approved","rejected"].includes(decision)) throw new AdminError("Quyết định không hợp lệ.");
    return runTransaction(this.db, async tx => {
      const snapshot = await tx.get(this.ref(`attendanceRequests/${requestId}`));
      const request = snapshot.data();
      if (!request || request.state !== "pending") throw new AdminError("Yêu cầu đã được xử lý. Hãy tải lại.","conflict");
      const classRef = this.ref(`classes/${request.classId}`);
      const course = (await tx.get(classRef)).data();
      if (!course || course.ownerUid !== this.uid) throw new AdminError("Bạn không phụ trách lớp này.");
      let workspace, meeting, roll;
      if (decision === "approved") {
        if (course.archived) throw new AdminError("Lớp đã lưu trữ; chỉ có thể từ chối yêu cầu.");
        roll = course.roster[request.email];
        if (!roll) throw new AdminError("Email không còn trong danh sách lớp.");
        workspace = { ...(await tx.get(this.ref(`workspaces/${course.workspaceId}`))).data(), id: course.workspaceId };
        meeting = (await tx.get(this.ref(`classes/${request.classId}/meetings/${request.meetingId}`))).data();
        const edit = correction(meeting,roll,request.requestedStatus,reason,requestId);
        this.advance(tx,workspace);
        tx.update(this.ref(`classes/${request.classId}/meetings/${request.meetingId}`),edit);
      }
      tx.update(snapshot.ref,{ state: decision, decisionReason: reason, reviewerUid: this.uid, decidedAt: serverTimestamp() });
      // One deterministic notice per decision; transaction retries cannot duplicate it.
      tx.set(this.ref(`announcements/request-${requestId}`), {
        ownerUid: this.uid, recipientUid: request.uid, recipientEmail: request.email,
        title: decision === "approved" ? "Yêu cầu sửa điểm danh đã được duyệt" : "Yêu cầu sửa điểm danh bị từ chối",
        body: reason, classId: request.classId, meetingId: request.meetingId, at: serverTimestamp(),
      });
    });
  }
  async sendAnnouncement(course, input) {
    const title = required(input.title,"Tiêu đề",160), body = required(input.body,"Nội dung",3000);
    const meetingId = input.meetingId || "";
    if (meetingId && !course.meetings.some(m=>m.id===meetingId)) throw new AdminError("Buổi học không thuộc lớp.");
    const current = await getDocFromServer(this.ref(`classes/${course.id}`));
    if (!current.exists() || current.data().archived) throw new AdminError("Lớp đã lưu trữ.");
    const emails = input.audience === "class" ? Object.keys(current.data().roster) : [""];
    if (!emails.length) throw new AdminError("Lớp chưa có email sinh viên.");
    if (emails.length > 200) throw new AdminError("Mỗi lần gửi tối đa 200 sinh viên.");
    const batch = writeBatch(this.db);
    for (const email of emails) batch.set(doc(collection(this.db,"announcements")),{
      ownerUid: this.uid, recipientUid: email ? "" : this.uid, recipientEmail: email,
      title, body, classId: course.id, meetingId, at: serverTimestamp(),
    });
    await batch.commit();
    return emails.length;
  }
  async archivedClasses() { return rows(await getDocsFromServer(this.ownQuery("classes",where("archived","==",true)))); }
}
