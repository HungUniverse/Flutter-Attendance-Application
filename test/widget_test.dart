import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/schedule_service.dart';

void main() {
  test('khung giờ trường có đủ bốn slot', () {
    expect(ScheduleService.slotTimes.length, 4);
    expect(ScheduleService.slotTimes[1]!.startHour, 7);
    expect(ScheduleService.slotTimes[4]!.endMinute, 15);
  });
}
