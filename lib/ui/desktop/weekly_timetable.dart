import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/schedule_service.dart';
import '../theme.dart';

/// Displays generated meetings, including make-up dates, rather than repeating
/// schedule rules. Multiple meetings in one cell are intentionally preserved.
class WeeklyTimetable extends StatefulWidget {
  const WeeklyTimetable({
    super.key,
    required this.classes,
    required this.onOpenMeeting,
    this.now,
  });

  final List<CourseClass> classes;
  final void Function(CourseClass, Meeting) onOpenMeeting;
  final DateTime? now;

  @override
  State<WeeklyTimetable> createState() => _WeeklyTimetableState();
}

class _WeeklyTimetableState extends State<WeeklyTimetable> {
  final _horizontalScroll = ScrollController();
  late DateTime _weekStart;
  Timer? _clock;

  DateTime get _now => widget.now ?? DateTime.now();

  static DateTime _monday(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day - date.weekday + DateTime.monday,
  );

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(_now);
    if (widget.now == null) {
      _clock = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _moveWeek(int direction) => setState(() {
    _weekStart = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + direction * 7,
    );
  });

  Future<void> _pickWeek() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() => _weekStart = _monday(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final days = List.generate(
      7,
      (index) =>
          DateTime(_weekStart.year, _weekStart.month, _weekStart.day + index),
    );
    final nextWeek = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + 7,
    );
    final meetings =
        <(CourseClass, Meeting)>[
          for (final course in widget.classes)
            for (final meeting in course.meetings)
              if (!meeting.startAt.toLocal().isBefore(_weekStart) &&
                  meeting.startAt.toLocal().isBefore(nextWeek))
                (course, meeting),
        ]..sort((a, b) {
          final byTime = a.$2.startAt.compareTo(b.$2.startAt);
          return byTime != 0 ? byTime : a.$1.id.compareTo(b.$1.id);
        });

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thời khóa biểu tuần',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat('dd/MM/yyyy').format(days.first)} – '
                      '${DateFormat('dd/MM/yyyy').format(days.last)}'
                      ' · ${meetings.length} slot học',
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton.outlined(
                      tooltip: 'Tuần trước',
                      onPressed: () => _moveWeek(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _weekStart = _monday(now);
                      }),
                      child: const Text('Tuần này'),
                    ),
                    IconButton.outlined(
                      tooltip: 'Tuần sau',
                      onPressed: () => _moveWeek(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickWeek,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Chọn tuần'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (meetings.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Tuần này không có lịch dạy. Chọn tuần khác để xem lớp.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 1220
                    ? 1220.0
                    : constraints.maxWidth;
                return Scrollbar(
                  controller: _horizontalScroll,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: width,
                      child: Table(
                        border: TableBorder.all(color: AppColors.border),
                        columnWidths: const {0: FixedColumnWidth(100)},
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.top,
                        children: [
                          TableRow(
                            children: [
                              _header('Slot', false),
                              for (final day in days)
                                _header(
                                  '${_weekday(day.weekday)}\n'
                                  '${DateFormat('dd/MM').format(day)}',
                                  _sameDay(day, now),
                                ),
                            ],
                          ),
                          for (final slot in ScheduleService.slotTimes.entries)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 22,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Slot ${slot.key}',
                                        style: const TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${_time(slot.value.startHour, slot.value.startMinute)}\n'
                                        '${_time(slot.value.endHour, slot.value.endMinute)}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                                for (final day in days)
                                  _dayCell(
                                    day,
                                    now,
                                    meetings.where((item) {
                                      final start = item.$2.startAt.toLocal();
                                      return _sameDay(start, day) &&
                                          _slotFor(item.$1, start) == slot.key;
                                    }).toList(),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String text, bool today) => Container(
    height: 70,
    alignment: Alignment.center,
    color: today ? AppColors.orangeSoft : AppColors.panel,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: today ? AppColors.orangeDark : AppColors.ink,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _dayCell(
    DateTime day,
    DateTime now,
    List<(CourseClass, Meeting)> entries,
  ) => Container(
    constraints: const BoxConstraints(minHeight: 170),
    padding: const EdgeInsets.all(8),
    color: _sameDay(day, now) ? AppColors.creamLight : Colors.white,
    child: entries.isEmpty
        ? const Center(child: Text('—'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _meetingCard(entry.$1, entry.$2, now),
                ),
            ],
          ),
  );

  Widget _meetingCard(CourseClass course, Meeting meeting, DateTime now) {
    final (status, color) = switch (meeting.state) {
      MeetingState.closed => ('Đã chốt', AppColors.success),
      MeetingState.active => ('Đang điểm danh', AppColors.orangeDark),
      MeetingState.upcoming when now.isBefore(meeting.startAt) => (
        'Sắp tới',
        AppColors.info,
      ),
      MeetingState.upcoming when !now.isBefore(meeting.endAt) => (
        'Đã qua',
        AppColors.muted,
      ),
      _ => ('Đang học', AppColors.orangeDark),
    };
    final start = meeting.startAt.toLocal();
    final end = meeting.endAt.toLocal();
    return Semantics(
      button: true,
      label:
          'Mở ${course.courseCode}, ${course.classCode}, '
          '${DateFormat('dd/MM/yyyy HH:mm').format(start)}, $status',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: .25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpenMeeting(course, meeting),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.courseCode} · ${course.classCode}',
                  style: const TextStyle(
                    color: AppColors.orangeDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${DateFormat('HH:mm').format(start)}–'
                  '${DateFormat('HH:mm').format(end)}',
                  style: const TextStyle(color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'Slot học ${meeting.number} · ${course.students.length} SV',
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _slotFor(CourseClass course, DateTime start) {
    final minute = start.hour * 60 + start.minute;
    for (final entry in ScheduleService.slotTimes.entries) {
      final slot = entry.value;
      if (minute >= slot.startHour * 60 + slot.startMinute &&
          minute < slot.endHour * 60 + slot.endMinute) {
        return entry.key;
      }
    }
    return course.scheduleRule.dailySlot;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String _weekday(int day) => const [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ][day - 1];
}
