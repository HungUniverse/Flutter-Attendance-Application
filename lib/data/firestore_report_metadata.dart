import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/models.dart';
import 'firestore_workspace_remote.dart';
import 'report_file_writer.dart';

class FirestoreReportMetadata {
  FirestoreReportMetadata(this.db, this.root);
  final FirebaseFirestore db;
  final Directory root;
  String? warning;
  Directory _queue(String uid) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(uid)) {
      throw ArgumentError('Invalid UID');
    }
    return Directory(
      p.join(root.path, 'teachers', uid, 'report-metadata-outbox'),
    );
  }

  Future<void> record(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
    File file,
    String format,
  ) async {
    final digest = sha256.convert(await file.readAsBytes()).toString();
    final id = sha256
        .convert(
          utf8.encode(
            '$uid/${workspace.semester}/${course.id}/${meeting.id}/$format/$digest',
          ),
        )
        .toString();
    final pending = File(p.join(_queue(uid).path, '$id.json'));
    final payload = {
      'ownerUid': uid,
      'classId': firestoreClassId(uid, workspace.semester, course.id),
      'meetingId': meeting.id,
      'fileName': p.basename(file.path),
      'format': format,
      'bytes': await file.length(),
    };
    try {
      await pending.parent.create(recursive: true);
      await writeReportAtomically(
        pending,
        Stream.value(utf8.encode(jsonEncode(payload))),
      );
      await flush(uid);
    } on Object {
      warning = 'Tệp đã lưu trên máy. Chưa ghi được metadata báo cáo lên Firestore, hãy xuất lại để thử.';
    }
  }

  Future<void> flush(String uid) async {
    warning = null;
    final queue = _queue(uid);
    if (!await queue.exists()) return;
    await for (final entry in queue.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final payload =
            jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
        if (payload['ownerUid'] != uid) {
          throw StateError('Metadata owner mismatch');
        }
        final ref = db.doc(
          'reportMetadata/${p.basenameWithoutExtension(entry.path)}',
        );
        await db
            .runTransaction((tx) async {
              if (!(await tx.get(ref)).exists) {
                tx.set(ref, {...payload, 'at': FieldValue.serverTimestamp()});
              }
            })
            .timeout(const Duration(seconds: 10));
        await entry.delete();
      } on Object {
        warning = 'Tệp đã lưu trên máy · Metadata báo cáo đang chờ đồng bộ.';
      }
    }
  }
}
