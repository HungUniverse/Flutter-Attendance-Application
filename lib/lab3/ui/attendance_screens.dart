import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models.dart';
import '../../ui/theme.dart';
import '../viewmodels/teacher_view_model.dart';
import 'components.dart';
import 'screens.dart' show openPage;

class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.classId,
    required this.meetingId,
  });
  final String classId;
  final String meetingId;
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(widget.classId);
    final m = vm.meeting(c.id, widget.meetingId);
    final students = c.students
        .where(
          (s) => '${s.rollNumber} ${s.fullName}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    final editable = m.state == MeetingState.active && m.isOnDate(vm.now());
    return MobilePage(
      title: m.state == MeetingState.closed
          ? 'Kết quả điểm danh'
          : 'Điểm danh lớp',
      actions: [
        IconButton(
          tooltip: 'Lịch sử lớp',
          onPressed: () => openPage(context, HistoryPage(classId: c.id)),
          icon: const Icon(Icons.history),
        ),
        IconButton(
          tooltip: 'Làm mới',
          onPressed: vm.busy ? null : vm.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ContentList(
        children: [
          if (m.state == MeetingState.active || vm.draftCount > 0)
            const AttendanceDraftNotice(),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${c.courseCode} · ${c.classCode}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(meetingLabel(m)),
                const SizedBox(height: 12),
                StatusTag(
                  stateLabel(m.state),
                  color: m.state == MeetingState.closed
                      ? AppColors.success
                      : AppColors.info,
                ),
                const SizedBox(height: 16),
                Totals(classId: c.id, meetingId: m.id),
              ],
            ),
          ),
          if (m.state == MeetingState.upcoming) ...[
            Text(
              m.isOnDate(vm.now())
                  ? 'Bắt đầu buổi học để ghi nhận kết quả.'
                  : 'Chưa đến ngày học. Chưa thể điểm danh buổi này.',
            ),
            FilledButton(
              onPressed: vm.busy || !m.isOnDate(vm.now())
                  ? null
                  : () async {
                      final ok = await vm.begin(c.id, m.id);
                      if (context.mounted) showResult(context, ok);
                    },
              child: const Text('Bắt đầu điểm danh'),
            ),
          ],
          if (editable) ...[
            if (vm.ai != null)
              OutlinedButton.icon(
                onPressed: vm.busy
                    ? null
                    : () => reviewWithAi(context, c.id, m.id),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('AI · Gợi ý kiểm tra trước khi chốt'),
              ),
            SegmentedButton<AttendanceMode>(
              segments: const [
                ButtonSegment(
                  value: AttendanceMode.link,
                  label: Text('Qua link'),
                  icon: Icon(Icons.link),
                ),
                ButtonSegment(
                  value: AttendanceMode.manual,
                  label: Text('Thủ công'),
                  icon: Icon(Icons.checklist),
                ),
              ],
              selected: {vm.mode},
              onSelectionChanged: vm.busy
                  ? null
                  : (s) => vm.selectMode(s.first),
            ),
            if (vm.mode == AttendanceMode.link)
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Sinh viên mở link và hoàn tất xác nhận để ghi nhận Có mặt.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vm.link == null
                          ? 'Chưa có link'
                          : vm.linkError != null
                          ? 'Chưa xác minh được tình trạng link'
                          : vm.link!.receiving
                          ? 'Đang nhận qua link'
                          : 'Link tạm ngừng',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: vm.busy
                          ? null
                          : () => openPage(
                              context,
                              LinkPage(classId: c.id, meetingId: m.id),
                            ),
                      icon: const Icon(Icons.link),
                      label: Text(
                        vm.link == null ? 'Tạo link điểm danh' : 'Quản lý link',
                      ),
                    ),
                    if (!vm.settings.enableLink)
                      const Text(
                        'Tạo link mới đang tạm tắt. Link hiện có giữ nguyên trạng thái.',
                      ),
                    if (vm.linkError != null)
                      Text(
                        vm.linkError!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                  ],
                ),
              ),
            if (vm.mode == AttendanceMode.manual)
              const Text(
                'Chọn Present hoặc Absent. Kết quả lưu trên thiết bị; sửa kết quả đã ghi cần lý do.',
              ),
          ],
          TextField(
            decoration: InputDecoration(
              labelText: 'Tìm họ tên hoặc MSSV',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
          ),
          Text(
            'DANH SÁCH SINH VIÊN (${students.length}/${c.students.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (students.isEmpty)
            const SectionCard(child: Text('Không có sinh viên khớp tìm kiếm.')),
          ...students.map((s) {
            final record = c.recordFor(m.id, s.rollNumber);
            return SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () {
                      vm.studentViewed();
                      openPage(
                        context,
                        StudentPage(classId: c.id, roll: s.rollNumber),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.fullName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${s.rollNumber} · Chi tiết',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (record?.note != null)
                    const Text(
                      'Có ghi chú chỉnh sửa',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.orangeDark,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (editable && vm.mode == AttendanceMode.manual)
                    SegmentedButton<AttendanceStatus>(
                      showSelectedIcon: false,
                      emptySelectionAllowed: true,
                      segments: const [
                        ButtonSegment(
                          value: AttendanceStatus.present,
                          label: Text('P · Có mặt'),
                        ),
                        ButtonSegment(
                          value: AttendanceStatus.absent,
                          label: Text('A · Vắng'),
                        ),
                      ],
                      selected:
                          record == null ||
                              record.status == AttendanceStatus.unmarked
                          ? {}
                          : {record.status},
                      onSelectionChanged: vm.busy
                          ? null
                          : (values) async {
                              if (values.isEmpty ||
                                  values.first == record?.status) {
                                return;
                              }
                              final ok = await vm.mark(
                                c.id,
                                m.id,
                                s.rollNumber,
                                values.first,
                              );
                              if (!ok && context.mounted) {
                                showResult(context, false);
                              }
                            },
                    )
                  else
                    StatusTag(
                      statusLabel(record?.status),
                      color: record?.status == AttendanceStatus.present
                          ? AppColors.success
                          : record?.status == AttendanceStatus.absent
                          ? AppColors.danger
                          : AppColors.muted,
                    ),
                ],
              ),
            );
          }),
          if (editable)
            FilledButton.icon(
              onPressed: vm.busy
                  ? null
                  : () => closeAttendance(context, c.id, m.id),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Chốt danh sách'),
            ),
          if (m.state == MeetingState.closed)
            FilledButton.icon(
              onPressed: () =>
                  openPage(context, ExportPage(classId: c.id, meetingId: m.id)),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Xuất kết quả'),
            ),
        ],
      ),
    );
  }
}

