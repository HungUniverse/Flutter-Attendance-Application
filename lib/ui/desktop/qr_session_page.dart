import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/attendance_controller.dart';
import '../../domain/models.dart';
import '../../domain/qr_protocol.dart';
import '../../network/attendance_lan_server.dart';
import '../../network/firebase_identity_verifier.dart';
import '../../network/quick_tunnel.dart';
import '../theme.dart';

class QrSessionPage extends StatefulWidget {
  const QrSessionPage({
    super.key,
    required this.controller,
    required this.classId,
    required this.meetingId,
    required this.initialMode,
  });

  final AttendanceController controller;
  final String classId;
  final String meetingId;
  final QrMode initialMode;

  @override
  State<QrSessionPage> createState() => _QrSessionPageState();
}

class _QrSessionPageState extends State<QrSessionPage> {
  late QrMode mode = widget.initialMode;
  final issuer = RollingQrIssuer();
  final tunnel = QuickTunnel();
  late Timer timer;
  late final AttendanceLanServer server;
  String? serverError;
  String? tunnelError;
  String? publicOrigin;
  bool serverReady = false;
  bool tunnelStarting = false;

  @override
  void initState() {
    super.initState();
    const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
    server = AttendanceLanServer(
      controller: widget.controller,
      issuer: issuer,
      firebaseVerifier: firebaseApiKey.isEmpty
          ? null
          : FirebaseIdentityVerifier(apiKey: firebaseApiKey),
    );
    _startServer();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    timer.cancel();
    unawaited(server.stop());
    unawaited(tunnel.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courseClass = widget.controller.classById(widget.classId);
    final meeting = widget.controller.meetingById(
      widget.classId,
      widget.meetingId,
    );
    final now = DateTime.now();
    final expired = !meeting.isOnDate(now);
    final stableWindow = now.toUtc().millisecondsSinceEpoch ~/ 15000 * 15000;
    final payload = serverReady && !expired
        ? issuer.issue(
            endpoint: server.endpoint,
            classId: widget.classId,
            meetingId: widget.meetingId,
            certificateFingerprint: server.certificateFingerprint,
            mode: mode,
            now: DateTime.fromMillisecondsSinceEpoch(stableWindow, isUtc: true),
          )
        : null;
    String? joinUrl;
    String? joinError;
    if (payload != null && publicOrigin != null) {
      try {
        joinUrl = server.joinUrl(payload, publicOrigin: publicOrigin);
      } on Object catch (error) {
        joinError = error.toString().replaceFirst('Bad state: ', '');
      }
    } else if (payload != null && tunnelError != null) {
      joinError = tunnelError;
    }
    final records = courseClass.attendance[meeting.id] ?? const {};
    final present = records.values
        .where((r) => r.status == AttendanceStatus.present)
        .length;
    final presentStudents = courseClass.students
        .where(
          (student) =>
              records[student.rollNumber]?.status == AttendanceStatus.present,
        )
        .toList();
    final seconds = 15 - (DateTime.now().second % 15);
    return Scaffold(
      backgroundColor: AppColors.creamLight,
      appBar: AppBar(
        title: Text('${courseClass.courseCode} · Slot ${meeting.number}'),
        actions: [
          SegmentedButton<QrMode>(
            segments: const [
              ButtonSegment(value: QrMode.normal, label: Text('QR thường')),
              ButtonSegment(value: QrMode.otp, label: Text('QR + mã bí mật')),
            ],
            selected: {mode},
            onSelectionChanged: expired
                ? null
                : (values) => setState(() => mode = values.first),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Row(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (expired)
                          const SizedBox(
                            width: 330,
                            height: 330,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock_clock_outlined,
                                  size: 72,
                                  color: AppColors.muted,
                                ),
                                SizedBox(height: 18),
                                Text(
                                  'QR đã khóa vì slot không thuộc ngày hôm nay.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else if (joinUrl != null)
                          QrImageView(
                            data: joinUrl,
                            size: 330,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: 1,
                          )
                        else if (serverError != null || joinError != null)
                          SizedBox(
                            width: 330,
                            height: 330,
                            child: Center(
                              child: Text(
                                joinError ?? serverError!,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            width: 330,
                            height: 330,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          expired
                              ? 'Hãy chốt danh sách để hoàn tất slot này.'
                              : 'QR đổi sau $seconds giây',
                        ),
                        if (!expired && serverReady) ...[
                          const SizedBox(height: 10),
                          Text(
                            publicOrigin == null
                                ? 'Đang chuẩn bị QR cho điện thoại…'
                                : 'Sẵn sàng để sinh viên quét QR',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (!expired && mode == QrMode.otp) ...[
                          const SizedBox(height: 18),
                          Text(
                            payload == null ? '------' : issuer.otpFor(payload),
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 12,
                                ),
                          ),
                          const Text(
                            'Mã bí mật giữ nguyên cho đến khi bật lại chế độ này',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 18),
                        Chip(
                          label: Text(
                            '$present/${courseClass.students.length} sinh viên đã có mặt',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sinh viên đã điểm danh',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Chip(
                          avatar: tunnelStarting
                              ? const SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  publicOrigin == null
                                      ? Icons.wifi_tethering_error_rounded
                                      : Icons.wifi_tethering_rounded,
                                  size: 17,
                                  color: publicOrigin == null
                                      ? AppColors.danger
                                      : AppColors.success,
                                ),
                          label: Text(
                            tunnelStarting
                                ? 'Đang chuẩn bị'
                                : publicOrigin == null
                                ? 'Chưa kết nối'
                                : 'Sẵn sàng',
                          ),
                        ),
                      ],
                    ),
                    Text('$present/${courseClass.students.length} có mặt'),
                    if (tunnelError != null || serverError != null) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.orangeSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Chưa tạo được QR cho điện thoại. Kiểm tra Internet rồi thử lại.',
                                ),
                              ),
                              TextButton(
                                onPressed: serverReady && !tunnelStarting
                                    ? _startTunnel
                                    : null,
                                child: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: presentStudents.isEmpty
                          ? const Center(
                              child: Text('Chưa có sinh viên điểm danh.'),
                            )
                          : ListView(
                              children: presentStudents
                                  .map(
                                    (student) => ListTile(
                                      dense: true,
                                      leading: const Icon(
                                        Icons.check_circle,
                                        color: AppColors.success,
                                      ),
                                      title: Text(student.fullName),
                                      subtitle: Text(student.rollNumber),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _close,
                        icon: const Icon(Icons.lock),
                        label: const Text('Chốt danh sách'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startServer() async {
    try {
      await server.start();
      if (mounted) setState(() => serverReady = true);
      unawaited(_startTunnel());
    } on Object {
      if (mounted) {
        setState(() {
          serverError = 'Không thể khởi động dịch vụ điểm danh.';
        });
      }
    }
  }

  Future<void> _startTunnel() async {
    if (!serverReady || tunnelStarting || tunnel.url != null) return;
    setState(() {
      tunnelStarting = true;
      tunnelError = null;
    });
    try {
      final url = await tunnel.start(server.tunnelOrigin);
      if (mounted) {
        setState(() => publicOrigin = url);
      }
    } on Object {
      if (mounted) {
        setState(() => tunnelError = 'Không thể tạo link điểm danh công khai.');
      }
    } finally {
      if (mounted) setState(() => tunnelStarting = false);
    }
  }

  Future<void> _close() async {
    await widget.controller.closeMeeting(widget.classId, widget.meetingId);
    if (mounted) Navigator.pop(context);
  }
}
