import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/attendance_controller.dart';
import '../../domain/models.dart';
import '../../lab3/services/contracts.dart';
import '../theme.dart';

class SharedQrPage extends StatefulWidget {
  const SharedQrPage({
    super.key,
    required this.controller,
    required this.classId,
    required this.meetingId,
    this.mode = QrMode.normal,
  });
  final AttendanceController controller;
  final String classId, meetingId;
  final QrMode mode;
  @override
  State<SharedQrPage> createState() => _SharedQrPageState();
}

class _SharedQrPageState extends State<SharedQrPage> {
  LinkSession? session;
  String? error;
  Timer? timer;
  bool working = false;
  @override
  void initState() {
    super.initState();
    unawaited(_start());
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _start() async {
    if (working) return;
    working = true;
    try {
      session = await widget.controller.sharedLinks!.createQr(
        widget.controller.classById(widget.classId),
        widget.controller.meetingById(widget.classId, widget.meetingId),
        otp: widget.mode == QrMode.otp,
      );
      error = null;
    } on Object catch (e) {
      error = '$e';
    } finally {
      working = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _poll() async {
    if (working || session == null || widget.controller.busy) return;
    working = true;
    try {
      session = (await widget.controller.sharedResults(session!)).session;
      error = null;
    } on Object catch (e) {
      error = '$e';
    } finally {
      working = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _close() async {
    if (working) return;
    working = true;
    setState(() {});
    try {
      await widget.controller.closeMeeting(widget.classId, widget.meetingId);
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      error = '$e';
    } finally {
      working = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép link điểm danh.')),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller.classById(widget.classId),
          m = widget.controller.meetingById(widget.classId, widget.meetingId);
      final present =
          c.attendance[m.id]?.values
              .where((r) => r.status == AttendanceStatus.present)
              .length ??
          0;
      final current = session;
      final closed = m.state == MeetingState.closed;
      final receiving = current?.receiving == true && !closed;
      final status = closed
          ? 'Đã chốt'
          : receiving
          ? 'Đang nhận điểm danh'
          : current != null
          ? 'Đã dừng nhận'
          : working
          ? 'Đang tạo mã QR…'
          : 'Chưa mở mã QR';
      final sync = widget.controller.sync;
      final notice =
          error ??
          (sync?.conflict == true
              ? 'Xung đột đồng bộ. Về danh sách lớp để đối chiếu.'
              : sync != null && sync.status != 'Đã đồng bộ'
              ? sync.status
              : null);
      final text = Theme.of(context).textTheme;
      final qr = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: receiving
              ? QrImageView(
                  data: current!.url,
                  size: 320,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'Mã QR điểm danh',
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Icon(
                    Icons.qr_code_2,
                    size: 76,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
        ),
      );
      final summary = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status,
            style: text.labelLarge?.copyWith(
              color: receiving || closed ? AppColors.success : AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$present / ${c.students.length}',
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text('Sinh viên có mặt', style: text.bodyMedium),
          if (receiving && current?.code != null) ...[
            const SizedBox(height: 16),
            Text('Mã xác nhận', style: text.bodyMedium),
            SelectableText(
              current!.code!,
              style: text.headlineMedium?.copyWith(letterSpacing: 4),
            ),
          ],
          const SizedBox(height: 20),
          if (receiving)
            OutlinedButton.icon(
              onPressed: () => _copyLink(current!.url),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Sao chép link'),
            )
          else if (current == null && !closed && !working)
            OutlinedButton(
              onPressed: _start,
              child: const Text('Thử mở lại QR'),
            ),
          if (!closed) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: working ? null : _close,
              child: const Text('Chốt danh sách'),
            ),
          ],
          if (notice != null) ...[
            const SizedBox(height: 12),
            Text(
              notice,
              style: text.bodySmall?.copyWith(
                color: error != null || sync?.conflict == true
                    ? AppColors.danger
                    : AppColors.muted,
              ),
            ),
          ],
        ],
      );
      return Scaffold(
        appBar: AppBar(
          title: Text('${c.courseCode} · ${c.classCode} · Buổi ${m.number}'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 570) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [qr, const SizedBox(height: 20), summary],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 6, child: qr),
                          const SizedBox(width: 28),
                          Expanded(flex: 5, child: summary),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
