import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models.dart';
import '../../domain/schedule_service.dart';
import '../../data/roster_importer.dart';
import '../../ui/theme.dart';
import '../viewmodels/teacher_view_model.dart';
import 'components.dart';
import 'attendance_screens.dart';
import 'weekly_timetable_page.dart';
export 'attendance_screens.dart';

void openPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class WorkspaceStartPage extends StatelessWidget {
  const WorkspaceStartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return MobilePage(
      title: 'FAP Attendance',
      actions: [
        IconButton(
          tooltip: 'Tài khoản',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => openPage(context, const AccountPage()),
        ),
      ],
      child: ContentList(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.school, size: 76, color: AppColors.orangeDark),
          Text(
            'FAP Attendance',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('Quản lý lịch lớp và điểm danh dành cho giảng viên.'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tài khoản giảng viên'),
                const SizedBox(height: 8),
                Text(vm.user!.email),
                const SizedBox(height: 8),
                Text(
                  vm.sync?.status ??
                      'Lưu trên thiết bị, sao lưu đám mây tùy chọn.',
                ),
                if (vm.sync != null)
                  OutlinedButton(
                    onPressed: vm.busy ? null : vm.refresh,
                    child: const Text('Tải dữ liệu tài khoản'),
                  ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: vm.busy
                ? null
                : () => openPage(context, const ImportPage()),
            icon: const Icon(Icons.upload_file),
            label: const Text('Nạp danh sách lớp'),
          ),
        ],
      ),
    );
  }
}

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _form = GlobalKey<FormState>();
  final _semester = TextEditingController();
  final _weeks = TextEditingController(text: '10');
  late DateTime _start;
  int _perWeek = 2;
  Uint8List? _bytes;
  String? _filename;
  String? _localError;
  RosterImportResult? _preview;
  bool _picking = false;
  @override
  void initState() {
    super.initState();
    final vm = context.read<TeacherViewModel>();
    _start = vm.workspace?.semesterStart ?? DateTime(2026, 9, 7);
    _semester.text = vm.workspace?.semester ?? '';
  }

  @override
  void dispose() {
    _semester.dispose();
    _weeks.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _localError = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ods', 'xlsx'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final picked = result.files.single;
      if (picked.size > 20 * 1024 * 1024) {
        setState(() => _localError = 'Tệp danh sách lớp phải nhỏ hơn 20 MB.');
        return;
      }
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('Không đọc được tệp.');
      if (!mounted) return;
      final inferred = RosterImporter.semesterFromFileName(picked.name);
      final start = inferred == 'FA26' ? DateTime(2026, 9, 7) : _start;
      final preview = context.read<TeacherViewModel>().previewImport(
        bytes,
        picked.name,
        inferred ?? (_semester.text.isEmpty ? 'FA26' : _semester.text),
        start,
        int.tryParse(_weeks.text) ?? 10,
        _perWeek,
      );
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _filename = picked.name;
          _preview = preview;
          _start = start;
          if (inferred != null) _semester.text = inferred;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _preview = null;
          _localError = e is RosterImportException
              ? e.message
              : 'Không đọc được tệp. Hãy chọn lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirm() async {
    if (!_form.currentState!.validate() || _bytes == null) {
      setState(
        () =>
            _localError = _bytes == null ? 'Hãy chọn tệp danh sách lớp.' : null,
      );
      return;
    }
    final vm = context.read<TeacherViewModel>();
    final bytes = _bytes!;
    final name = _filename!;
    final semester = _semester.text.trim().toUpperCase();
    final weeks = int.parse(_weeks.text);
    final start = _start;
    final perWeek = _perWeek;
    try {
      final preview = vm.previewImport(
        bytes,
        name,
        semester,
        start,
        weeks,
        perWeek,
      );
      final accepted = await confirmAction(
        context,
        'Xác nhận nạp danh sách lớp',
        '${preview.classes.length} lớp · ${preview.classes.fold<int>(0, (n, c) => n + c.students.length)} sinh viên\n\n'
            '${preview.classes.map((c) => '${c.courseCode} · ${c.classCode}').join('\n')}\n\n'
            'Nạp lại cùng học kỳ sẽ giữ lịch sử hiện có.'
            '${preview.warnings.isEmpty ? '' : '\n\nLưu ý:\n${preview.warnings.join('\n')}'}',
        confirm: 'Nạp danh sách lớp',
      );
      if (!accepted || !mounted) return;
      final ok = await vm.importRoster(
        bytes: bytes,
        filename: name,
        semester: semester,
        start: start,
        weeks: weeks,
        perWeek: perWeek,
      );
      if (!mounted) return;
      showResult(context, ok);
      if (ok) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _localError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return MobilePage(
      title: 'Nạp danh sách lớp',
      child: Form(
        key: _form,
        child: ContentList(
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'TỆP NGUỒN',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.description_outlined,
                    size: 40,
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _filename ??
                        'Chọn Markbook của giảng viên (.ods hoặc .xlsx)',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cột nguồn: Class, RollNumber, Email, MemberCode, FullName. Các cột điểm và ghi chú thi được bỏ qua.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: vm.busy || _picking ? null : _pick,
                    child: Text(
                      _picking
                          ? 'Đang chọn…'
                          : _bytes == null
                          ? 'Chọn tệp'
                          : 'Đổi tệp',
                    ),
                  ),
                ],
              ),
            ),
            if (_preview != null)
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_preview!.classes.length} lớp · ${_preview!.classes.fold<int>(0, (n, c) => n + c.students.length)} lượt ghi danh',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nhận mã lịch, môn và lớp từ tên sheet. Ví dụ 11_PRN232_SE1917: Thứ 2 + Thứ 5, slot 1 (07:30–09:15).',
                    ),
                    const SizedBox(height: 8),
                    ..._preview!.classes.map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${c.scheduleCode} · ${c.courseCode} · ${c.classCode}: ${c.students.length} sinh viên',
                        ),
                      ),
                    ),
                    if (_preview!.warnings.isNotEmpty)
                      Text(
                        _preview!.warnings.join('\n'),
                        style: const TextStyle(color: AppColors.danger),
                      ),
                  ],
                ),
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'CẤU HÌNH HỌC KỲ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _semester,
                    decoration: const InputDecoration(
                      labelText: 'Học kỳ',
                      helperText:
                          'Tự nhận từ tên file, ví dụ FA26_Markbook.ods',
                    ),
                    validator: (v) =>
                        RegExp(r'^[A-Za-z0-9_-]{1,32}$')
                            .hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Nhập học kỳ gồm chữ và số.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: vm.busy
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _start,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (date != null && mounted) {
                              setState(() => _start = date);
                            }
                          },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      'Bắt đầu: ${DateFormat('dd/MM/yyyy').format(_start)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _weeks,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Số tuần (1–52)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 52
                          ? 'Nhập từ 1 đến 52 tuần.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _perWeek,
                    decoration: const InputDecoration(
                      labelText: 'Số buổi mỗi tuần',
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 buổi/tuần')),
                      DropdownMenuItem(value: 2, child: Text('2 buổi/tuần')),
                    ],
                    onChanged: vm.busy
                        ? null
                        : (v) => setState(() => _perWeek = v!),
                  ),
                ],
              ),
            ),
            if (_localError != null)
              Text(
                _localError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            FilledButton(
              onPressed: vm.busy || _picking ? null : _confirm,
              child: const Text('Xem trước danh sách lớp'),
            ),
            OutlinedButton(
              onPressed: vm.busy ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final String _initialSemester = context
      .read<TeacherViewModel>()
      .workspace!
      .semester;

  void _openClasses() => openPage(context, const _ClassManagementPage());

  @override
  Widget build(BuildContext context) {
    final semester = context.select(
      (TeacherViewModel vm) => vm.workspace?.semester,
    );
    if (semester == null) return const SizedBox.shrink();
    return WeeklyTimetablePage(
      key: ValueKey(semester),
      startAtSemester: semester != _initialSemester,
      onHome: _openClasses,
      onMeeting: (classId, meetingId) => openPage(
        context,
        AttendancePage(classId: classId, meetingId: meetingId),
      ),
      bottom: TimetableNavigation(
        selected: 0,
        onSelected: (index) {
          switch (index) {
            case 0:
              _openClasses();
            case 1:
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => NotificationsPage(
                    bottom: TimetableNavigation(
                      selected: 1,
                      onSelected: (index) {
                        if (index == 0) Navigator.of(context).pop();
                        if (index == 2) openPage(context, const AccountPage());
                      },
                    ),
                  ),
                ),
              );
            case 2:
              openPage(context, const AccountPage());
          }
        },
      ),
    );
  }
}

