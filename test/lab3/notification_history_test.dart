import 'dart:convert';

import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/firebase_services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Messaging extends Fake implements FirebaseMessaging {}

class _Preferences extends Fake implements SharedPreferencesAsync {
  _Preferences(this.values);
  final Map<String, Object?> values;

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      values.keys.where((key) => allowList?.contains(key) ?? true).toSet();

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async => {
    for (final key in await getKeys(allowList: allowList)) key: values[key],
  };
}

void main() {
  test('reads valid account notices despite corrupt stored entries', () async {
    String notice(String id, DateTime date) => jsonEncode(
      AppNotice(id: id, title: 'Demo', body: '', at: date).toJson(),
    );
    final service = FirebaseNotificationService(
      _Messaging(),
      preferences: _Preferences({
        'fap_notice_teacher1_old': notice('old', DateTime(2026, 11, 10)),
        'fap_notice_teacher1_new': notice('new', DateTime(2026, 11, 11)),
        'fap_notice_teacher1_bad_json': '{',
        'fap_notice_teacher1_bad_date':
            '{"id":"bad","title":"Demo","body":"","at":"invalid"}',
        'fap_notice_teacher1_bad_shape': '[]',
        'fap_notice_teacher1_bad_type': 42,
        'fap_notice_teacher2_other': notice('other', DateTime(2026, 11, 12)),
      }),
    );

    final history = await service.history('teacher1');

    expect(history.map((item) => item.id), ['new', 'old']);
    expect(await service.history('teacher3'), isEmpty);
  });
}
