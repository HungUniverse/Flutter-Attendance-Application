# Hướng dẫn thu minh chứng và nộp Lab 3

Hướng dẫn này áp dụng cho FAP Attendance trên Windows và Android. Backend Node chạy trên laptop. Android và trình duyệt mở trang điểm danh qua Cloudflare Quick Tunnel. Dùng project Firebase `fap-attendance-71655`.

| Việc cần làm | Khi nào có thể đánh dấu xong |
| --- | --- |
| [Khởi động bản demo](#1-khởi-động-bản-demo) | `/health` trả `ready: true` qua HTTPS, Android mở được app và đăng nhập được |
| [Kiểm chứng Firebase](#2-kiểm-chứng-sáu-dịch-vụ-firebase) | Có kết quả thực tế, ảnh hoặc clip và một ca lỗi cho mỗi dịch vụ |
| [Chạy ARTEMIS](#3-chạy-artemis-và-kiểm-thử-khám-phá) | Có ít nhất 10 ca, mỗi ca ít nhất 3 lượt, tỷ lệ đạt, log và một phiên khám phá 15–30 phút |
| [Review PR bằng AI](#4-review-pr-bằng-ai-và-đưa-mã-lên-github) | Có 1 PR, ít nhất 5 phát hiện thuộc 2 nhóm, quyết định cho từng mục và commit sửa ít nhất 3 mục |
| [Hoàn thiện hồ sơ](#5-hoàn-thiện-hồ-sơ-nộp) | Mở được repo GitHub, báo cáo PDF 8–12 trang, slide PDF 12–15 trang và video 5–10 phút |

## 1. Khởi động bản demo

### Chuẩn bị tài khoản và dữ liệu

- Dùng tài khoản Google giảng viên mà backend đã cho phép. Nếu demo đồng bộ, dùng cùng tài khoản này trên Windows và Android. Chuẩn bị một tài khoản Google sinh viên có email khớp danh sách và một tài khoản thử thứ hai để kiểm tra quyền Storage.
- Tạo bản sao của tệp ODS hoặc XLSX để kiểm thử. Giữ nguyên các cột `Class`, `RollNumber`, `Email`, `FullName` hoặc tên cột tương đương trong mẫu. Chỉ để 2–3 sinh viên demo. Dùng mã học kỳ riêng như `LAB3-DEMO-01` để dễ phân biệt với dữ liệu đang dùng.
- Nạp trước một lớp có buổi vào đúng ngày demo. Nếu buổi đang hiện **Sắp tới**, kiểm tra ngày bắt đầu và lịch lớp trước khi thử tạo link. Với bảng tính tự tạo, mã đầu của sheet quyết định nhóm ngày học. Ví dụ `11_PRM393_DEMO01` thuộc nhóm Thứ Hai/Thứ Năm, `21_PRM393_DEMO01` thuộc nhóm Thứ Ba/Thứ Sáu và `31_PRM393_DEMO01` thuộc nhóm Thứ Tư/Thứ Bảy. Chọn hai buổi mỗi tuần nếu cần cả hai ngày của nhóm.
- Tạo một thư mục lưu minh chứng trên laptop, chẳng hạn `D:\Fall2026\PRM393\Lab3-minh-chung`, với các thư mục con `firebase`, `artemis`, `ai-review` và `submission`. Đặt tên ảnh theo mục và thao tác, ví dụ `auth-03-console-users.png`.

### Bật backend và lấy URL HTTPS

Nếu backend và tunnel còn chạy, dùng URL HTTPS đang hoạt động và chuyển đến bước kiểm tra `/health`. Nếu cần khởi động lại, mở một tab PowerShell dành cho tunnel.

```powershell
cloudflared tunnel --url http://127.0.0.1:8789
```

Sao chép URL `https://….trycloudflare.com` vừa hiện. Giữ tab này mở. Nếu hostname mới khác hostname lần trước, vào **Firebase → Authentication → Settings → Authorized domains → Add domain** và nhập phần hostname. Quick Tunnel cấp URL tạm cho lần chạy. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) · [Tên miền đăng nhập Firebase](https://support.google.com/firebase/answer/6400741)

Mở tab PowerShell thứ hai. Các lệnh bên dưới dùng `backend/.env` đã thiết lập và yêu cầu bạn nhập lại URL, đường dẫn khóa Admin SDK và email giảng viên cho tab mới. Điền đường dẫn đến tệp JSON quản trị bạn đã dùng khi chạy Node trước đó.

```powershell
cd D:\Fall2026\PRM393\Project_PRM393\backend
$env:PUBLIC_ORIGIN = (Read-Host 'Dan URL HTTPS cua tunnel dang chay').Trim().TrimEnd('/')
$env:GOOGLE_APPLICATION_CREDENTIALS = (Read-Host 'Nhap duong dan den JSON Firebase Admin SDK').Trim().Trim('"')
$env:TEACHER_EMAILS = (Read-Host 'Nhap email Google cua giang vien demo').Trim()
node --env-file=.env server.mjs
```

Khi terminal hiện **Attendance relay ready**, mở `http://127.0.0.1:8789/health` và mở `/health` trên URL tunnel trong trình duyệt. Cả hai phải trả `{"ready":true}`. Nếu báo `EADDRINUSE`, kiểm tra cửa sổ backend đang chạy để dùng lại hoặc khởi động lại đúng tiến trình đó. Nếu tab tunnel báo lỗi kết nối, kiểm tra `/health` trên cổng `8789` trước. [Cấu hình backend](../backend/README.md)

### Bật Android Emulator và công cụ demo

1. Trong Android Studio, mở **Device Manager**, bấm nút Play của máy ảo có Google Play và đợi màn hình Android xuất hiện.
2. Mở một tab PowerShell mới và chạy các lệnh dưới đây. Thay `emulator-5554` nếu `flutter devices` hiển thị ID khác. Nếu không tìm thấy `adb.exe`, xem **Android Studio → SDK Manager → Android SDK Location** và đổi đường dẫn cho khớp.

```powershell
cd D:\Fall2026\PRM393\Project_PRM393
flutter devices
$deviceId = 'emulator-5554'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
& $adb -s $deviceId shell setprop debug.firebase.analytics.app vn.edu.fpt.fap_attendance
$apiUrl = (Read-Host 'Dan URL HTTPS cua tunnel dang chay').Trim().TrimEnd('/')
flutter run -d $deviceId "--dart-define=ATTENDANCE_API_URL=$apiUrl" --dart-define=LAB3_DEMO_TOOLS=true
```

3. Vào **Tài khoản & cài đặt** và kiểm tra có phần **Khu vực kiểm thử Lab 3**. Nếu thiếu, dừng lượt `flutter run` cũ rồi chạy lại với `LAB3_DEMO_TOOLS=true`.
4. Khi cần mở Windows để minh họa đồng bộ, chạy `flutter run -d windows "--dart-define=ATTENDANCE_API_URL=$apiUrl"` trong tab riêng. Nhập lại `$apiUrl` ở tab đó. Đăng nhập cùng Google giảng viên trên cả hai app.

### Bổ sung minh chứng FlutterFire CLI

Đây là bước khởi tạo ở trang 3 của đề. Thực hiện từ thư mục gốc trên một nhánh có thể xem lại diff. Giữ bản APK demo đã chạy được trước khi thử cấu hình. Nếu đã cài Firebase CLI hoặc FlutterFire CLI, bỏ qua lệnh cài tương ứng.

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
dart pub global run flutterfire_cli:flutterfire configure --project=fap-attendance-71655 --platforms=android
```

Đăng nhập bằng tài khoản có quyền trên Firebase project. Kiểm tra CLI chọn ứng dụng Android `vn.edu.fpt.fap_attendance` đã đăng ký. Lưu log hoàn tất, xem các tệp thay đổi rồi build lại Android để xác nhận. [Thiết lập FlutterFire](https://firebase.google.com/docs/flutter/setup)

## 2. Kiểm chứng sáu dịch vụ Firebase

Mở đúng project `fap-attendance-71655` trong [Firebase Console](https://console.firebase.google.com/). Bật Analytics DebugView từ đầu. Làm Auth, Analytics và Storage trong cùng một lượt nghiệp vụ, sau đó làm FCM, Remote Config và Crashlytics. Với mỗi ca, ghi thiết bị, thời điểm, thao tác, kết quả thực tế và tên ảnh hoặc log.

### 2.1 Authentication

1. Trên Android vào **Tài khoản & cài đặt → Đăng xuất** nếu đang đăng nhập. Chụp `auth-01-login.png`.
2. Chạm **Đăng nhập với Google**, rồi hủy ở hộp chọn tài khoản. Chụp `auth-02-cancel.png` khi app hiện thông báo và vẫn ở màn đăng nhập.
3. Đăng nhập lại bằng Google giảng viên. Chụp màn lịch/lớp. Mở **Firebase → Authentication → Users** và chụp dòng tài khoản vừa dùng.
4. Sau khi hoàn thành các ca cần đăng nhập, đăng xuất và bấm Back. Ghi kết quả màn nghiệp vụ có bị chặn hay không. Khi cần dùng lại app, đăng nhập lại trước ca tiếp theo.

**Đủ minh chứng khi** có ảnh trước/sau, dòng Users, ca hủy và ca đăng xuất kèm kết quả bảo vệ màn hình.

### 2.2 Analytics DebugView

1. Trong Console, mở **Analytics → DebugView** và chọn đúng thiết bị debug nếu có nhiều thiết bị. Nếu không có sự kiện, kiểm tra đúng project và package, chạy lại lệnh `adb ... setprop` ở mục 1 rồi mở lại app.
2. Làm các thao tác sau trên **Android**. Trong DebugView, bấm sự kiện để mở tham số. Lưu ảnh đủ từng sự kiện. Một ảnh có thể dùng cho nhiều sự kiện nếu thấy rõ tên và phần tham số cần đối chiếu.

| Thao tác | Tên sự kiện | Tham số kiểm tra |
| --- | --- | --- |
| Đăng nhập Google thành công | `login` | `method=google` |
| Xác nhận **Nạp danh sách lớp** thành công | `markbook_import` | `class_count` |
| Chuyển **Qua link ↔ Thủ công** | `attendance_mode_selected` | `mode` |
| Mở buổi hôm nay và bấm **Tạo link điểm danh** đến khi nhận được link mới | `attendance_link_created` | Tên sự kiện |
| Chuyển sang **Thủ công** và ghi P/A cho một sinh viên | `attendance_marked` | `mode`, `status` |
| Xác nhận **Chốt danh sách** | `attendance_closed` | `present_count`, `absent_count` |
| Mở chi tiết một sinh viên | `student_detail_viewed` | Tên sự kiện |
| Xuất báo cáo JSON hoặc CSV | `attendance_exported` | `format` |
| Bật sao lưu, chờ upload thành công | `report_uploaded` | `format` |
| Đăng xuất ở cuối lượt | `logout` | Tên sự kiện |

3. Đối chiếu tên, kiểu tham số và câu hỏi sản phẩm với kế hoạch. Cho ca lỗi, thử hủy một thao tác như nạp danh sách trước khi xác nhận và ghi nhận sự kiện thành công tương ứng có xuất hiện hay không. Ghi rõ đây là **kiểm tra việc phát sự kiện của app**. Ca giả lập dịch vụ Analytics thất bại đã có trong test `tracking failure never breaks attendance`. [Kế hoạch Analytics](analytics-plan.md) · [DebugView](https://firebase.google.com/docs/analytics/debugview) · [Ca kiểm tra Analytics lỗi](../test/lab3/teacher_view_model_test.dart)

### 2.3 Cloud Storage

1. Vào **Firebase → Storage → Rules**. So sánh với [storage.rules trong repo](../firebase/storage.rules). Nếu Console còn rules cũ, cập nhật bản mới và bấm **Publish**. Chụp phần rules theo UID.
2. Trên app mở một buổi **Đã chốt**, vào **Xuất kết quả điểm danh**, chọn **JSON** hoặc **CSV**, tích **Sao lưu Firebase Storage** rồi bấm **Xuất file**. Chụp hoặc quay màn có tiến độ, kết quả thành công và URL. Báo cáo nhỏ có thể tải xong nhanh. Che phần token trong URL khi chia sẻ ảnh.
3. Trong **Storage → Files**, mở thư mục báo cáo của học kỳ demo. Đối chiếu đường dẫn app hiển thị với tệp trên Console.

```text
reports/<uid>/<học-kỳ>/<môn>/<lớp>/<ngày>_Slot-<số-buổi>/<tên-tệp>.json
```

4. Trong **Storage → Rules → Rules Playground**, chọn thao tác `get` và nhập đúng đường dẫn của tệp vừa xuất. Chạy một lượt với UID chủ sở hữu, một lượt với UID khác và lưu kết quả `Allow`/`Deny`. Có thể thử thêm chế độ chưa đăng nhập. Dùng UID từ Authentication của hai tài khoản demo. [Firebase Rules Playground](https://firebase.google.com/docs/rules/simulator)
5. Tắt mạng **trên Android Emulator** và thử sao lưu một báo cáo demo. Ghi lại lỗi hoặc thời gian chờ, kiểm tra tệp trên thiết bị vẫn còn. Bật lại mạng, bấm **Sao lưu Storage / Thử lại** và đối chiếu tệp xuất hiện trên Console. Nếu SDK thử lại lâu, ghi thời gian quan sát và trạng thái thực tế. [Cấu trúc lưu tệp trong dự án](STORAGE_LAYOUT.md)

### 2.4 Firebase Cloud Messaging

1. Đăng nhập trên Android. Vào **Tài khoản & cài đặt → Kiểm tra quyền và token FCM**. Cấp quyền thông báo, rồi sao chép token của máy ảo vào Console. Lấy lại token nếu vừa đăng xuất/đăng nhập lại.
2. Vào **Firebase → Messaging → tạo thông báo**. Nhập tiêu đề và nội dung demo. Chọn **Send test message**, dán token của máy ảo rồi bấm **Test**. Chỉ gửi đến thiết bị test. [Gửi tin thử bằng FCM](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
3. Gửi ba lượt. Đặt tiêu đề khác nhau để đối chiếu lịch sử.

| Tiêu đề ví dụ | Trạng thái Android trước khi gửi | Kết quả cần ghi |
| --- | --- | --- |
| `Lab 3 - Foreground` | App đang hiển thị | Mở tab **Thông báo** và tìm tin vừa nhận |
| `Lab 3 - Background` | Bấm Home, app còn trong danh sách gần đây | Chụp thông báo hệ thống, chạm và ghi màn đích |
| `Lab 3 - Closed` | Mở màn hình ứng dụng gần đây, vuốt đóng app | Chụp thông báo, chạm để mở lại app và ghi màn đích |

Ở lượt **Closed**, dùng màn hình ứng dụng gần đây. **Force stop** trong Android Settings là trạng thái khác và cần mở lại app trước khi nhận FCM tiếp. [Trạng thái nhận tin trên Android](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)

4. Để kiểm tra mở đúng buổi học, gửi thêm tin có dữ liệu `uid`, `classId`, `meetingId`. Với học kỳ đã đồng bộ, xem các giá trị trong Firestore theo đường dẫn `teachers/<uid>/workspaces/<tài-liệu-học-kỳ>` và các trường `workspace.classes[].id`, `workspace.classes[].meetings[].id`. Dùng **Custom data** của thông báo. Tin có lớp/buổi hợp lệ sẽ mở màn điểm danh. Tin thử chỉ có tiêu đề và nội dung sẽ mở **Thông báo** khi chạm. [Dữ liệu tùy chỉnh trong Firebase Console](https://firebase.google.com/docs/cloud-messaging/send/firebase-console)
5. Vào **Android Settings → Apps → FAP Attendance → Notifications**, tắt quyền và kiểm tra app vẫn mở được phần nghiệp vụ. Ghi trạng thái trên máy. Bật lại quyền sau khi xong.

Nếu lượt gửi thử ở bước 4 không mang dữ liệu tùy chỉnh, có thể gửi riêng đến token demo bằng Firebase Admin SDK. Chạy khối sau trong PowerShell ở thư mục backend đã cài `node_modules`. Cần tài khoản dịch vụ có quyền gửi FCM của project. Khối này hỏi giá trị lúc chạy và chỉ in mã tin đã gửi.

```powershell
cd D:\Fall2026\PRM393\Project_PRM393\backend
$env:GOOGLE_APPLICATION_CREDENTIALS = (Read-Host 'Duong dan JSON Firebase Admin SDK').Trim().Trim('"')
$env:LAB3_FCM_TOKEN = Read-Host 'Token cua Android Emulator demo'
$env:LAB3_FCM_UID = Read-Host 'UID tai khoan giang vien demo'
$env:LAB3_FCM_CLASS_ID = Read-Host 'ID lop demo'
$env:LAB3_FCM_MEETING_ID = Read-Host 'ID buoi hoc demo'
@'
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

initializeApp({ credential: applicationDefault(), projectId: 'fap-attendance-71655' });
const id = await getMessaging().send({
  token: process.env.LAB3_FCM_TOKEN,
  notification: { title: 'Lab 3 - Mo buoi hoc', body: 'Cham de mo buoi demo.' },
  data: {
    uid: process.env.LAB3_FCM_UID,
    classId: process.env.LAB3_FCM_CLASS_ID,
    meetingId: process.env.LAB3_FCM_MEETING_ID,
  },
});
console.log('Da gui:', id);
'@ | node --input-type=module
Remove-Item Env:LAB3_FCM_TOKEN,Env:LAB3_FCM_UID,Env:LAB3_FCM_CLASS_ID,Env:LAB3_FCM_MEETING_ID
```

Lưu ảnh Console cho ba lượt gửi thử và ảnh hoặc video màn đích cho lượt có dữ liệu. [Gửi đến một thiết bị bằng Firebase Admin SDK](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk)

### 2.5 Remote Config

1. Trong Console, mở **Remote Config**. Tạo hai tham số dưới đây nếu chưa có, ghi lại giá trị hiện tại rồi bấm **Publish changes**.

| Tham số | Kiểu | Giá trị để thử |
| --- | --- | --- |
| `enable_link_attendance` | Boolean | `false` |
| `export_help_message` | String | `Minh chứng Lab 3: kiểm tra báo cáo trước khi sao lưu.` |

2. Trước khi đổi, chụp màn **Tài khoản & cài đặt** và trang **Xuất kết quả**. Dùng buổi chưa có link đang hoạt động để thử thay đổi bật/tắt tạo link.
3. Sau khi publish, bấm **Tài khoản & cài đặt → Cập nhật cấu hình**. Nếu vừa fetch, chờ đủ một phút với bản debug rồi thử lại. Mở màn điểm danh và màn xuất. Chụp trạng thái **Tạo link: Tạm tắt** và dòng hướng dẫn xuất mới, giữ nguyên bản app đang chạy.
4. Tắt mạng trên Android, thử cập nhật lại sau khoảng fetch tối thiểu. Ghi nhận app giữ cấu hình đã tải hoặc dùng giá trị mặc định trên bản cài chưa từng tải, kèm thông báo thực tế. Bật lại mạng, khôi phục hai giá trị ban đầu trên Console và cập nhật app. [Cấu hình và chu kỳ fetch của dự án](FIREBASE_ANDROID_SETUP.md#4-remote-config) · [Firebase Remote Config](https://firebase.google.com/docs/remote-config/flutter/get-started)

### 2.6 Crashlytics

1. Kiểm tra app đang đăng nhập Google. Dùng một buổi demo **đang mở hôm nay và chưa có link**, mở màn **Tạo link điểm danh**, tắt mạng Android rồi bấm tạo link. Chờ thông báo lỗi trong app và chụp màn hình. Bật lại mạng để app có thể gửi báo cáo. Nhánh lỗi này đi qua ViewModel và ghi non-fatal với `operation=create_link`.
2. Làm bước này cuối lượt demo. Vào **Tài khoản & cài đặt → Crash thử nghiệm → Gây crash**. App sẽ đóng. Mở lại app và giữ thiết bị kết nối Internet để gửi báo cáo.
3. Vào **Firebase → Crashlytics**, chọn đúng app Android. Tìm một sự kiện non-fatal và một sự kiện crash thử nghiệm. Mở chi tiết, đối chiếu **user ID** và khóa **`operation`**. Nếu Console chưa hiện, đợi vài phút và xác nhận đã mở lại app sau crash.
4. Lưu ảnh chi tiết của từng sự kiện. Khi làm slide, dùng bản che thông tin tài khoản nếu có dữ liệu nhận dạng. [Cách kiểm chứng Crashlytics](https://firebase.google.com/docs/crashlytics/flutter/test-implementation)

Sau khi thu xong Analytics, có thể tắt chế độ DebugView bằng lệnh sau trong tab đã khai báo `$adb` và `$deviceId`.

```powershell
& $adb -s $deviceId shell setprop debug.firebase.analytics.app .none.
```

## 3. Chạy ARTEMIS và kiểm thử khám phá

### Cài và kết nối Android

Dùng bản ARTEMIS mà giảng viên chỉ định nếu lớp đã có link. Nếu dùng **Google ARTEMIS**, đây là cách mở giao diện trên Windows theo hướng dẫn của dự án. Chạy ở một thư mục riêng ngoài repo FAP Attendance. Nếu đã clone, mở thư mục `artemis` hiện có và chạy từ dòng `cd artemis` tương ứng.

```powershell
cd D:\Fall2026\PRM393
git clone https://github.com/google/artemis.git
cd artemis
.\start.bat
```

1. Làm theo hướng dẫn cài Python/uv và công cụ Android trên màn hình. Mở máy ảo trước, kiểm tra nó xuất hiện trong `adb devices`.
2. Trong giao diện ARTEMIS, kết nối đúng máy ảo và cấu hình khóa API mô hình mà lớp sử dụng. Chỉ nhập khóa vào phần cấu hình của công cụ. Dùng tài khoản và danh sách demo trên thiết bị.
3. Chạy một lệnh ngắn để kiểm tra kết nối, ví dụ yêu cầu mở **FAP Attendance** và báo tiêu đề màn hiện tại. Xác nhận kết quả trên màn hình máy ảo rồi bắt đầu các ca. [Hướng dẫn Google ARTEMIS trên Windows](https://github.com/google/artemis#quick-start)

### Chạy 10 ca, mỗi ca 3 lượt

Dùng [bảng nghiệm thu A01–A14](LAB3_ACCEPTANCE.md) để lấy điều kiện đầu và kết quả mong đợi. Chọn tối thiểu 10 ca. Bộ A01–A10 bao phủ ba luồng và có trình chọn tệp hoặc bảng chia sẻ Android.

| Ca | Thao tác cần quan sát | Cách chuẩn bị cho lượt kế tiếp |
| --- | --- | --- |
| A01 | Đăng nhập Google, thấy màn lịch/lớp | Đăng xuất, quay về màn đăng nhập |
| A02 | Mở Google Sign-In, hủy rồi bấm Back | Quay về màn đăng nhập |
| A03 | Mở trình chọn tệp Android, chọn ODS/XLSX và kiểm tra số lớp, số sinh viên khi xem trước rồi nạp | Dùng mã học kỳ demo riêng cho từng lượt |
| A04 | Nạp lại cùng học kỳ và kiểm tra một kết quả đã ghi còn nguyên | Chuẩn bị học kỳ có sẵn một buổi đã ghi hoặc đã chốt |
| A05 | Ghi P/A, đổi chế độ rồi quay lại, kiểm tra số đếm và ô chưa ghi | Dùng buổi hoặc học kỳ demo có bản ghi ban đầu đã biết |
| A06 | Tạo link, bấm **Chia sẻ** để mở bảng chia sẻ Android, gửi bằng tài khoản sinh viên demo và đối chiếu kết quả | Dừng link cũ, dùng buổi hoặc lượt demo mới |
| A07 | Tài khoản ngoài lớp thử gửi trên link còn mở, đối chiếu số có mặt | Dùng link hoạt động và cùng điều kiện trước lượt gửi |
| A08 | Hủy xác nhận chốt, kiểm tra chưa đổi. Sau đó chốt và đối chiếu số có mặt/vắng | Dùng buổi demo mới cho từng lượt |
| A09 | Mở **Sửa P/A**, xóa lý do, bấm Lưu, rồi nhập lý do hợp lệ và lưu lại | Chuẩn bị một bản ghi đã chốt, ghi lại trạng thái đầu mỗi lượt |
| A10 | Xuất JSON hoặc CSV và kiểm tra tên tệp, lớp, buổi và số dòng | Dùng buổi đã chốt và biết trước kết quả |

Với ca cần thao tác trên trình duyệt sinh viên ngoài máy ảo, ghi rõ phần nào ARTEMIS thực hiện và phần nào do người kiểm thử phối hợp. Đánh giá kết quả dựa trên giá trị nhìn thấy, như số có mặt trước/sau hoặc trạng thái vẫn giữ nguyên khi hủy.

Ví dụ mô tả cho A09:

> Mở FAP Attendance đang đăng nhập, vào một buổi demo đã chốt, mở chi tiết sinh viên và chọn Sửa P/A. Chọn trạng thái khác, xóa nội dung lý do và bấm Lưu. Xác minh hộp sửa vẫn mở, có thông báo yêu cầu lý do và kết quả cũ vẫn được giữ. Nhập lý do “Kiểm tra Lab 3”, bấm Lưu và mở lại chi tiết để xác minh trạng thái và lý do đã đổi. Trả về kết quả quan sát được và đường dẫn ảnh hoặc log.

Ghi một dòng cho mỗi lượt, ít nhất 30 dòng tổng cộng. Mẫu cột:

| Mã ca | Lượt | Thiết bị và build | Điều kiện đầu | Kết quả mong đợi | Kết quả thực tế | Pass/Fail/Blocked | Log hoặc ảnh |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A09 | 1 | Điền sau khi chạy | Buổi demo đã chốt | Lý do trống bị chặn | Điền kết quả đã quan sát | Điền sau khi đối chiếu | `artemis/A09/run-01/` |

Ghi tổng số lượt **Pass**, **Fail** và **Blocked**. Nếu báo cáo tỷ lệ `Pass / (Pass + Fail)`, ghi rõ mẫu số và số lượt Blocked. Giữ log của lượt lỗi và log thử lại. Dành thêm **15–30 phút** cho một phiên khám phá, chẳng hạn đổi mạng giữa lúc điểm danh, quay lại app khi đang có phiên hoặc thử chữ dài. Ghi giờ bắt đầu/kết thúc, thao tác, kết quả và việc thử lại nếu có lỗi.

## 4. Review PR bằng AI và đưa mã lên GitHub

1. Từ thư mục dự án, chạy `git status --short` để xem phạm vi thay đổi. Tạo nhánh, ví dụ `git switch -c codex/lab3-submission`. Chọn từng thư mục hoặc tệp thuộc Lab 3 để stage. Xem danh sách bằng `git diff --cached --name-only` trước khi commit.
2. Commit mã Flutter, backend, Firebase Rules, test và tài liệu cần nộp. Các tệp cấu hình bí mật, dữ liệu sinh viên thật, `.env`, JSON Firebase Admin SDK và token cần ở ngoài commit. Kiểm tra riêng nội dung file minh chứng trước khi đưa vào repo.
3. Push nhánh bằng `git push -u origin codex/lab3-submission`. Trên GitHub, tạo Pull Request từ nhánh này vào `main`, mô tả ba luồng, cách chạy và test hiện có.
4. Trong PR, ở **Reviewers**, yêu cầu **Copilot** review nếu tài khoản có quyền. Có thể dùng CodeRabbit hoặc công cụ tương đương mà lớp chấp nhận. Lưu link PR và các nhận xét gắn với dòng mã. [Cách yêu cầu Copilot review](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/copilot-code-review)
5. Ghi ít nhất **5 phát hiện thuộc ít nhất 2 nhóm**, ví dụ lỗi xử lý, kiểm thử hoặc khả năng bảo trì. Với mỗi mục, ghi vị trí, vấn đề, quyết định **chấp nhận / điều chỉnh / bác bỏ** và lý do kỹ thuật. Sửa ít nhất **3 mục được chấp nhận**, commit trên cùng nhánh và chạy lại kiểm thử liên quan. Gắn hash commit và kết quả retest vào bảng.

| ID | Nhóm | File và dòng | Phát hiện thực tế | Quyết định và lý do | Commit sửa | Retest |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | Điền sau khi review | `file:dòng` | Trích nội dung review có liên kết | Điền sau khi đối chiếu | Hash nếu có sửa | Kết quả đã chạy |

## 5. Hoàn thiện hồ sơ nộp

1. **Repo GitHub.** README có cách chạy Android và backend trên laptop, link thiết kế Lab 2, kiến trúc, kế hoạch Analytics, kết quả test và link PR review. Kiểm tra quyền xem theo yêu cầu của giảng viên. Dùng commit ghi trong log để chỉ rõ bản app dùng trong video.
2. **Báo cáo PDF 8–12 trang.** Trình bày phạm vi, truy vết thiết kế, kiến trúc, sáu dịch vụ Firebase, kết quả ARTEMIS, AI Code Review và phụ lục minh chứng. Ghi rõ kết quả nào đạt, lỗi nào còn tồn tại và phạm vi demo local.
3. **Slide PDF 12–15 trang.** Có thể dùng 14 slide theo thứ tự sau.

   | Slide | Nội dung |
   | --- | --- |
   | 1–2 | Tên dự án, mục tiêu và phần hiện thực từ Lab 2 |
   | 3–4 | Kiến trúc MVVM và đường đi của dữ liệu khi chạy demo |
   | 5–7 | Ba luồng nghiệp vụ, mỗi luồng một slide |
   | 8–10 | Sáu dịch vụ Firebase, hai dịch vụ mỗi slide, dùng ảnh có thể đối chiếu |
   | 11–12 | Bộ ca ARTEMIS, tỷ lệ đạt, log tiêu biểu và kiểm thử khám phá |
   | 13–14 | AI Code Review, commit sửa và link repo/demo |

4. **Video 5–10 phút.** Một kịch bản khoảng 8 phút gồm 30 giây giới thiệu, 1 phút kiến trúc, 3 phút demo ba luồng, 2 phút mở minh chứng Firebase, 1 phút trình bày ARTEMIS và 30 giây cho PR review. Mở sẵn các tab Console. Dùng ảnh Crashlytics đã thu để tránh ngắt mạch video.

### Gửi minh chứng theo từng đợt

| Đợt | Tệp hoặc thông tin gửi lại |
| --- | --- |
| 1 | Ảnh **Authentication → Users**, ảnh đăng nhập và lỗi hủy, ảnh tệp trên Storage, kết quả `Allow`/`Deny` và ảnh DebugView |
| 2 | Ảnh/clip FCM ở ba trạng thái, ảnh Remote Config trước/sau, ảnh Crashlytics non-fatal và crash |
| 3 | Bảng 30 lượt ARTEMIS trở lên, log/ảnh đi kèm và ghi chép phiên khám phá |
| 4 | Link PR, bảng quyết định và commit sửa, hai file PDF và video |

Với mỗi ảnh hoặc video, ghi thao tác, thiết bị và kết quả quan sát được. Che thông tin sinh viên thật, thông tin đăng nhập, token FCM, token tải tệp và khóa API trước khi chia sẻ.
