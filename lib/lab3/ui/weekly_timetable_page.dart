import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/models.dart';
import '../../domain/schedule_service.dart';
import '../viewmodels/teacher_view_model.dart';
import 'components.dart';

const _navy = Color(0xFF172A42);
const _orange = Color(0xFFF69700);
const _paper = Color(0xFFF5F5F6);
const _line = Color(0xFFE8E8EA);
const _muted = Color(0xFF626B79);
const _subtle = Color(0xFF687280);
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _meetUrl = 'https://meet.google.com/meet/ptq-remp-zui';
const _meetChannel = MethodChannel('vn.edu.fpt.fap_attendance/meet');

Future<void> _openMeet(BuildContext context) async {
  try {
    await _meetChannel.invokeMethod<void>('open', _meetUrl);
    return;
  } on PlatformException {
    // Offer the same link when Android has no browser or Meet handler.
  } on MissingPluginException {
    // Widget previews do not register the Android channel.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Không mở được Google Meet.'),
      action: SnackBarAction(
        label: 'Sao chép',
        onPressed: () => Clipboard.setData(const ClipboardData(text: _meetUrl)),
      ),
    ),
  );
}

class WeeklyTimetablePage extends StatefulWidget {
  const WeeklyTimetablePage({
    super.key,
    required this.onHome,
    required this.onMeeting,
    required this.bottom,
    required this.startAtSemester,
  });

  final VoidCallback onHome;
  final void Function(String classId, String meetingId) onMeeting;
  final Widget bottom;
  final bool startAtSemester;

  @override
  State<WeeklyTimetablePage> createState() => _WeeklyTimetablePageState();
}

class _WeeklyTimetablePageState extends State<WeeklyTimetablePage> {
  final _scroll = ScrollController();
  final _dayKeys = List.generate(7, (_) => GlobalKey());
  late final Future<List<String>> _semesters;
  late DateTime _monday;
  late DateTime _selected;

