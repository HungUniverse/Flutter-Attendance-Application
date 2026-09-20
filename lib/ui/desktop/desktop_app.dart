import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../application/attendance_controller.dart';
import '../../data/drive_sync_service.dart';
import '../../domain/models.dart';
import '../../domain/schedule_service.dart';
import '../theme.dart';
import 'class_detail_page.dart';
import 'schedule_settings_dialog.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key, required this.controller});
  final AttendanceController controller;

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends State<DesktopHomePage> {
  final _welcomeEmail = TextEditingController();

  @override
  void dispose() {
    _welcomeEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final workspace = widget.controller.workspace;
        return Scaffold(
          backgroundColor: workspace == null
              ? Colors.white
              : AppColors.creamLight,
          appBar: workspace == null
              ? null
              : AppBar(
                  title: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: 11),
                      ),
                      SizedBox(width: 10),
                      Text('FAP ATTENDANCE WORKSPACE'),
                    ],
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Chip(
                        avatar: widget.controller.syncingDrive
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_upload_outlined,
                                size: 18,
                                color: AppColors.info,
                              ),
                        label: Text(
                          widget.controller.syncingDrive
                              ? 'Đang đồng bộ...'
                              : switch (workspace.syncState) {
                                  SyncState.localOnly => 'Chỉ lưu local',
                                  SyncState.pendingSync => 'Chờ đồng bộ Drive',
                                  SyncState.synced => 'Đã đồng bộ',
                                  SyncState.conflict => 'Có xung đột Drive',
                                },
                        ),
                      ),
                    ),
                    if (widget.controller.driveConnected)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton.icon(
                          onPressed:
                              widget.controller.busy ||
                                  widget.controller.syncingDrive
                              ? null
                              : _importFromDrive,
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            color: AppColors.info,
                          ),
                          label: const Text('Cập nhật từ Drive'),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton.icon(
                        onPressed:
                            widget.controller.busy ||
                                widget.controller.syncingDrive
                            ? null
                            : _drive,
                        icon: widget.controller.syncingDrive
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_to_drive,
                                color: AppColors.info,
                              ),
                        label: Text(
                          widget.controller.syncingDrive
                              ? 'Đang đồng bộ...'
                              : widget.controller.driveConnected
                              ? 'Đồng bộ ngay'
                              : 'Kết nối Drive',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: FilledButton.icon(
                        onPressed:
                            widget.controller.busy ||
                                widget.controller.syncingDrive
                            ? null
                            : _import,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Cập nhật markbook'),
                      ),
                    ),
                  ],
                ),
          body: workspace == null ? _emptyState() : _dashboard(workspace),
        );
      },
    );
  }

  Widget _emptyState() => LayoutBuilder(
    builder: (context, constraints) {
      final login = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 42),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 11),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'FAP ATTENDANCE',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 58),
                Text(
                  'Chào mừng trở lại!',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Nhập email giảng viên để bắt đầu workspace học kỳ.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _welcomeEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Email giảng viên',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  onSubmitted: (_) =>
                      _import(suggestedTeacherEmail: _welcomeEmail.text),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.controller.busy
                        ? null
                        : () => _import(
                            suggestedTeacherEmail: _welcomeEmail.text,
                          ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Tiếp tục với markbook'),
                  ),
                ),
                const SizedBox(height: 22),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'HOẶC',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.controller.busy
                        ? null
                        : _signInWithGoogleDrive,
                    icon: const Icon(Icons.add_to_drive, color: AppColors.info),
                    label: const Text('Tiếp tục bằng Google Drive'),
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 17,
                      color: AppColors.muted,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dữ liệu được lưu local-first, không sử dụng database.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (constraints.maxWidth < 900) return login;
      return Row(
        children: [
          Expanded(
            child: ColoredBox(color: Colors.white, child: login),
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.cream,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(56),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        constraints: const BoxConstraints(maxWidth: 620),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 32,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.fact_check_outlined,
                                  color: AppColors.orange,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Không gian điểm danh',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Spacer(),
                                Chip(label: Text('Sẵn sàng')),
                              ],
                            ),
                            Divider(height: 34),
                            Row(
                              children: [
                                _PreviewTile(
                                  icon: Icons.table_view_outlined,
                                  label: 'Import roster',
                                ),
                                SizedBox(width: 12),
                                _PreviewTile(
                                  icon: Icons.qr_code_2,
                                  label: 'Điểm danh QR',
                                ),
                                SizedBox(width: 12),
                                _PreviewTile(
                                  icon: Icons.cloud_done_outlined,
                                  label: 'Lưu an toàn',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 44),
                      Text(
                        'Điểm danh gọn hơn mỗi ngày',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tạo lịch, theo dõi chuyên cần và xuất dữ liệu FAP\ntrong một workspace duy nhất.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _dashboard(TeacherWorkspace workspace) {
    final today = DateTime.now();
    final todayClasses = <(CourseClass, Meeting)>[];
    for (final courseClass in workspace.classes) {
      for (final meeting in courseClass.meetings) {
        if (_sameDay(meeting.startAt, today)) {
          todayClasses.add((courseClass, meeting));
        }
      }
    }
    todayClasses.sort((a, b) => a.$2.startAt.compareTo(b.$2.startAt));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.white, AppColors.cream],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chào ngày dạy mới!',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Học kỳ ${workspace.semester} · ${_longWeekday(today.weekday)}, ${DateFormat('dd/MM/yyyy').format(today)}',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    if (widget.controller.workspacePath != null)
                      Tooltip(
                        message: widget.controller.workspacePath!,
                        child: const Chip(
                          avatar: Icon(Icons.check_circle_outline, size: 18),
                          label: Text('Đã lưu local'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _dashboardMetric(
                    icon: Icons.school_outlined,
                    value: '${workspace.classes.length}',
                    label: 'Lớp đang dạy',
                    color: AppColors.orange,
                  ),
                  const SizedBox(width: 14),
                  _dashboardMetric(
                    icon: Icons.today_outlined,
                    value: '${todayClasses.length}',
                    label: 'Lớp hôm nay',
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 14),
                  _dashboardMetric(
                    icon: Icons.people_outline,
                    value:
                        '${workspace.classes.fold<int>(0, (sum, item) => sum + item.students.length)}',
                    label: 'Sinh viên',
                    color: AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _sectionHeading(
                'Lịch dạy hôm nay',
                todayClasses.isEmpty
                    ? 'Không có slot học'
                    : '${todayClasses.length} slot theo lịch',
              ),
              const SizedBox(height: 12),
              if (todayClasses.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 12),
                      Text('Hôm nay không có lớp trong lịch đã cấu hình.'),
                    ],
                  ),
                )
              else
                ...todayClasses.map((item) {
                  final (courseClass, meeting) = item;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _todayClassRow(courseClass, meeting, today),
                  );
                }),
              const SizedBox(height: 24),
              _sectionHeading(
                'Tất cả lớp',
                'Chọn một lớp để xem danh sách điểm danh',
              ),
              const SizedBox(height: 12),
              ...workspace.classes.map(
                (courseClass) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _classRow(courseClass),
                ),
              ),
              if (widget.controller.lastMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.orangeSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(widget.controller.lastMessage!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sectionHeading(String title, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );

  Widget _todayClassRow(
    CourseClass courseClass,
    Meeting meeting,
    DateTime now,
  ) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      onTap: () => _openClass(courseClass.id),
      leading: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.orangeSoft,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          'S${courseClass.scheduleRule.dailySlot}',
          style: const TextStyle(
            color: AppColors.orangeDark,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(
        '${courseClass.courseCode} · ${courseClass.classCode}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${DateFormat('HH:mm').format(meeting.startAt)}–${DateFormat('HH:mm').format(meeting.endAt)} · Slot ${meeting.number}',
      ),
      trailing: _meetingStatus(meeting, now),
    ),
  );

  Widget _classRow(CourseClass courseClass) {
    final closed = courseClass.meetings
        .where((meeting) => meeting.state == MeetingState.closed)
        .length;
    final total = courseClass.meetings.length;
    final progress = total == 0 ? 0.0 : closed / total;
    final days = courseClass.scheduleRule.weekdays.isEmpty
        ? ScheduleService.weekdaysByGroup[courseClass.scheduleRule.dayGroup]!
              .take(courseClass.scheduleRule.meetingsPerWeek)
              .toList()
        : courseClass.scheduleRule.weekdays;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openClass(courseClass.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.orange, width: 5)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final information = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orangeSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          courseClass.courseCode,
                          style: const TextStyle(
                            color: AppColors.orangeDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          courseClass.classCode,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 7,
                    children: [
                      _classFact(
                        Icons.people_outline,
                        '${courseClass.students.length} sinh viên',
                      ),
                      _classFact(
                        Icons.calendar_month_outlined,
                        '${courseClass.scheduleRule.weeks} tuần',
                      ),
                      _classFact(
                        Icons.repeat_rounded,
                        '${courseClass.scheduleRule.meetingsPerWeek} slot/tuần',
                      ),
                      _classFact(
                        Icons.schedule_outlined,
                        'Lịch ${courseClass.scheduleCode}${days.isEmpty ? '' : ' · ${days.map(_shortWeekday).join(' & ')}'}',
                      ),
                    ],
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 150,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$closed/$total slot đã chốt',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(99),
                          backgroundColor: AppColors.panel,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  OutlinedButton.icon(
                    onPressed: () => _configureCourse(courseClass),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Chỉnh lịch'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _deleteCourse(courseClass),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Xóa'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _openClass(courseClass.id),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Mở lớp'),
                  ),
                ],
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [information, const SizedBox(height: 18), actions],
                );
              }
              return Row(
                children: [
                  Expanded(child: information),
                  const SizedBox(width: 24),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _classFact(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: AppColors.muted),
      const SizedBox(width: 6),
      Text(label),
    ],
  );

  String _shortWeekday(int day) => switch (day) {
    DateTime.monday => 'T2',
    DateTime.tuesday => 'T3',
    DateTime.wednesday => 'T4',
    DateTime.thursday => 'T5',
    DateTime.friday => 'T6',
    DateTime.saturday => 'T7',
    _ => '?',
  };

  String _longWeekday(int day) => switch (day) {
    DateTime.monday => 'Thứ Hai',
    DateTime.tuesday => 'Thứ Ba',
    DateTime.wednesday => 'Thứ Tư',
    DateTime.thursday => 'Thứ Năm',
    DateTime.friday => 'Thứ Sáu',
    DateTime.saturday => 'Thứ Bảy',
    DateTime.sunday => 'Chủ Nhật',
    _ => '',
  };

  Future<void> _configureCourse(CourseClass courseClass) async {
    final result = await showScheduleSettingsDialog(context, courseClass);
    if (result == null) return;
    try {
      await widget.controller.updateSchedule(courseClass.id, result);
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  Future<void> _deleteCourse(CourseClass courseClass) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lớp khỏi workspace?'),
        content: Text(
          'Lớp ${courseClass.courseCode} · ${courseClass.classCode} sẽ bị xóa khỏi danh sách hiện tại. '
          'File markbook gốc không bị xóa và dữ liệu local của lớp được chuyển vào thư mục lưu trữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Xóa lớp'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteClass(courseClass.id);
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  Widget _meetingStatus(Meeting meeting, DateTime now) {
    final text = now.isBefore(meeting.startAt)
        ? 'Sắp tới'
        : now.isAfter(meeting.endAt)
        ? 'Đã qua'
        : 'Đang học';
    final color = now.isBefore(meeting.startAt)
        ? AppColors.orange
        : now.isAfter(meeting.endAt)
        ? AppColors.muted
        : AppColors.success;
    return Chip(
      avatar: Icon(Icons.circle, size: 9, color: color),
      label: Text(text),
    );
  }

  Future<void> _import({String? suggestedTeacherEmail}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ods', 'xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null || !mounted) return;
    final settings = await showDialog<_ImportSettings>(
      context: context,
      builder: (context) =>
          _ImportDialog(initialTeacherEmail: suggestedTeacherEmail ?? ''),
    );
    if (settings == null) return;
    try {
      final warnings = await widget.controller.importRoster(
        bytes: Uint8List.fromList(picked.files.single.bytes!),
        fileName: picked.files.single.name,
        semester: settings.semester,
        semesterStart: settings.start,
        teacherEmail: settings.teacherEmail,
        weeks: settings.weeks,
        meetingsPerWeek: settings.meetingsPerWeek,
      );
      if (warnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import hoàn tất với cảnh báo'),
            content: SelectableText(warnings.join('\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  Future<void> _drive() async {
    try {
      if (widget.controller.driveConnected) {
        await widget.controller.syncNow();
      } else {
        await widget.controller.connectDrive(
          clientId: const String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'),
          clientSecret: const String.fromEnvironment(
            'GOOGLE_OAUTH_CLIENT_SECRET',
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  Future<void> _signInWithGoogleDrive() async {
    await _drive();
    if (!mounted || !widget.controller.driveConnected) return;
    await _importFromDrive(suggestedTeacherEmail: _welcomeEmail.text);
  }

  Future<void> _importFromDrive({String? suggestedTeacherEmail}) async {
    try {
      final sources = await widget.controller.driveSourceFiles();
      if (!mounted) return;
      if (sources.isEmpty) {
        _showError('Drive chưa có markbook nào do ứng dụng tải lên.');
        return;
      }
      final selected = await showDialog<DriveSourceFile>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Chọn markbook từ Drive'),
          children: sources
              .map(
                (source) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, source),
                  child: ListTile(
                    leading: const Icon(Icons.table_view_outlined),
                    title: Text(source.name),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null || !mounted) return;
      final settings = await showDialog<_ImportSettings>(
        context: context,
        builder: (context) =>
            _ImportDialog(initialTeacherEmail: suggestedTeacherEmail ?? ''),
      );
      if (settings == null) return;
      final bytes = await widget.controller.downloadDriveSource(selected.id);
      final warnings = await widget.controller.importRoster(
        bytes: bytes,
        fileName: selected.name,
        semester: settings.semester,
        semesterStart: settings.start,
        teacherEmail: settings.teacherEmail,
        weeks: settings.weeks,
        meetingsPerWeek: settings.meetingsPerWeek,
      );
      if (warnings.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import hoàn tất với cảnh báo'),
            content: SelectableText(warnings.join('\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  void _openClass(String classId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ClassDetailPage(controller: widget.controller, classId: classId),
      ),
    );
  }

  void _showError(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ImportSettings {
  const _ImportSettings(
    this.semester,
    this.teacherEmail,
    this.start,
    this.weeks,
    this.meetingsPerWeek,
  );
  final String semester;
  final String teacherEmail;
  final DateTime start;
  final int weeks;
  final int meetingsPerWeek;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({this.initialTeacherEmail = ''});

  final String initialTeacherEmail;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final semester = TextEditingController(text: 'FA26');
  late final TextEditingController teacherEmail;
  DateTime start = DateTime(2026, 9, 7);
  int weeks = 10;
  int meetings = 2;

  @override
  void initState() {
    super.initState();
    teacherEmail = TextEditingController(text: widget.initialTeacherEmail);
  }

  @override
  void dispose() {
    semester.dispose();
    teacherEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thiết lập học kỳ'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.info, size: 20),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Nếu học kỳ đã tồn tại, app sẽ cập nhật danh sách và giữ nguyên lịch sử điểm danh.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: semester,
            decoration: const InputDecoration(labelText: 'Mã học kỳ'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: teacherEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email giảng viên'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ngày bắt đầu'),
            subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final value = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                initialDate: start,
              );
              if (value != null) setState(() => start = value);
            },
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: weeks,
                  decoration: const InputDecoration(labelText: 'Số tuần'),
                  items: [5, 6, 8, 10, 12, 15]
                      .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                      .toList(),
                  onChanged: (v) => setState(() => weeks = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: meetings,
                  decoration: const InputDecoration(labelText: 'Slot/tuần'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                  ],
                  onChanged: (v) => setState(() => meetings = v!),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ImportSettings(
            semester.text.trim(),
            teacherEmail.text.trim(),
            start,
            weeks,
            meetings,
          ),
        ),
        child: const Text('Tiếp tục'),
      ),
    ],
  );
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 126,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange),
          const Spacer(),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}
