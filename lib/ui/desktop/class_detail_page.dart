import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../application/attendance_controller.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'qr_session_page.dart';
import 'schedule_settings_dialog.dart';

class ClassDetailPage extends StatefulWidget {
  const ClassDetailPage({
    super.key,
    required this.controller,
    required this.classId,
  });

  final AttendanceController controller;
  final String classId;

  @override
  State<ClassDetailPage> createState() => _ClassDetailPageState();
}

class _ClassDetailPageState extends State<ClassDetailPage> {
  String? selectedMeetingId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final courseClass = widget.controller.classById(widget.classId);
        selectedMeetingId ??= _defaultMeeting(courseClass).id;
        final selected = courseClass.meetings.singleWhere(
          (m) => m.id == selectedMeetingId,
          orElse: () => courseClass.meetings.first,
        );
        final now = DateTime.now();
        final isToday = selected.isOnDate(now);
        final isPast = selected.isBeforeDate(now);
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 10),
                ),
                const SizedBox(width: 10),
                Text('${courseClass.courseCode} · ${courseClass.classCode}'),
              ],
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () => _configureSchedule(courseClass),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Cấu hình lịch'),
              ),
              const SizedBox(width: 12),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selected.id,
                  items: courseClass.meetings
                      .map(
                        (meeting) => DropdownMenuItem(
                          value: meeting.id,
                          child: Text(
                            'Slot ${meeting.number} · ${DateFormat('dd/MM HH:mm').format(meeting.startAt)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => selectedMeetingId = value),
                ),
              ),
              const SizedBox(width: 12),
              if (selected.state == MeetingState.closed)
                OutlinedButton.icon(
                  onPressed: () => _export(selected),
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV'),
                )
              else if (isPast && selected.state == MeetingState.active)
                FilledButton.icon(
                  onPressed: () => _close(selected),
                  icon: const Icon(Icons.lock_clock_outlined),
                  label: const Text('Chốt slot quá hạn'),
                )
              else if (isPast)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.hourglass_top_rounded),
                  label: const Text('Đang tự động chốt'),
                )
              else if (!isToday)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Chưa đến ngày'),
                )
              else if (selected.state == MeetingState.upcoming)
                FilledButton.icon(
                  onPressed: () => _chooseModeAndStart(courseClass, selected),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Điểm danh'),
                )
              else if (selected.state == MeetingState.active)
                FilledButton.icon(
                  onPressed: () =>
                      _openQr(courseClass, selected, QrMode.normal),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Mở QR'),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(width: 20),
            ],
          ),
          body: Column(
            children: [
              _summary(courseClass, selected),
              const Divider(height: 1),
              Expanded(child: _attendanceTable(courseClass)),
            ],
          ),
        );
      },
    );
  }

  Widget _summary(CourseClass courseClass, Meeting selected) {
    final records = courseClass.attendance[selected.id] ?? const {};
    final present = records.values
        .where((r) => r.status == AttendanceStatus.present)
        .length;
    final absent = records.values
        .where((r) => r.status == AttendanceStatus.absent)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            children: [
              _metric(
                'Sinh viên',
                '${courseClass.students.length}',
                Icons.people_outline,
                AppColors.info,
              ),
              _metric(
                'Có mặt',
                '$present',
                Icons.check_circle_outline,
                AppColors.success,
              ),
              _metric(
                'Vắng',
                '$absent',
                Icons.cancel_outlined,
                AppColors.danger,
              ),
              _metric(
                'Tiến độ',
                '${courseClass.meetings.where((m) => m.state == MeetingState.closed).length}/${courseClass.meetings.length}',
                Icons.timeline,
                AppColors.orange,
              ),
              const Spacer(),
              if (selected.state == MeetingState.active)
                FilledButton.tonalIcon(
                  onPressed: () => _close(selected),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(
                    selected.isBeforeDate(DateTime.now())
                        ? 'Chốt slot quá hạn'
                        : 'Chốt danh sách',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Padding(
        padding: const EdgeInsets.only(right: 28),
        child: Row(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(label),
              ],
            ),
          ],
        ),
      );

  Widget _attendanceTable(CourseClass courseClass) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: DataTable2(
            fixedLeftColumns: 2,
            minWidth: 620 + courseClass.meetings.length * 96,
            columnSpacing: 14,
            horizontalMargin: 16,
            headingRowHeight: 68,
            dataRowHeight: 58,
            dividerThickness: 1,
            headingRowColor: const WidgetStatePropertyAll(AppColors.orangeSoft),
            dataRowColor: const WidgetStatePropertyAll(Colors.white),
            headingTextStyle: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
            columns: [
              const DataColumn2(fixedWidth: 120, label: Text('MSSV')),
              const DataColumn2(fixedWidth: 260, label: Text('Họ tên')),
              const DataColumn2(
                fixedWidth: 58,
                numeric: true,
                label: Text('P', style: TextStyle(color: AppColors.success)),
              ),
              const DataColumn2(
                fixedWidth: 58,
                numeric: true,
                label: Text('A', style: TextStyle(color: AppColors.danger)),
              ),
              const DataColumn2(
                fixedWidth: 90,
                numeric: true,
                label: Text(
                  '% vắng',
                  style: TextStyle(color: AppColors.orangeDark),
                ),
              ),
              ...courseClass.meetings.map((meeting) {
                final current =
                    !now.isBefore(meeting.startAt) &&
                    !now.isAfter(meeting.endAt);
                return DataColumn2(
                  fixedWidth: 96,
                  label: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: current
                        ? BoxDecoration(
                            color: AppColors.orange,
                            borderRadius: BorderRadius.circular(9),
                          )
                        : null,
                    child: Text(
                      'Slot ${meeting.number}\n${DateFormat('dd/MM').format(meeting.startAt)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: current ? Colors.white : AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ],
            rows: courseClass.students.map((student) {
              final statuses = courseClass.meetings
                  .map(
                    (m) =>
                        courseClass
                            .recordFor(m.id, student.rollNumber)
                            ?.status ??
                        AttendanceStatus.unmarked,
                  )
                  .toList();
              final p = statuses
                  .where((s) => s == AttendanceStatus.present)
                  .length;
              final a = statuses
                  .where((s) => s == AttendanceStatus.absent)
                  .length;
              return DataRow(
                cells: [
                  DataCell(
                    SelectableText(
                      student.rollNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(
                    Tooltip(
                      message: student.fullName,
                      child: Text(
                        student.fullName,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text('$p')),
                  DataCell(Text('$a')),
                  DataCell(
                    Text(
                      '${(widget.controller.absenceRate(courseClass.id, student.rollNumber) * 100).toStringAsFixed(1)}%',
                    ),
                  ),
                  ...courseClass.meetings.map((meeting) {
                    final status =
                        courseClass
                            .recordFor(meeting.id, student.rollNumber)
                            ?.status ??
                        AttendanceStatus.unmarked;
                    final editable =
                        meeting.state == MeetingState.closed ||
                        (meeting.state == MeetingState.active &&
                            meeting.isOnDate(now));
                    return DataCell(
                      Center(child: _statusBadge(status)),
                      onTap: editable
                          ? () => _editStatus(
                              courseClass,
                              meeting,
                              student,
                              status,
                            )
                          : null,
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(AttendanceStatus status) {
    final color = switch (status) {
      AttendanceStatus.present => AppColors.success,
      AttendanceStatus.absent => AppColors.danger,
      AttendanceStatus.unmarked => AppColors.muted,
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        attendanceCode(status).isEmpty ? '–' : attendanceCode(status),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Meeting _defaultMeeting(CourseClass courseClass) {
    final now = DateTime.now();
    return courseClass.meetings.firstWhere(
      (m) => m.state == MeetingState.active,
      orElse: () => courseClass.meetings.firstWhere(
        (m) => m.isOnDate(now),
        orElse: () => courseClass.meetings.firstWhere(
          (m) => m.isAfterDate(now) && m.state != MeetingState.closed,
          orElse: () => courseClass.meetings.last,
        ),
      ),
    );
  }

  Future<void> _chooseModeAndStart(
    CourseClass courseClass,
    Meeting meeting,
  ) async {
    final mode = await showDialog<QrMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn chế độ QR'),
        content: const Text('Mã bí mật đổi cùng QR sau mỗi 15 giây.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, QrMode.normal),
            child: const Text('QR thường'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, QrMode.otp),
            child: const Text('QR + mã bí mật'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    await widget.controller.startMeeting(courseClass.id, meeting.id);
    if (mounted) {
      _openQr(
        courseClass,
        widget.controller.meetingById(courseClass.id, meeting.id),
        mode,
      );
    }
  }

  void _openQr(CourseClass courseClass, Meeting meeting, QrMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrSessionPage(
          controller: widget.controller,
          classId: courseClass.id,
          meetingId: meeting.id,
          initialMode: mode,
        ),
      ),
    );
  }

  Future<void> _close(Meeting meeting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chốt danh sách?'),
        content: const Text('Tất cả sinh viên chưa có P sẽ được đánh dấu A.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chốt'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.closeMeeting(widget.classId, meeting.id);
    }
  }

  Future<void> _editStatus(
    CourseClass courseClass,
    Meeting meeting,
    Student student,
    AttendanceStatus old,
  ) async {
    final reason = TextEditingController();
    AttendanceStatus value = old == AttendanceStatus.present
        ? AttendanceStatus.absent
        : AttendanceStatus.present;
    final result = await showDialog<(AttendanceStatus, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${student.rollNumber} · ${student.fullName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<AttendanceStatus>(
                segments: const [
                  ButtonSegment(
                    value: AttendanceStatus.present,
                    label: Text('Present'),
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.absent,
                    label: Text('Absent'),
                  ),
                ],
                selected: {value},
                onSelectionChanged: (values) =>
                    setDialogState(() => value = values.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Lý do chỉnh sửa'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isNotEmpty) {
                  Navigator.pop(context, (value, reason.text.trim()));
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await widget.controller.overrideStatus(
        classId: courseClass.id,
        meetingId: meeting.id,
        rollNumber: student.rollNumber,
        status: result.$1,
        reason: result.$2,
      );
    }
  }

  Future<void> _export(Meeting meeting) async {
    try {
      final file = await widget.controller.exportMeeting(
        widget.classId,
        meeting.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Đã xuất ${file.path}')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _configureSchedule(CourseClass courseClass) async {
    final result = await showScheduleSettingsDialog(context, courseClass);
    if (result == null) return;
    try {
      await widget.controller.updateSchedule(courseClass.id, result);
      selectedMeetingId = null;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