class AttendanceDraftNotice extends StatelessWidget {
  const AttendanceDraftNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${vm.draftCount} lựa chọn trong bản nháp trên máy',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn và đổi P/A thoải mái. Bấm Chốt danh sách để gửi một lần. Bản nháp không bị ghi đè khi tự đồng bộ.',
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Bản nháp điểm danh trên máy'),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Buổi đã chốt hoặc lớp đã đổi trên máy chủ sẽ không bị bản nháp ghi đè. Nếu cần áp dụng lại, sửa kết quả trong Lịch sử kèm lý do.',
                        ),
                        ...vm.manualDrafts.map(
                          (draft) => Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${draft.classId}\n${DateTime(draft.startAt.year, draft.startAt.month, draft.startAt.day).toIso8601String().split('T').first}\n${draft.records.entries.map((entry) => '${entry.key}: ${attendanceCode(entry.value.status)}').join('\n')}',
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final accepted = await confirmAction(
                                      context,
                                      'Bỏ bản nháp này?',
                                      'Các lựa chọn trong bản nháp của buổi này sẽ bị bỏ. Kết quả trên Firebase không thay đổi.',
                                      confirm: 'Bỏ bản nháp',
                                    );
                                    if (!accepted || !context.mounted) return;
                                    final ok = await vm.discardDraft(draft.key);
                                    if (ok && context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                                  child: const Text('Bỏ bản nháp này'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            ),
            child: const Text('Xem bản nháp'),
          ),
        ],
      ),
    );
  }
}

