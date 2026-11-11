import '../../domain/models.dart';

/// Captured from the exported report, never reconstructed from a filename or
/// from whichever class happens to be selected later.
class ReportDestination {
  ReportDestination({
    required this.ownerUid,
    required this.semester,
    required this.courseCode,
    required this.classCode,
    required this.meetingNumber,
    required this.meetingDate,
    required this.fileName,
  }) {
    for (final segment in [ownerUid, semester, courseCode, classCode]) {
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(segment)) {
        throw const FormatException('Thông tin thư mục báo cáo không hợp lệ.');
      }
    }
    if (meetingNumber < 1 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*\.(json|csv)$')
            .hasMatch(fileName)) {
      throw const FormatException('Tên tệp hoặc số buổi học không hợp lệ.');
    }
  }

  factory ReportDestination.forExport({
    required String uid,
    required TeacherWorkspace workspace,
    required CourseClass course,
    required Meeting meeting,
    required String fileName,
  }) => ReportDestination(
    ownerUid: uid,
    semester: workspace.semester,
    courseCode: course.courseCode,
    classCode: course.classCode,
    meetingNumber: meeting.number,
    meetingDate: meeting.startAt,
    fileName: fileName,
  );

  final String ownerUid;
  final String semester;
  final String courseCode;
  final String classCode;
  final int meetingNumber;
  final DateTime meetingDate;
  final String fileName;

  String get dateKey =>
      '${meetingDate.year.toString().padLeft(4, '0')}-'
      '${meetingDate.month.toString().padLeft(2, '0')}-'
      '${meetingDate.day.toString().padLeft(2, '0')}';
  String get meetingFolder =>
      '${dateKey}_Slot-${meetingNumber.toString().padLeft(2, '0')}';
  String get folderPath =>
      'reports/$ownerUid/$semester/$courseCode/$classCode/$meetingFolder';
  String get objectPath => '$folderPath/$fileName';
  Map<String, String> get metadata => {
    'ownerUid': ownerUid,
    'semester': semester,
    'courseCode': courseCode,
    'classCode': classCode,
    'meetingNumber': '$meetingNumber',
    'meetingDate': dateKey,
    'storageLayout': 'semester-course-class-meeting-v1',
  };
}
