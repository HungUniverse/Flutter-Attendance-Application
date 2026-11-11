import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

Future<File> writeReportAtomically(
  File destination,
  Stream<List<int>> bytes,
) async {
  final temporary = File(
    p.join(destination.parent.path, '.report-${const Uuid().v4()}.tmp'),
  );
  try {
    final writer = await temporary.open(mode: FileMode.write);
    try {
      await for (final chunk in bytes) {
        await writer.writeFrom(chunk);
      }
      await writer.flush();
    } finally {
      await writer.close();
    }
    return await temporary.rename(destination.path);
  } on Object {
    try {
      if (await temporary.exists()) await temporary.delete();
    } on FileSystemException {
      // Keep the original write or rename error.
    }
    rethrow;
  }
}
