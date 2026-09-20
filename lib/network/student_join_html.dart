import 'dart:convert';

String studentJoinHtml({
  required String challengeId,
  required String deviceId,
  required DateTime expiresAt,
  required bool requiresOtp,
  required bool requiresFirebase,
  required String courseLabel,
  required int slotNumber,
}) {
  final config = jsonEncode({
    'challengeId': challengeId,
    'deviceId': deviceId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'requiresOtp': requiresOtp,
    'requiresFirebase': requiresFirebase,
  }).replaceAll('<', r'\u003c');
  final safeCourse = const HtmlEscape().convert(courseLabel);
  final authNote = requiresFirebase
      ? 'Email phải được xác minh trong Firebase. Mật khẩu chỉ dùng để đăng nhập và không được lưu trên trang này.'
      : 'Chế độ demo: email chỉ được đối chiếu với danh sách lớp, chưa xác minh quyền sở hữu email.';
  return '''<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>Điểm danh · FAP Attendance</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#fff8f4;color:#243047;font:16px/1.5 system-ui,"Segoe UI",sans-serif;display:grid;place-items:center;padding:20px}
.card{width:min(100%,450px);background:#fff;border:1px solid #f0ddd4;border-radius:22px;box-shadow:0 20px 50px #54271113;padding:30px}
.brand{font-size:13px;letter-spacing:.1em;font-weight:800;color:#c93c13}.dot{display:inline-block;width:10px;height:10px;border-radius:50%;background:#f4511e;margin-right:9px}
h1{font-size:30px;line-height:1.18;margin:24px 0 8px}p{color:#667085;margin:0 0 20px}.meta{background:#fff4ee;border-radius:12px;padding:12px 14px;color:#243047;font-weight:700;margin-bottom:18px}
.timer{font-size:15px;color:#b73813;font-weight:700;margin-bottom:18px}.timer strong{font-variant-numeric:tabular-nums}
label{display:block;font-weight:650;margin:14px 0 6px}input{width:100%;border:1px solid #e7cfc4;border-radius:11px;padding:13px 14px;font:inherit;outline:none}input:focus{border-color:#f4511e;box-shadow:0 0 0 3px #f4511e20}
button{width:100%;border:0;border-radius:11px;background:#f4511e;color:#fff;font:700 16px system-ui;padding:14px;margin-top:22px;cursor:pointer}button:disabled{opacity:.5;cursor:not-allowed}
#message{min-height:24px;margin-top:16px;font-weight:650;color:#bd3425}.ok{color:#16835d!important}.foot{font-size:12px;color:#87909f;margin-top:22px;text-align:center}
</style></head><body><main class="card">
<div class="brand"><span class="dot"></span>FAP ATTENDANCE</div>
<h1>Điểm danh sinh viên</h1><p>Đăng nhập và gửi điểm danh trước khi lượt quét hết hạn.</p>
<div class="meta">$safeCourse · Slot $slotNumber</div>
<div class="timer">Thời gian còn lại: <strong id="remaining">02:00</strong></div>
<form id="checkin"><label for="email">Email sinh viên trong danh sách lớp</label><input id="email" type="email" required autocomplete="email" placeholder="student@example.com">
<div id="passwordRow" hidden><label for="password">Mật khẩu Firebase</label><input id="password" type="password" autocomplete="current-password"></div>
<div id="otpRow" hidden><label for="otp">Mã bí mật 6 số trên màn hình GV</label><input id="otp" inputmode="numeric" maxlength="6" pattern="[0-9]{6}"></div>
<button id="submit" type="submit">Gửi điểm danh</button></form><div id="message" role="status" aria-live="polite"></div>
<div class="foot">$authNote</div></main>
<script>
const config=$config;
const form=document.getElementById('checkin'),submit=document.getElementById('submit'),message=document.getElementById('message');
document.getElementById('otpRow').hidden=!config.requiresOtp;
document.getElementById('passwordRow').hidden=!config.requiresFirebase;
document.getElementById('password').required=config.requiresFirebase;
document.getElementById('otp').required=config.requiresOtp;
function tick(){const left=Math.max(0,Math.ceil((Date.parse(config.expiresAt)-Date.now())/1000));document.getElementById('remaining').textContent=String(Math.floor(left/60)).padStart(2,'0')+':'+String(left%60).padStart(2,'0');if(left===0){submit.disabled=true;message.textContent='Đã quá 2 phút. Hãy quét QR mới.';}}
tick();setInterval(tick,1000);
async function post(path,body,token){const response=await fetch(path,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body),cache:'no-store'});const result=await response.json();if(!response.ok||result.accepted===false)throw new Error(result.message||'Không gửi được điểm danh.');return result;}
form.addEventListener('submit',async(event)=>{event.preventDefault();if(Date.now()>=Date.parse(config.expiresAt))return tick();submit.disabled=true;message.className='';message.textContent='Đang xác minh…';try{const email=document.getElementById('email').value.trim();let token;if(config.requiresFirebase){const login=await post('/api/v1/student-sign-in',{email,password:document.getElementById('password').value});token=login.idToken;}const result=await post('/api/v1/check-ins',{challengeId:config.challengeId,deviceId:config.deviceId,email,otp:config.requiresOtp?document.getElementById('otp').value:undefined},token);message.className='ok';message.textContent=result.message||'Điểm danh thành công.';form.hidden=true;}catch(error){message.textContent=error.message||String(error);if(Date.now()<Date.parse(config.expiresAt))submit.disabled=false;}});
</script></body></html>''';
}