Future<void> closeAttendance(
  BuildContext context,
  String classId,
  String meetingId,
) async {
  final vm = context.read<TeacherViewModel>();
  final totals = vm.counts(classId, meetingId);
  final confirm = await confirmAction(
    context,
    'Xác nhận chốt danh sách',
    '${vm.course(classId).courseCode} · ${vm.course(classId).classCode}\n${meetingLabel(vm.meeting(classId, meetingId))}\n\n'
        '${totals[AttendanceStatus.present]} Có mặt · ${totals[AttendanceStatus.absent]} Vắng.\n'
        '${totals[AttendanceStatus.unmarked]} sinh viên chưa ghi nhận sẽ chuyển thành Vắng (A).\n\n'
        'Link ngừng nhận. Bạn vẫn có thể sửa có lý do sau khi chốt.',
    confirm: 'Đồng ý chốt',
  );
  if (!confirm || !context.mounted) return;
  final ok = await vm.close(classId, meetingId);
  if (context.mounted) showResult(context, ok);
}

Future<void> reviewWithAi(
  BuildContext context,
  String classId,
  String meetingId,
) async {
  final vm = context.read<TeacherViewModel>();
  final ok = await vm.requestAiReview(classId, meetingId);
  if (!context.mounted) return;
  if (!ok || vm.aiReview == null) {
    showResult(context, false);
    return;
  }
  final edited = await showDialog<String>(
    context: context,
    builder: (_) => _AiReviewDialog(vm.aiReview!.text),
  );
  if (edited != null && context.mounted) {
    final accepted = await vm.acceptAiReview(edited);
    if (context.mounted) showResult(context, accepted);
  }
}

class _AiReviewDialog extends StatefulWidget {
  const _AiReviewDialog(this.text);
  final String text;
  @override
  State<_AiReviewDialog> createState() => _AiReviewDialogState();
}

class _AiReviewDialogState extends State<_AiReviewDialog> {
  late final TextEditingController editor;
  @override
  void initState() {
    super.initState();
    editor = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Gợi ý do AI tạo'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Kiểm tra, chỉnh sửa và xác nhận nội dung trước khi tiếp tục chốt.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: editor,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(labelText: 'Nội dung kiểm tra'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
      FilledButton(
        onPressed: () {
          if (editor.text.trim().isNotEmpty) {
            Navigator.pop(context, editor.text.trim());
          }
        },
        child: const Text('Xác nhận gợi ý'),
      ),
    ],
  );
}