class _ClassManagementPage extends StatelessWidget {
  const _ClassManagementPage();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    if (vm.workspace == null) return const SizedBox.shrink();
    final classes = vm.workspace!.classes;
    return MobilePage(
      title: 'Danh sách lớp',
      actions: [
        if (vm.sync != null)
          IconButton(
            tooltip: 'Đồng bộ dữ liệu',
            onPressed: vm.busy ? null : vm.refresh,
            icon: const Icon(Icons.sync),
          ),
        IconButton(
          tooltip: 'Thông báo',
          onPressed: () => openPage(context, const NotificationsPage()),
          icon: const Icon(Icons.notifications_outlined),
        ),
        IconButton(
          tooltip: 'Tài khoản',
          onPressed: () => openPage(context, const AccountPage()),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          await vm.refresh();
        },
        child: ContentList(
          children: [
            if (vm.draftCount > 0) const AttendanceDraftNotice(),
            if (vm.sync != null)
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vm.sync!.status),
                    if (vm.sync!.conflict)
                      OutlinedButton(
                        onPressed: vm.busy
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Nhận bản máy chủ?'),
                                    content: const Text(
                                      'Bản trên máy sẽ được giữ trong tệp đối chiếu trước khi nhận bản mới.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Hủy'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Nhận bản máy chủ'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await vm.receiveServerWorkspace();
                                }
                              },
                        child: const Text('Xử lý xung đột'),
                      ),
                  ],
                ),
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Học kỳ ${vm.workspace!.semester}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${classes.length} lớp · ${classes.fold<int>(0, (n, c) => n + c.students.length)} sinh viên',
                  ),
                  const SizedBox(height: 8),
                  const StatusTag(
                    'Dữ liệu lưu trên thiết bị',
                    color: AppColors.success,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: vm.busy
                  ? null
                  : () => openPage(context, const ImportPage()),
              icon: const Icon(Icons.upload_file),
              label: const Text('Nạp danh sách lớp'),
            ),
            if (classes.isEmpty)
              const SectionCard(child: Text('Nạp danh sách lớp để bắt đầu.')),
            ...classes.map((c) => _ClassCard(course: c)),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.course});
  final CourseClass course;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final started = course.meetings.any(
      (m) => m.state != MeetingState.upcoming,
    );
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(course.id),
        tilePadding: const EdgeInsets.all(16),
        title: Text(
          '${course.courseCode} · ${course.classCode}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${course.students.length} sinh viên · ${course.meetings.where((m) => m.state == MeetingState.closed).length}/${course.meetings.length} buổi đã chốt',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () =>
                    openPage(context, HistoryPage(classId: course.id)),
                child: const Text('Lịch sử'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openPage(context, SchedulePage(classId: course.id)),
                child: Text(started ? 'Xem lịch' : 'Cấu hình lịch'),
              ),
              TextButton(
                onPressed: vm.busy
                    ? null
                    : () async {
                        if (await confirmAction(
                          context,
                          'Xóa lớp?',
                          'Lớp được lưu trữ trên thiết bị. Tệp danh sách lớp gốc được giữ lại.',
                          confirm: 'Xóa lớp',
                        )) {
                          final ok = await vm.deleteClass(course.id);
                          if (context.mounted) showResult(context, ok);
                        }
                      },
                child: const Text('Xóa lớp'),
              ),
            ],
          ),
          ...course.meetings.map(
            (m) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(meetingLabel(m)),
                    const SizedBox(height: 8),
                    StatusTag(
                      stateLabel(m.state),
                      color: m.state == MeetingState.closed
                          ? AppColors.success
                          : AppColors.info,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => openPage(
                        context,
                        AttendancePage(classId: course.id, meetingId: m.id),
                      ),
                      child: Text(
                        m.state == MeetingState.closed
                            ? 'Xem kết quả'
                            : 'Vào buổi học',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.classId});
  final String classId;
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _weeks;
  late int _perWeek;
  late int _weekday;
  late List<DateTime> _excluded;
  late List<DateTime> _makeup;
  @override
  void initState() {
    super.initState();
    final r = context
        .read<TeacherViewModel>()
        .course(widget.classId)
        .scheduleRule;
    _weeks = TextEditingController(text: '${r.weeks}');
    _perWeek = r.meetingsPerWeek;
    _weekday = r.weekdays.isEmpty
        ? ScheduleService.weekdaysByGroup[r.dayGroup]!.first
        : r.weekdays.first;
    _excluded = List.of(r.excludedDates);
    _makeup = List.of(r.additionalStarts);
  }

  @override
  void dispose() {
    _weeks.dispose();
    super.dispose();
  }

  Future<void> _date(bool makeup) async {
    final vm = context.read<TeacherViewModel>();
    final d = await showDatePicker(
      context: context,
      initialDate: vm.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        final target = makeup ? _makeup : _excluded;
        if (!target.any((e) => DateUtils.isSameDay(e, d))) target.add(d);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(widget.classId);
    final locked = c.meetings.any((m) => m.state != MeetingState.upcoming);
    final r = c.scheduleRule;
    return MobilePage(
      title: 'Cấu hình lịch lớp',
      child: Form(
        key: _form,
        child: ContentList(
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.courseCode} · ${c.classCode}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    locked
                        ? 'Không thể đổi lịch vì lớp đã có buổi bắt đầu hoặc đã chốt.'
                        : 'Được phép sửa trước khi lớp bắt đầu điểm danh.',
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _weeks,
              enabled: !locked && !vm.busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tuần (1–52)'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 52 ? 'Nhập 1–52 tuần.' : null;
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: _perWeek,
              decoration: const InputDecoration(labelText: 'Tần suất'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 buổi/tuần')),
                DropdownMenuItem(value: 2, child: Text('2 buổi/tuần')),
              ],
              onChanged: locked || vm.busy
                  ? null
                  : (v) => setState(() => _perWeek = v!),
            ),
            if (_perWeek == 1)
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: 'Ngày học'),
                items: ScheduleService.weekdaysByGroup[r.dayGroup]!
                    .map(
                      (day) => DropdownMenuItem(
                        value: day,
                        child: Text('Thứ ${day + 1}'),
                      ),
                    )
                    .toList(),
                onChanged: locked || vm.busy
                    ? null
                    : (v) => setState(() => _weekday = v!),
              ),
            Text(
              'Khung giờ ${r.dailySlot} · ${ScheduleService.slotTimes[r.dailySlot]!.startHour}:${ScheduleService.slotTimes[r.dailySlot]!.startMinute.toString().padLeft(2, '0')} (cố định)',
            ),
            const Text(
              'NGÀY NGHỈ / HỌC BÙ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._excluded.map(
              (d) => ListTile(
                title: Text('Nghỉ: ${DateFormat('dd/MM/yyyy').format(d)}'),
                trailing: IconButton(
                  tooltip: 'Xóa ngày nghỉ',
                  onPressed: locked
                      ? null
                      : () => setState(() => _excluded.remove(d)),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            ..._makeup.map(
              (d) => ListTile(
                title: Text('Bù: ${DateFormat('dd/MM/yyyy').format(d)}'),
                trailing: IconButton(
                  tooltip: 'Xóa ngày bù',
                  onPressed: locked
                      ? null
                      : () => setState(() => _makeup.remove(d)),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            if (!locked)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _date(false),
                    child: const Text('Thêm ngày nghỉ'),
                  ),
                  OutlinedButton(
                    onPressed: () => _date(true),
                    child: const Text('Thêm ngày bù'),
                  ),
                ],
              ),
            FilledButton(
              onPressed: locked || vm.busy
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      final ok = await vm.updateSchedule(
                        c.id,
                        ScheduleRule(
                          scheduleCode: r.scheduleCode,
                          semesterStart: r.semesterStart,
                          weeks: int.parse(_weeks.text),
                          meetingsPerWeek: _perWeek,
                          weekdays: _perWeek == 1
                              ? [_weekday]
                              : ScheduleService.weekdaysByGroup[r.dayGroup]!,
                          excludedDates: _excluded,
                          additionalStarts: _makeup,
                        ),
                      );
                      if (context.mounted) {
                        showResult(context, ok);
                        if (ok) Navigator.pop(context);
                      }
                    },
              child: const Text('Lưu cấu hình'),
            ),
            OutlinedButton(
              onPressed: vm.busy ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, this.bottom});
  final Widget? bottom;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return MobilePage(
      title: 'Thông báo',
      bottom: bottom,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: vm.busy ? null : vm.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ContentList(
        children: [
          OutlinedButton(
            onPressed: vm.busy ? null : vm.requestNotifications,
            child: const Text('Bật thông báo'),
          ),
          if (vm.permission != null) Text('Quyền thông báo: ${vm.permission}'),
          if (vm.notices.isEmpty)
            const SectionCard(
              child: Text(
                'Chưa có thông báo. Kéo làm mới sau khi nhận thông báo mới.',
              ),
            ),
          ...vm.notices.map(
            (notice) => SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    notice.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(notice.body),
                  Text(DateFormat('dd/MM HH:mm').format(notice.at)),
                  if (notice.classId != null && notice.meetingId != null)
                    TextButton(
                      onPressed: () {
                        try {
                          vm.meeting(notice.classId!, notice.meetingId!);
                          openPage(
                            context,
                            AttendancePage(
                              classId: notice.classId!,
                              meetingId: notice.meetingId!,
                            ),
                          );
                        } on Object {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Không tìm thấy buổi học trên thiết bị này.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Xem buổi học'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return MobilePage(
      title: 'Tài khoản & cài đặt',
      child: ContentList(
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.user!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(vm.user!.email),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => openPage(context, const NotificationsPage()),
            child: const Text('Thông báo'),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cấu hình ứng dụng',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tạo link: ${vm.settings.enableLink ? 'Đang bật' : 'Tạm tắt'}',
                ),
                Text(vm.settings.exportHelp),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: vm.busy
                      ? null
                      : () async {
                          final ok = await vm.refreshConfig();
                          if (context.mounted) showResult(context, ok);
                        },
                  child: const Text('Cập nhật cấu hình'),
                ),
              ],
            ),
          ),
          if (const bool.fromEnvironment('LAB3_DEMO_TOOLS')) ...[
            const Text(
              'Khu vực kiểm thử Lab 3',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            OutlinedButton(
              onPressed: vm.busy ? null : vm.requestNotifications,
              child: const Text('Kiểm tra quyền và token FCM'),
            ),
            if (vm.messagingToken != null) SelectableText(vm.messagingToken!),
            const Text('Không đưa token vào slide công khai.'),
            OutlinedButton(
              onPressed: vm.busy
                  ? null
                  : () async {
                      if (await confirmAction(
                        context,
                        'Gây crash thử nghiệm?',
                        'Ứng dụng sẽ đóng. Chỉ dùng để kiểm tra Crashlytics.',
                        confirm: 'Gây crash',
                      )) {
                        await vm.demoCrash();
                      }
                    },
              child: const Text('Crash thử nghiệm'),
            ),
          ],
          FilledButton(
            onPressed: vm.busy
                ? null
                : () async {
                    if (await confirmAction(
                      context,
                      'Đăng xuất?',
                      'Dữ liệu vẫn được giữ trên thiết bị và chỉ mở lại bằng tài khoản này. Link đang nhận sẽ được dừng.',
                      confirm: 'Đăng xuất',
                    )) {
                      final ok = await vm.signOut();
                      if (context.mounted) showResult(context, ok);
                    }
                  },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}
