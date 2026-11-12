import { doc, runTransaction, serverTimestamp } from "firebase/firestore";
import { AdminError, required } from "../admin/model.js";

export function parseSessionId(value) {
  const text=String(value||"").trim();
  const id=text.match(/(?:^|\/join\/)([A-Za-z0-9_-]{1,128})\/?(?:\?.*)?$/)?.[1];
  if(!id) throw new AdminError("Dán link điểm danh do giảng viên cung cấp hoặc mã phiên hợp lệ.");
  return id;
}
export async function createRequest(db,user,input) {
  const sessionId=parseSessionId(input.session),reason=required(input.reason,"Lý do đề nghị",1000);
  if(!["P","A"].includes(input.status))throw new AdminError("Chọn Có mặt hoặc Vắng.");
  return runTransaction(db,async tx=>{
    const session=await tx.get(doc(db,"attendanceSessions",sessionId));
    if(!session.exists())throw new AdminError("Không tìm thấy phiên. Kiểm tra lại link với giảng viên.");
    const s=session.data();
    const ref=doc(db,"attendanceRequests",`${s.classId}_${s.meetingId}_${user.uid}`);
    const own=await tx.get(ref);
    if(own.exists())throw new AdminError("Bạn đã gửi yêu cầu cho buổi này. Theo dõi kết quả trong danh sách yêu cầu.");
    tx.set(ref,{
      uid:user.uid,email:user.email.toLowerCase(),ownerUid:s.ownerUid,classId:s.classId,meetingId:s.meetingId,sessionId,
      requestedStatus:input.status,reason,state:"pending",createdAt:serverTimestamp(),
    });
  });
}
