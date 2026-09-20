import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/qr_protocol.dart';
import '../../mobile/check_in_client.dart';
import '../../mobile/student_auth_service.dart';
import '../theme.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final scanner = MobileScannerController();
  final email = TextEditingController();
  final password = TextEditingController();
  final otp = TextEditingController();
  final auth = StudentAuthService();
  final client = CheckInClient();

  QrPayload? payload;
  CheckInChallengeResponse? challenge;
  String? deviceId;
  String? message;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final preferences = await SharedPreferences.getInstance();
    var id = preferences.getString('device_id');
    id ??= const Uuid().v4();
    await preferences.setString('device_id', id);
    if (!mounted) return;
    setState(() {
      deviceId = id;
      email.text = preferences.getString('student_email') ?? '';
    });
  }

  @override
  void dispose() {
    scanner.dispose();
    email.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.creamLight,
    appBar: AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 10),
          ),
          SizedBox(width: 9),
          Text('FAP ATTENDANCE'),
        ],
      ),
    ),
    body: SafeArea(child: payload == null ? _scannerView() : _formView()),
  );

  Widget _scannerView() => Column(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: scanner,
                  onDetect: (capture) {
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value != null && !busy) _acceptQr(value);
                  },
                ),
                Center(
                  child: Container(
                    width: 245,
                    height: 245,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.orange, width: 3),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Quét mã QR đang hiển thị trên máy giảng viên. Điện thoại và máy tính phải cùng mạng Wi-Fi.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  Widget _formView() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.verified_user_outlined, size: 64),
      const SizedBox(height: 16),
      Text(
        'Xác nhận danh tính',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Email trong danh sách lớp',
        ),
      ),
      if (auth.configured) ...[
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu Firebase'),
        ),
      ],
      if (challenge?.requiresOtp == true) ...[
        const SizedBox(height: 12),
        TextField(
          controller: otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Mã bí mật 6 số'),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: busy ? null : _submit,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.how_to_reg),
        label: const Text('Submit điểm danh'),
      ),
      if (auth.configured)
        TextButton(
          onPressed: busy ? null : _register,
          child: const Text('Tạo tài khoản và gửi email xác minh'),
        ),
      if (message != null) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(message!),
          ),
        ),
      ],
      TextButton(onPressed: _reset, child: const Text('Quét mã khác')),
    ],
  );

  Future<void> _acceptQr(String value) async {
    setState(() => busy = true);
    await scanner.stop();
    try {
      final uri = Uri.tryParse(value);
      final encoded = uri?.queryParameters['qr'] ?? value;
      final decoded = QrPayload.decode(encoded);
      if (decoded.expiresAt.isBefore(DateTime.now().toUtc())) {
        throw StateError('QR đã hết hạn. Hãy quét mã mới.');
      }
      final created = await client.createChallenge(decoded, encoded, deviceId!);
      if (!mounted) return;
      setState(() {
        payload = decoded;
        challenge = created;
        message = null;
      });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_clean(error))));
        await scanner.start();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      String? token;
      if (auth.configured) {
        final user = await auth.signIn(email.text, password.text);
        if (!user.emailVerified) {
          await auth.sendVerification();
          throw StateError('Email chưa xác minh. Đã gửi lại thư xác minh.');
        }
        token = await auth.idToken();
      }
      final result = await client.checkIn(
        payload: payload!,
        challengeId: challenge!.id,
        deviceId: deviceId!,
        email: email.text,
        otp: challenge!.requiresOtp ? otp.text : null,
        firebaseIdToken: token,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('student_email', email.text.trim());
      if (mounted) setState(() => message = result);
    } on Object catch (error) {
      if (mounted) setState(() => message = _clean(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _register() async {
    setState(() => busy = true);
    try {
      await auth.register(email.text, password.text);
      if (mounted) {
        setState(() {
          message =
              'Đã tạo tài khoản. Hãy mở email xác minh rồi quay lại Submit.';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => message = _clean(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      payload = null;
      challenge = null;
      message = null;
      otp.clear();
    });
    await scanner.start();
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');
}
