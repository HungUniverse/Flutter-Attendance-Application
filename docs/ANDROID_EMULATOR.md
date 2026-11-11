# Chạy máy ảo Android trên laptop Windows

## 1. Cài Android Studio và Emulator

Tải Android Studio từ https://developer.android.com/studio và mở trình cài đặt.
Giữ Android SDK và Android Virtual Device khi được hỏi. Máy đã có SDK tại:

```text
C:\Users\lenovo\AppData\Local\Android\Sdk
```

Trong Android Studio: More Actions > SDK Manager; nếu đã mở project thì Tools >
SDK Manager. Ở SDK Tools, chọn Android Emulator và Android SDK Platform-Tools,
bấm Apply để tải các phần thiếu. Dùng cùng SDK path trên để Flutter nhận thiết bị.

## 2. Tạo điện thoại ảo

1. Ở màn chào Android Studio: More Actions > Virtual Device Manager. Nếu đang mở
   project: View > Tool Windows > Device Manager.
2. Bấm + > Create Virtual Device. Chọn Phone, ví dụ Pixel 6 có biểu tượng Google
   Play trong danh sách, rồi Next.
3. Chọn system image **Google Play**, ví dụ Android 15/API 35 nếu có; tải về rồi
   Next > Finish. Với laptop Intel/AMD chọn x86_64. Đây là lựa chọn cho demo,
   không yêu cầu API của máy ảo trùng compile SDK của app.
4. Đặt tên dễ nhớ, ví dụ `FAP_Pixel`. Bấm nút tam giác Run cạnh máy ảo và chờ
   đến màn hình Android. Mở Play Store để đăng nhập tài khoản dùng thử.

Google Play image có Play Store/Google Play services, phù hợp kiểm tra Google
Sign-In và FCM. Không cần tạo Android project mới chỉ để mở Device Manager.

## 3. Chạy FAP Attendance

Mở Terminal tại thư mục source:

```powershell
cd D:\Fall2026\PRM393\Project_PRM393
flutter devices
```

Khi thấy thiết bị, dùng đúng ID được lệnh trả về:

```powershell
flutter run -d <ID_MAY_AO>
```

Ví dụ chỉ khi ID thực sự là `emulator-5554`:

```powershell
flutter run -d emulator-5554
```

Nếu đã tạo máy nhưng chưa mở, có thể dùng `flutter emulators` để lấy AVD ID rồi
`flutter emulators --launch <AVD_ID>`. AVD ID và ID thiết bị trong `flutter devices`
là hai giá trị khác nhau.

## 4. Nếu máy ảo không khởi động

- Task Manager > Performance > CPU: kiểm tra Virtualization. Nếu Disabled, cần
  bật Intel VT-x/AMD SVM trong BIOS/UEFI theo hướng dẫn máy.
- Trên Windows, mở Turn Windows features on or off, bật Windows Hypervisor
  Platform nếu công cụ báo thiếu, sau đó tự khởi động lại máy khi phù hợp.
- Kiểm tra còn đủ dung lượng cho system image và dữ liệu máy ảo.
- Nếu lỗi đồ họa/đen màn hình, thử Graphics = Software trong cấu hình AVD.

Những thay đổi hệ thống, chấp nhận giấy phép và khởi động lại do bạn thực hiện;
lượt triển khai source không tự bật hoặc tải các thành phần này.

## Nguồn

- https://docs.flutter.dev/platform-integration/android/setup
- https://developer.android.com/studio/run/managing-avds
- https://developer.android.com/studio/run/emulator-acceleration
