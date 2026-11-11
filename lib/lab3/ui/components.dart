import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models.dart';
import '../../ui/theme.dart';
import '../viewmodels/teacher_view_model.dart';

String meetingLabel(Meeting m) =>
    'Slot ${m.number} · ${DateFormat('dd/MM/yyyy').format(m.startAt)}\n${DateFormat('HH:mm').format(m.startAt)}–${DateFormat('HH:mm').format(m.endAt)}';
String stateLabel(MeetingState state) => switch (state) {
  MeetingState.upcoming => 'Chưa bắt đầu',
  MeetingState.active => 'Đang điểm danh',
  MeetingState.closed => 'Đã chốt',
};
String statusLabel(AttendanceStatus? s) => switch (s) {
  AttendanceStatus.present => 'P · Có mặt',
  AttendanceStatus.absent => 'A · Vắng',
  _ => 'Chưa ghi nhận',
};

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {super.key, this.color = AppColors.info});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class MobilePage extends StatelessWidget {
  const MobilePage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottom,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(top: false, child: bottom!),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.busy) const LinearProgressIndicator(minHeight: 3),
            if (vm.sync != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  vm.sync!.status,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (vm.error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFECE9),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vm.error!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng thông báo',
                      onPressed: vm.dismissMessage,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class ContentList extends StatelessWidget {
  const ContentList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: children.length,
        separatorBuilder: (_, index) => const SizedBox(height: 16),
        itemBuilder: (_, index) => children[index],
      ),
    ),
  );
}

class Totals extends StatelessWidget {
  const Totals({super.key, required this.classId, required this.meetingId});
  final String classId;
  final String meetingId;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final counts = vm.counts(classId, meetingId);
    final data = <(String, int, Color)>[
      ('Sĩ số', vm.course(classId).students.length, AppColors.ink),
      ('Có mặt', counts[AttendanceStatus.present]!, AppColors.success),
      ('Vắng', counts[AttendanceStatus.absent]!, AppColors.danger),
      ('Chưa ghi', counts[AttendanceStatus.unmarked]!, AppColors.muted),
    ];
    return LayoutBuilder(
      builder: (context, size) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: data
            .map(
              (d) => SizedBox(
                width: (size.maxWidth - 8) / 2,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: d.$3.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(d.$1, style: const TextStyle(fontSize: 14)),
                      Text(
                        '${d.$2}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: d.$3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body, {
  String confirm = 'Đồng ý',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

void showResult(BuildContext context, bool success) {
  if (!context.mounted) return;
  final vm = context.read<TeacherViewModel>();
  final text = success ? vm.message : vm.error;
  if (text != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
