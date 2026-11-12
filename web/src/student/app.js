import "../admin/style.css";
import "./style.css";
import { onAuthStateChanged, signInWithPopup, signOut } from "firebase/auth";
import { collection, query, where, onSnapshot, getDocFromServer, doc } from "firebase/firestore";
import { auth, db, googleProvider } from "../firebase-client.js";
import { escapeHtml as h, dateText, messageFor, showDialog } from "../ui.js";
import { createRequest } from "./repository.js";

document.title="Hộp thư & yêu cầu · FAP Attendance";
document.body.className="admin-body student-body";
document.body.innerHTML='<div id="student-root"></div>';
const root=document.getElementById("student-root");
let stops=[],generation=0,requests=[],notices=new Map(),labels=new Map(),error="",loading=true;
const sessionFromLink=new URLSearchParams(location.search).get("session")||"";
const stateLabels={pending:"Chờ giảng viên",approved:"Đã duyệt",rejected:"Đã từ chối"};
function render() {
  const user=auth.currentUser;
  root.innerHTML=`<header class="student-header"><a class="wordmark" href="/">F<span>FAP Attendance</span></a><div>${user?`<span class="muted">${h(user.email)}</span><button id="logout" class="secondary">Đổi tài khoản</button>`:'<a href="/admin">Không gian giảng viên →</a>'}</div></header><main class="student-main"><div class="page-heading"><div><p class="overline">KHÔNG GIAN SINH VIÊN</p><h1>Hộp thư & yêu cầu</h1><p class="muted">Theo dõi phản hồi và trao đổi về kết quả điểm danh của bạn.</p></div>${user?'<button id="new-request" class="primary">＋ Yêu cầu sửa điểm danh</button>':""}</div><p id="student-feedback" role="status" aria-live="polite" class="feedback" hidden></p>${!user ? `<section class="panel student-login"><h2>Đăng nhập để xem thông tin của bạn</h2><p>Dùng tài khoản Google có email trong danh sách lớp.</p><button id="login" class="primary">Đăng nhập bằng Google</button><p id="login-error" class="form-error" role="alert"></p></section>` : error ? `<div class="error-panel" role="alert"><p>${h(error)}</p><button id="reload" class="secondary">Tải lại trang</button></div>` : loading ? '<div class="loading" role="status"><span class="spinner"></span>Đang tải hộp thư…</div>' : content()}</main><footer class="student-footer">FAP Attendance · Chỉ hiển thị dữ liệu gửi tới tài khoản của bạn</footer>`;
  const login=document.getElementById("login");if(login)login.onclick=async()=>{login.disabled=true;try{await signInWithPopup(auth,googleProvider);}catch(e){const el=document.getElementById("login-error");if(el)el.textContent=messageFor(e);}finally{login.disabled=false;}};
  const logout=document.getElementById("logout");if(logout)logout.onclick=async()=>{try{await signOut(auth);}catch(e){error=messageFor(e);render();}};
  const reload=document.getElementById("reload");if(reload)reload.onclick=()=>location.reload();
  const create=document.getElementById("new-request");if(create)create.onclick=requestForm;
}
function content(){
  const items=[...notices.values()].sort((a,b)=>(b.at?.toMillis?.()||0)-(a.at?.toMillis?.()||0));
  return `<div class="student-columns"><section class="panel"><div class="panel-heading"><div><h2>Thông báo của bạn</h2><p>${items.length} thông báo</p></div></div>${items.length ? `<div class="notice-list">${items.map(n=>`<article class="notice-item"><div><div class="notice-meta">${dateText(n.at)}</div><h3>${h(n.title)}</h3><p>${h(n.body)}</p></div></article>`).join("")}</div>` : '<div class="empty-state"><h3>Hộp thư đang trống</h3><p>Thông báo lớp học và kết quả xử lý yêu cầu sẽ xuất hiện tại đây.</p></div>'}</section><section class="panel"><div class="panel-heading"><div><h2>Yêu cầu đã gửi</h2><p>${requests.length} yêu cầu · mỗi buổi gửi một lần</p></div></div>${requests.length ? `<div class="student-requests">${[...requests].sort((a,b)=>(b.createdAt?.toMillis?.()||0)-(a.createdAt?.toMillis?.()||0)).map(r=>`<article><div class="notice-meta"><span>${dateText(r.createdAt)}</span><span class="pill ${h(r.state)}">${stateLabels[r.state]||h(r.state)}</span></div><h3>${h(labels.get(r.sessionId)||"Buổi học")}</h3><p>Đề nghị: <strong>${r.requestedStatus==="P"?"Có mặt (P)":"Vắng (A)"}</strong></p><p class="preserve-lines">${h(r.reason)}</p>${r.decisionReason?`<div class="soft-note"><strong>Phản hồi giảng viên</strong><p class="preserve-lines">${h(r.decisionReason)}</p><small>${dateText(r.decidedAt)}</small></div>`:""}</article>`).join("")}</div>` : '<div class="empty-state"><h3>Chưa gửi yêu cầu</h3><p>Sau khi giảng viên chốt buổi, dùng link điểm danh của buổi đó để đề nghị sửa kết quả.</p></div>'}</section></div>`;
}
function requestForm(){
  const account=auth.currentUser;
  showDialog("Yêu cầu sửa điểm danh",`<label>Link hoặc mã phiên điểm danh<input name="session" required value="${h(sessionFromLink)}" placeholder="https://fap-attendance-71655.web.app/join/…"></label><label>Kết quả đề nghị<select name="status"><option value="P">Có mặt (P)</option><option value="A">Vắng (A)</option></select></label><label>Lý do và thông tin đối chiếu<textarea name="reason" required maxlength="1000" rows="5" placeholder="Giải thích rõ trường hợp cần kiểm tra…"></textarea></label><p class="help-note">Chỉ gửi sau khi buổi học đã chốt, cho kết quả khác hiện tại. Email Google phải thuộc danh sách lớp. Mỗi sinh viên gửi một yêu cầu cho mỗi buổi; giảng viên sẽ xem xét trước khi sửa.</p>`,async input=>{
    try{await createRequest(db,account,input);}
    catch(e){if(e.code==="permission-denied"){e.name="AdminError";e.message="Chưa thể gửi: buổi phải được chốt, email phải thuộc lớp và kết quả đề nghị phải khác kết quả hiện tại. Hãy kiểm tra với giảng viên.";}throw e;}
    const el=document.getElementById("student-feedback");if(el){el.textContent="Đã gửi yêu cầu. Bạn có thể theo dõi phản hồi tại đây.";el.hidden=false;}
  },{label:"Gửi yêu cầu"});
}
onAuthStateChanged(auth,user=>{
  const current=++generation;stops.forEach(s=>s());stops=[];
  document.querySelectorAll("dialog").forEach(d=>d.close());
  requests=[];notices=new Map();labels=new Map();error="";loading=Boolean(user);render();
  if(!user)return;
  let received=0;
  const fail=e=>{if(current===generation){error=messageFor(e);loading=false;render();}};
  const ready=()=>{received++;if(received>=3)loading=false;render();};
  stops.push(onSnapshot(query(collection(db,"attendanceRequests"),where("uid","==",user.uid)),snapshot=>{
    if(current!==generation)return;
    requests=snapshot.docs.map(d=>({...d.data(),id:d.id}));ready();
    for(const id of new Set(requests.map(r=>r.sessionId)))if(!labels.has(id)){
      labels.set(id,"Buổi học");getDocFromServer(doc(db,"attendanceSessions",id)).then(s=>{if(current===generation){labels.set(id,s.data()?.label||"Buổi học");render();}}).catch(()=>{});
    }
  },fail));
  // Keep each query's result separate so removed documents disappear correctly.
  const sources=[new Map(),new Map()];
  [where("recipientUid","==",user.uid),where("recipientEmail","==",user.email.toLowerCase())].forEach((filter,index)=>{
    stops.push(onSnapshot(query(collection(db,"announcements"),filter),snapshot=>{
      if(current!==generation)return;
      sources[index]=new Map(snapshot.docs.map(d=>[d.id,{...d.data(),id:d.id}]));
      notices=new Map([...sources[0],...sources[1]]);ready();
    },fail));
  });
});
window.addEventListener("pagehide",()=>stops.forEach(s=>s()));
