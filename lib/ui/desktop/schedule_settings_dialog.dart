import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/schedule_service.dart';
import '../theme.dart';

Future<ScheduleRule?> showScheduleSettingsDialog(
  BuildContext context,
  CourseClass courseClass,
) => showDialog<ScheduleRule>(
  context: context,
  builder: (_) => _ScheduleSettingsDialog(courseClass: courseClass),
);

class _ScheduleSettingsDialog extends StatefulWidget {
  const _ScheduleSettingsDialog({required this.courseClass});

  final CourseClass courseClass;

  @override
  State<_ScheduleSettingsDialog> createState() =>
      _ScheduleSettingsDialogState();
}

class _ScheduleSettingsDialogState extends State<_ScheduleSettingsDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController weeks;
  late final TextEditingController excluded;
  late final TextEditingController additional;
  late int meetingsPerWeek;
  late Set<int> selectedDays;

  ScheduleRule get rule => widget.courseClass.scheduleRule;
  List<int> get groupDays => ScheduleService.weekdaysByGroup[rule.dayGroup]!;

  @override
  void initState() {
    super.initState();
    weeks = TextEditingController(text: '${rule.weeks}');
    excluded = TextEditingController(
      text: rule.excludedDates
          .map((date) => DateFormat('yyyy-MM-dd').format(date))
          .join(', '),
    );
    additional = TextEditingController(
      text: rule.additionalStarts
          .map((date) => DateFormat('yyyy-MM-dd').format(date))
          .join(', '),
    );
    meetingsPerWeek = rule.meetingsPerWeek;
    selectedDays =
        (rule.weekdays.isEmpty
                ? groupDays.take(meetingsPerWeek)
                : rule.weekdays)
            .toSet();
  }

  @override
  void dispose() {
    weeks.dispose();
    excluded.dispose();
    additional.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedWeeks = int.tryParse(weeks.text) ?? 0;
    final estimatedMeetings = parsedWeeks * meetingsPerWeek;
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      title: Container(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        decoration: const BoxDecoration(
          color: AppColors.creamLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.edit_calendar_outlined,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cấu hình lịch riêng',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.courseClass.courseCode} · ${widget.courseClass.classCode}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: weeks,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Số tuần giảng dạy',
                          prefixIcon: Icon(Icons.date_range_outlined),
                          suffixText: 'tuần',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final number = int.tryParse(value ?? '');
                          if (number == null || number < 1 || number > 52) {
                            return 'Nhập từ 1 đến 52 tuần';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: meetingsPerWeek,
                        decoration: const InputDecoration(
                          labelText: 'Số slot mỗi tuần',
                          prefixIcon: Icon(Icons.repeat_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 slot')),
                          DropdownMenuItem(value: 2, child: Text('2 slot')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            meetingsPerWeek = value;
                            selectedDays = value == 2
                                ? groupDays.toSet()
                                : {selectedDays.firstOrNull ?? groupDays.first};
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Ngày học trong tuần',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: groupDays.map((day) {
                    final selected = selectedDays.contains(day);
                    return ChoiceChip(
                      label: Text(_weekdayName(day)),
                      selected: selected,
                      onSelected: meetingsPerWeek == 2
                          ? null
                          : (_) => setState(() => selectedDays = {day}),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: const Text(
                    'Ngày nghỉ và học bù',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Tùy chọn nâng cao'),
                  children: [
                    TextFormField(
                      controller: excluded,
                      decoration: const InputDecoration(
                        labelText: 'Ngày nghỉ',
                        hintText: '2026-09-21, 2026-10-05',
                      ),
                      validator: _validateDates,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: additional,
                      decoration: const InputDecoration(
                        labelText: 'Ngày học bù',
                        hintText: '2026-10-11',
                      ),
                      validator: _validateDates,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.orangeSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppColors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Dự kiến $estimatedMeetings slot trước khi trừ ngày nghỉ và cộng lịch học bù.',
                          style: const TextStyle(
                            color: AppColors.orangeDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Lưu và sinh lại lịch'),
        ),
      ],
    );
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ScheduleRule(
        scheduleCode: rule.scheduleCode,
        semesterStart: rule.semesterStart,
        weeks: int.parse(weeks.text),
        meetingsPerWeek: meetingsPerWeek,
        weekdays: selectedDays.toList()..sort(),
        excludedDates: _parseDates(excluded.text),
        additionalStarts: _parseDates(additional.text),
      ),
    );
  }

  String? _validateDates(String? source) {
    try {
      _parseDates(source ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  List<DateTime> _parseDates(String source) => source
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map((value) {
        try {
          return DateFormat('yyyy-MM-dd').parseStrict(value);
        } on FormatException {
          throw FormatException('Ngày "$value" không đúng yyyy-MM-dd.');
        }
      })
      .toList();

  String _weekdayName(int day) => switch (day) {
    DateTime.monday => 'Thứ Hai',
    DateTime.tuesday => 'Thứ Ba',
    DateTime.wednesday => 'Thứ Tư',
    DateTime.thursday => 'Thứ Năm',
    DateTime.friday => 'Thứ Sáu',
    DateTime.saturday => 'Thứ Bảy',
    _ => 'Ngày $day',
  };
}