  static DateTime _shift(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  @override
  void initState() {
    super.initState();
    final vm = context.read<TeacherViewModel>();
    final workspace = vm.workspace!;
    final today = DateUtils.dateOnly(vm.now().toLocal());
    final start = workspace.semesterStart.toLocal();
    // Keep opening on the current week. Other semesters start at their first
    // teaching week when selected explicitly.
    _selected = widget.startAtSemester ? DateUtils.dateOnly(start) : today;
    _monday = _shift(_selected, 1 - _selected.weekday);
    _semesters = vm.repository.listSemesters(vm.uid);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showWeek(DateTime date) {
    setState(() {
      _selected = DateUtils.dateOnly(date);
      _monday = _shift(_selected, 1 - _selected.weekday);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _showDay(DateTime day) {
    setState(() => _selected = day);
    final target = _dayKeys[day.weekday - 1].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(_selected.year < 2020 ? _selected.year : 2020),
      lastDate: DateTime(_selected.year > 2100 ? _selected.year : 2100, 12, 31),
    );
    if (date != null && mounted) {
      _showWeek(date);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && DateUtils.isSameDay(_selected, date)) _showDay(date);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TeacherViewModel>();
    final workspace = vm.workspace!;
    final days = List.generate(7, (i) => _shift(_monday, i));
    final today = vm.now().toLocal();
    final currentMonday = _shift(today, 1 - today.weekday);
    final currentWeek = DateUtils.isSameDay(_monday, currentMonday);
    final end = _shift(_monday, 7);
    final meetings = List.generate(7, (_) => <(CourseClass, Meeting)>[]);
    for (final course in workspace.classes) {
      for (final meeting in course.meetings) {
        final start = meeting.startAt.toLocal();
        if (!start.isBefore(_monday) && start.isBefore(end)) {
          meetings[start.weekday - 1].add((course, meeting));
        }
      }
    }
    for (final day in meetings) {
      day.sort((a, b) {
        final time = a.$2.startAt.compareTo(b.$2.startAt);
        return time != 0 ? time : a.$1.id.compareTo(b.$1.id);
      });
    }
    final dateFormat = DateFormat('dd/MM/yyyy', 'en_US');
    final lecturer = vm.user?.name.trim();
    final syncStatus = vm.sync?.status;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 82,
        leading: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.only(right: 4),
          ),
          onPressed: widget.onHome,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios_new, size: 17),
                SizedBox(width: 4),
                Text('Home', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
        title: const Text(
          'Weekly timetable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        titleSpacing: 4,
        toolbarHeight: 48,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
        backgroundColor: _navy,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      bottomNavigationBar: widget.bottom,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (vm.busy)
              const LinearProgressIndicator(minHeight: 2, color: _orange),
            if (vm.error case final error?)
              Material(
                color: const Color(0xFFFFECE9),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(error, style: const TextStyle(fontSize: 13)),
                    ),
                    IconButton(
                      tooltip: 'Đóng thông báo',
                      onPressed: vm.dismissMessage,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ColoredBox(
              color: _paper,
              child: Column(
                children: [
                  FutureBuilder<List<String>>(
                    future: _semesters,
                    builder: (context, snapshot) {
                      final semesters = {workspace.semester, ...?snapshot.data};
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(11, 12, 11, 13),
                        child: Row(
                          children: [
                            for (final semester in semesters)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _SemesterChip(
                                  semester: semester,
                                  selected: semester == workspace.semester,
                                  onTap:
                                      vm.busy || semester == workspace.semester
                                      ? null
                                      : () => vm.selectSemester(semester),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: currentWeek
                          ? _pickDate
                          : () => _showWeek(vm.now().toLocal()),
                      style: TextButton.styleFrom(
                        foregroundColor: _muted,
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                      ),
                      child: Text(
                        '${currentWeek ? 'Current week' : 'Week'}: '
                        '${dateFormat.format(days.first)} – ${dateFormat.format(days.last)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFBFC0C3)),
            Row(
              children: [
                IconButton(
                  tooltip: 'Tuần trước',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 38,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showWeek(_shift(_monday, -7)),
                  icon: const Icon(
                    Icons.arrow_left_rounded,
                    color: _navy,
                    size: 27,
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _pickDate,
                    style: TextButton.styleFrom(
                      foregroundColor: _navy,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      DateFormat('MMMM yyyy', 'en_US').format(_selected),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tuần sau',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 38,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showWeek(_shift(_monday, 7)),
                  icon: const Icon(
                    Icons.arrow_right_rounded,
                    color: _navy,
                    size: 27,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: _CalendarDay(
                        day: days[i],
                        selected: DateUtils.isSameDay(_selected, days[i]),
                        hasMeetings: meetings[i].isNotEmpty,
                        onTap: () => _showDay(days[i]),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFBFC0C3)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: vm.refresh,
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (syncStatus != null && syncStatus != 'Đã đồng bộ')
                          TextButton(
                            onPressed: widget.onHome,
                            child: Text(
                              syncStatus,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (meetings.every((day) => day.isEmpty))
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Chưa có lịch dạy trong tuần này.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                          ),
                        for (var i = 0; i < days.length; i++)
                          _TimetableDay(
                            key: _dayKeys[i],
                            day: days[i],
                            meetings: meetings[i],
                            lecturer: lecturer,
                            onMeeting: widget.onMeeting,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SemesterChip extends StatelessWidget {
  const _SemesterChip({
    required this.semester,
    required this.selected,
    required this.onTap,
  });

  final String semester;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final term = RegExp(r'^(FALL|SUMMER|SPRING|FA|SU|SP)[ _-]?(\d{4}|\d{2})$')
        .firstMatch(semester.toUpperCase());
    final (name, icon) = switch (term?.group(1)) {
      'FA' || 'FALL' => ('FALL', Icons.park_rounded),
      'SU' || 'SUMMER' => ('SUMMER', Icons.wb_sunny_rounded),
      'SP' || 'SPRING' => ('SPRING', Icons.eco_rounded),
      _ => ('', Icons.school_rounded),
    };
    final year = term?.group(2);
    final label = year == null
        ? semester
        : '$name${year.length == 2 ? '20$year' : year}';
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? _orange : Colors.white,
        elevation: selected ? 3 : 1,
        shadowColor: selected
            ? const Color(0x55F69700)
            : const Color(0x250E243F),
        shape: StadiumBorder(
          side: BorderSide(color: selected ? _orange : _line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: selected ? const Color(0x55FFFFFF) : _paper,
                  child: Icon(
                    icon,
                    size: 13,
                    color: selected ? Colors.white : _subtle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? const Color(0xFF241A08) : _navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .55,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.selected,
    required this.hasMeetings,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool hasMeetings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${DateFormat('EEEE, d MMMM yyyy', 'en_US').format(day)}'
        '${hasMeetings ? ', có lịch dạy' : ''}',
    selected: selected,
    button: true,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _weekdays[day.weekday - 1],
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? _navy : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: selected ? Colors.white : _navy,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (hasMeetings)
                  Positioned(
                    bottom: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? Colors.white : _navy,
                      ),
                      child: const SizedBox.square(dimension: 3.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimetableDay extends StatelessWidget {
  const _TimetableDay({
    super.key,
    required this.day,
    required this.meetings,
    required this.lecturer,
    required this.onMeeting,
  });

  final DateTime day;
  final List<(CourseClass, Meeting)> meetings;
  final String? lecturer;
  final void Function(String classId, String meetingId) onMeeting;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dateWidth = (constraints.maxWidth * .20).clamp(54.0, 104.0);
      final slotWidth = (constraints.maxWidth * .19).clamp(60.0, 96.0);
      return DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: dateWidth,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: _line)),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${day.day}/${day.month.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            _weekdays[day.weekday - 1],
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: dateWidth),
              child: meetings.isEmpty
                  ? const SizedBox(height: 52, width: double.infinity)
                  : Column(
                      children: [
                        for (var i = 0; i < meetings.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: _line),
                          _MeetingRow(
                            course: meetings[i].$1,
                            meeting: meetings[i].$2,
                            lecturer: lecturer,
                            slotWidth: slotWidth,
                            onTap: () =>
                                onMeeting(meetings[i].$1.id, meetings[i].$2.id),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.course,
    required this.meeting,
    required this.lecturer,
    required this.slotWidth,
    required this.onTap,
  });

  final CourseClass course;
  final Meeting meeting;
  final String? lecturer;
  final double slotWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = meeting.startAt.toLocal();
    int? slot;
    for (final entry in ScheduleService.slotTimes.entries) {
      if (entry.value.startHour == start.hour &&
          entry.value.startMinute == start.minute) {
        slot = entry.key;
        break;
      }
    }
    final stripe = switch (slot) {
      1 => const Color(0xFF257BC3),
      2 => const Color(0xFF36CE27),
      3 => const Color(0xFFE47128),
      4 => const Color(0xFF3018D5),
      _ => _muted,
    };
    final (label, badgeColor) = switch (meeting.state) {
      MeetingState.upcoming => ('NOT YET', const Color(0xFF646970)),
      MeetingState.active => ('CHECK-IN', const Color(0xFF087960)),
      MeetingState.closed => ('FINALIZED', const Color(0xFF19751B)),
    };
    final time = DateFormat('HH:mm', 'en_US');
    const details = TextStyle(color: _muted, fontSize: 12, height: 1.3);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: stripe,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: slotWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 5, 0),
                      child: Column(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: stripe.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Text(
                                slot == null ? 'Học bù' : 'Slot $slot',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color.lerp(stripe, Colors.black, .28),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(time.format(start), style: details),
                          const SizedBox(
                            height: 11,
                            child: VerticalDivider(width: 1, color: _line),
                          ),
                          Text(
                            time.format(meeting.endAt.toLocal()),
                            style: details,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Room',
                                  style: TextStyle(
                                    color: _subtle,
                                    fontSize: 10,
                                    height: 1.2,
                                  ),
                                ),
                                Text(
                                  'Chưa có phòng',
                                  style: TextStyle(
                                    color: _navy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            course.courseCode,
                            style: details.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('SessionNo: ${meeting.number}', style: details),
                          Text('Class: ${course.classCode}', style: details),
                          if (lecturer != null && lecturer!.isNotEmpty)
                            Text('Lecturer: $lecturer', style: details),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Semantics(
                                label: stateLabel(meeting.state),
                                excludeSemantics: true,
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: badgeColor,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .45,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _openMeet(context),
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFF087960),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 27),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('Meet URL'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimetableNavigation extends StatelessWidget {
  const TimetableNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7F7F9), Color(0xFFDEE4E9)],
      ),
      border: Border(top: BorderSide(color: Color(0xFFBFC0C3))),
    ),
    child: Padding(
      padding: EdgeInsets.only(
        top: selected == 0 && MediaQuery.sizeOf(context).height >= 500 ? 26 : 0,
      ),
      child: Material(
        color: _navy,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              for (final (index, icon, label) in const [
                (0, Icons.home_rounded, 'Lịch & lớp'),
                (1, Icons.chat_bubble_rounded, 'Thông báo'),
                (2, Icons.person_rounded, 'Tài khoản'),
              ])
                Expanded(
                  child: Center(
                    heightFactor: 1,
                    child: Semantics(
                      selected: index == selected,
                      child: IconButton(
                        key: ValueKey('timetable-nav-$index'),
                        tooltip: label,
                        onPressed: () => onSelected(index),
                        style: IconButton.styleFrom(
                          backgroundColor: index == selected
                              ? const Color(0xFF343D46)
                              : null,
                          foregroundColor: index == selected
                              ? const Color(0xFFFFA327)
                              : const Color(0xFF9CA8B7),
                          minimumSize: const Size(50, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        icon: Icon(icon, size: 24),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
