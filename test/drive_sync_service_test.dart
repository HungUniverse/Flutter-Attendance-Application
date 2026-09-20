import 'package:fap_attendance/data/drive_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Drive folder paths are cumulative and shared by every class', () {
    final first = DriveSyncService.folderPathsFor(
      r'classes\PRN232_SE1920\sessions\M01.json',
    );
    final second = DriveSyncService.folderPathsFor(
      r'classes\PRM393_SE1917\class.json',
    );

    expect(first, [
      'classes',
      r'classes\PRN232_SE1920',
      r'classes\PRN232_SE1920\sessions',
    ]);
    expect(second.first, 'classes');
    expect(
      DriveSyncService.pathHashFor(first.first),
      DriveSyncService.pathHashFor(second.first),
    );
    expect(
      DriveSyncService.pathHashFor(first[1]),
      isNot(DriveSyncService.pathHashFor(second[1])),
    );
  });
}