class LinkPage extends StatelessWidget {
  const LinkPage({super.key, required this.classId, required this.meetingId});
  final String classId;
  final String meetingId;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(classId);
    final m = vm.meeting(classId, meetingId);
    final session = vm.link;
    final same = session?.classId == classId && session?.meetingId == meetingId;
    final receiving =
        same &&
        vm.linkError == null &&
        session!.receiving &&
        session.expiresAt.isAfter(vm.linkNow);
    return MobilePage(
      title: 'Link điểm danh',
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
                Text(meetingLabel(m)),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusTag(
                  m.state == MeetingState.closed
                      ? 'Đã kết thúc'
                      : receiving
                      ? 'Đang nhận qua link'
                      : same && vm.linkError != null
                      ? 'Không thể xác minh link'
                      : 'Link tạm ngừng',
                  color: receiving ? AppColors.success : AppColors.muted,
                ),
                const SizedBox(height: 16),
                if (same) SelectableText(session!.url),
                if (same && session!.code != null)
                  Text(
                    'Mã xác nhận: ${session.code}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (vm.linkError != null)
                  Text(
                    vm.linkError!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                const SizedBox(height: 16),
                if (!receiving && m.state == MeetingState.active)
                  FilledButton(
                    onPressed:
                        vm.busy || (!vm.settings.enableLink && vm.link == null)
                        ? null
                        : () async {
                            final ok = await vm.createLink(classId, meetingId);
                            if (context.mounted) showResult(context, ok);
                          },
                    child: Text(
                      same ? 'Thử lại / Tạo lại link' : 'Tạo link điểm danh',
                    ),
                  ),
                if (receiving)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: vm.busy
                            ? null
                            : () async {
                                final ok = await vm.shareLink(copy: true);
                                if (context.mounted) showResult(context, ok);
                              },
                        icon: const Icon(Icons.copy),
                        label: const Text('Sao chép'),
                      ),
                      FilledButton.icon(
                        onPressed: vm.busy ? null : () => vm.shareLink(),
                        icon: const Icon(Icons.share),
                        label: const Text('Chia sẻ'),
                      ),
                    ],
                  ),
                if (same)
                  OutlinedButton(
                    onPressed: vm.busy ? null : vm.refresh,
                    child: const Text('Kiểm tra trạng thái / Làm mới'),
                  ),
              ],
            ),
          ),
          Totals(classId: classId, meetingId: meetingId),
          const Text(
            'Sinh viên cần hoàn tất trang xác nhận trong 2 phút kể từ khi mở lượt điểm danh. Mở link đơn thuần chưa được tính Có mặt.',
          ),
          const Text(
            'Chuyển ứng dụng hoặc quay lại lớp không tự chốt buổi học. Khi mất kết nối, app chưa thể xác minh link; kết quả trên máy được giữ lại.',
          ),
          if (same && m.state != MeetingState.closed)
            OutlinedButton(
              onPressed: vm.busy
                  ? null
                  : () async {
                      if (await confirmAction(
                        context,
                        'Dừng nhận qua link?',
                        'Giữ kết quả hiện tại và tiếp tục điểm danh thủ công. Ô chưa ghi không tự chuyển thành Vắng.',
                        confirm: 'Dừng nhận',
                      )) {
                        final ok = await vm.stopLink();
                        if (context.mounted) showResult(context, ok);
                      }
                    },
              child: const Text('Dừng nhận qua link'),
            ),
          if (m.state == MeetingState.active)
            FilledButton(
              onPressed: vm.busy
                  ? null
                  : () => closeAttendance(context, classId, meetingId),
              child: const Text('Chốt danh sách'),
            ),
          OutlinedButton(
            onPressed: () {
              vm.selectMode(AttendanceMode.manual);
              Navigator.pop(context);
            },
            child: const Text('Quay lại lớp · Thủ công'),
          ),
        ],
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.classId});
  final String classId;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _closedOnly = false;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(widget.classId);
    final meetings =
        c.meetings
            .where((m) => !_closedOnly || m.state == MeetingState.closed)
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return MobilePage(
      title: 'Lịch sử điểm danh lớp',
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
                Text(
                  '${c.students.length} sinh viên · ${c.meetings.where((m) => m.state == MeetingState.closed).length}/${c.meetings.length} buổi đã chốt',
                ),
              ],
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Tất cả')),
              ButtonSegment(value: true, label: Text('Đã chốt')),
            ],
            selected: {_closedOnly},
            onSelectionChanged: (v) => setState(() => _closedOnly = v.first),
          ),
          if (meetings.isEmpty)
            const SectionCard(
              child: Text('Chưa có buổi học thuộc bộ lọc này.'),
            ),
          ...meetings.map((m) {
            final counts = vm.counts(c.id, m.id);
            return SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    meetingLabel(m),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  StatusTag(stateLabel(m.state)),
                  const SizedBox(height: 8),
                  Text(
                    '${counts[AttendanceStatus.present]} Có mặt · ${counts[AttendanceStatus.absent]} Vắng · ${counts[AttendanceStatus.unmarked]} Chưa ghi',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => openPage(
                      context,
                      AttendancePage(classId: c.id, meetingId: m.id),
                    ),
                    child: const Text('Xem chi tiết'),
                  ),
                  if (m.state == MeetingState.closed)
                    FilledButton(
                      onPressed: () => openPage(
                        context,
                        ExportPage(classId: c.id, meetingId: m.id),
                      ),
                      child: const Text('Xuất kết quả'),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class StudentPage extends StatelessWidget {
  const StudentPage({super.key, required this.classId, required this.roll});
  final String classId;
  final String roll;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(classId);
    final s = c.students.singleWhere((s) => s.rollNumber == roll);
    final records = c.meetings.map((m) => c.recordFor(m.id, roll));
    final meetings = c.meetings.toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return MobilePage(
      title: 'Chi tiết sinh viên',
      child: ContentList(
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fullName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('${s.rollNumber}\n${s.email}'),
                const SizedBox(height: 16),
                Text(
                  'Có mặt: ${records.where((r) => r?.status == AttendanceStatus.present).length} · Vắng: ${records.where((r) => r?.status == AttendanceStatus.absent).length}',
                ),
                Text(
                  'Tỷ lệ vắng: ${(vm.attendance.absenceRate(c, roll) * 100).toStringAsFixed(1)}%',
                ),
                Text(
                  'Tính trên toàn bộ ${c.meetings.length} buổi đã lên lịch.',
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Text(
            'LỊCH SỬ ĐIỂM DANH CÁ NHÂN',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ...meetings.map((m) {
            final r = c.recordFor(m.id, roll);
            final audit = c.auditEvents
                .where((e) => e.meetingId == m.id && e.rollNumber == roll)
                .toList();
            return SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    meetingLabel(m),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  StatusTag(
                    statusLabel(r?.status),
                    color: r?.status == AttendanceStatus.absent
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                  const SizedBox(height: 8),
                  Text(stateLabel(m.state)),
                  if (r?.note != null) Text(r!.note!),
                  if (audit.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Ghi chú & lịch sử chỉnh sửa'),
                          content: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: audit.reversed
                                  .map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: Text(
                                        '${e.createdAt.toLocal()}\n${e.oldValue ?? 'Chưa ghi'} → ${e.newValue}\n${e.reason}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Đóng'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Xem ghi chú'),
                    ),
                  if (m.state != MeetingState.upcoming)
                    FilledButton(
                      onPressed: vm.busy
                          ? null
                          : () => editAttendance(context, c.id, m.id, roll),
                      child: const Text('Sửa P/A'),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

Future<void> editAttendance(
  BuildContext context,
  String classId,
  String meetingId,
  String roll, {
  AttendanceStatus? initial,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EditSheet(
      classId: classId,
      meetingId: meetingId,
      roll: roll,
      initial: initial,
    ),
  );
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({
    required this.classId,
    required this.meetingId,
    required this.roll,
    this.initial,
  });
  final String classId;
  final String meetingId;
  final String roll;
  final AttendanceStatus? initial;
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late AttendanceStatus _status;
  @override
  void initState() {
    super.initState();
    _status =
        widget.initial ??
        context
            .read<TeacherViewModel>()
            .course(widget.classId)
            .recordFor(widget.meetingId, widget.roll)
            ?.status ??
        AttendanceStatus.present;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(widget.classId);
    final student = c.students.singleWhere((s) => s.rollNumber == widget.roll);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        24,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sửa kết quả điểm danh',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${student.fullName} · ${student.rollNumber}\n${c.courseCode} · ${c.classCode}\n${meetingLabel(vm.meeting(c.id, widget.meetingId))}',
              ),
              const SizedBox(height: 16),
              SegmentedButton<AttendanceStatus>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AttendanceStatus.present,
                    label: Text('P · Có mặt'),
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.absent,
                    label: Text('A · Vắng'),
                  ),
                ],
                selected: {_status},
                onSelectionChanged: vm.busy
                    ? null
                    : (v) => setState(() => _status = v.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                minLines: 3,
                maxLines: 6,
                enabled: !vm.busy,
                decoration: const InputDecoration(
                  labelText: 'Lý do chỉnh sửa (bắt buộc)',
                  alignLabelWithHint: true,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập lý do chỉnh sửa.'
                    : null,
              ),
              if (vm.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    vm.error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: vm.busy
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        final ok = await vm.edit(
                          c.id,
                          widget.meetingId,
                          widget.roll,
                          _status,
                          _reason.text,
                        );
                        if (context.mounted) {
                          showResult(context, ok);
                          if (ok) Navigator.pop(context);
                        }
                      },
                child: Text(vm.busy ? 'Đang lưu…' : 'Lưu thay đổi'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: vm.busy ? null : () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.classId, required this.meetingId});
  final String classId;
  final String meetingId;
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String _format = 'pdf';
  bool _backup = false;
  bool _exported = false;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final c = vm.course(widget.classId);
    final m = vm.meeting(c.id, widget.meetingId);
    return MobilePage(
      title: 'Xuất kết quả điểm danh',
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
                Text(meetingLabel(m)),
                const SizedBox(height: 8),
                StatusTag(stateLabel(m.state)),
              ],
            ),
          ),
          Totals(classId: c.id, meetingId: m.id),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ĐỊNH DẠNG TỆP',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pdf', label: Text('PDF')),
                    ButtonSegment(value: 'json', label: Text('JSON')),
                    ButtonSegment(value: 'csv', label: Text('CSV')),
                  ],
                  selected: {_format},
                  onSelectionChanged: vm.busy
                      ? null
                      : (v) => setState(() => _format = v.first),
                ),
                const SizedBox(height: 12),
                Text(switch (_format) {
                  'pdf' =>
                    'Báo cáo PDF có thể mở, lưu và chia sẻ trên thiết bị.',
                  'json' => 'Dùng cho Chrome Extension trên máy tính.',
                  _ => 'Dùng trao đổi và đối chiếu dữ liệu bảng tính.',
                }),
                Text(vm.settings.exportHelp),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'NƠI LƯU BÁO CÁO',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_android),
                  title: Text('Lưu trên thiết bị'),
                  subtitle: Text('Mặc định · luôn giữ bản local'),
                ),
                if (vm.uploads != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _backup,
                    onChanged: vm.busy
                        ? null
                        : (v) => setState(() => _backup = v!),
                    title: const Text('Sao lưu Firebase Storage'),
                    subtitle: const Text(
                      'Cần mạng · Xếp theo học kỳ / môn / lớp / buổi học',
                    ),
                  ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: vm.busy || m.state != MeetingState.closed
                ? null
                : () async {
                    final ok = await vm.export(c.id, m.id, _format);
                    if (ok && mounted) setState(() => _exported = true);
                    if (ok && _backup) await vm.upload();
                    if (context.mounted) {
                      showResult(context, ok && vm.error == null);
                    }
                  },
            icon: const Icon(Icons.file_download),
            label: const Text('Xuất file'),
          ),
          if (_exported && vm.exportedFile != null)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Đã lưu file trên thiết bị',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(vm.exportedFile!.uri.pathSegments.last),
                  const SizedBox(height: 8),
                  SelectableText(
                    vm.exportedFile!.path,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: vm.busy ? null : vm.shareExport,
                    icon: const Icon(Icons.share),
                    label: const Text('Chia sẻ tệp'),
                  ),
                  if (vm.uploads != null && vm.reportDestination != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Thư mục Firebase Storage',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      vm.reportDestination!.folderPath,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (vm.uploads != null)
                    LinearProgressIndicator(value: vm.uploadProgress),
                  if (vm.uploads != null)
                    Text('Tải lên: ${(vm.uploadProgress * 100).round()}%'),
                  if (vm.reportBackedUp)
                    const Text(
                      'Đã sao lưu Firebase Storage',
                      style: TextStyle(color: AppColors.success),
                    ),
                  if (vm.uploads != null && !vm.reportBackedUp)
                    OutlinedButton(
                      onPressed: vm.busy
                          ? null
                          : () async {
                              final ok = await vm.upload();
                              if (context.mounted) showResult(context, ok);
                            },
                      child: const Text('Sao lưu Storage / Thử lại'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
