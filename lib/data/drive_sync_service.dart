import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class DriveConflictException implements Exception {
  const DriveConflictException(this.paths);
  final List<String> paths;

  @override
  String toString() => 'Có ${paths.length} file xung đột cần xem lại.';
}

class DriveLeaseException implements Exception {
  const DriveLeaseException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DriveSourceFile {
  const DriveSourceFile({required this.id, required this.name});
  final String id;
  final String name;
}

class DriveSyncResult {
  const DriveSyncResult({
    required this.uploaded,
    required this.unchanged,
    required this.cleanedFolders,
    required this.cleanedFiles,
  });

  final int uploaded;
  final int unchanged;
  final int cleanedFolders;
  final int cleanedFiles;
}

class DriveSyncService {
  DriveSyncService(this.api, {String? deviceId})
    : deviceId = deviceId ?? const Uuid().v4();

  final drive.DriveApi api;
  final String deviceId;

  Future<String> ensureRootFolder() => _ensureFolder(
    name: 'FAP Attendance',
    parentId: null,
    properties: const {'app': 'fap-attendance', 'kind': 'root'},
  );

  Future<void> acquireLease(String workspaceId) async {
    final rootId = await ensureRootFolder();
    final existing = await _findOne({
      'app': 'fap-attendance',
      'kind': 'device-lease',
      'workspaceId': workspaceId,
    });
    if (existing != null) {
      final bytes = await _download(existing.id!);
      final lease = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      final expiresAt = DateTime.parse(lease['expiresAt']! as String);
      if (expiresAt.isAfter(DateTime.now().toUtc()) &&
          lease['deviceId'] != deviceId) {
        throw const DriveLeaseException(
          'Workspace đang được mở để ghi trên thiết bị khác.',
        );
      }
    }
    final data = utf8.encode(
      jsonEncode({
        'workspaceId': workspaceId,
        'deviceId': deviceId,
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 3))
            .toIso8601String(),
      }),
    );
    await _upsert(
      existing: existing,
      name: 'device_lease.json',
      parentId: rootId,
      bytes: data,
      properties: {
        'app': 'fap-attendance',
        'kind': 'device-lease',
        'workspaceId': workspaceId,
      },
    );
  }

  Future<DriveSyncResult> syncDirectory({
    required Directory semesterDirectory,
    required String workspaceId,
  }) async {
    await acquireLease(workspaceId);
    final rootId = await ensureRootFolder();
    final semesterId = await _ensureFolder(
      name: p.basename(semesterDirectory.path),
      parentId: rootId,
      properties: {
        'app': 'fap-attendance',
        'kind': 'semester',
        'workspaceId': workspaceId,
      },
    );
    final cleanedFolders = await _cleanupLegacyTopLevelFolders(
      semesterId: semesterId,
      workspaceId: workspaceId,
    );
    final conflicts = <String>[];
    var uploaded = 0;
    var unchanged = 0;
    await for (final entity in semesterDirectory.list(recursive: true)) {
      if (entity is! File ||
          entity.path.endsWith('.tmp') ||
          entity.path.endsWith('.bak') ||
          entity.path.endsWith('.drive-conflict')) {
        continue;
      }
      final relative = p.relative(entity.path, from: semesterDirectory.path);
      final parts = p.split(relative);
      var parentId = semesterId;
      final folderParts = parts.take(parts.length - 1).toList();
      final folderPaths = folderPathsFor(relative);
      for (var index = 0; index < folderParts.length; index++) {
        final folder = folderParts[index];
        parentId = await _ensureFolder(
          name: folder,
          parentId: parentId,
          properties: {
            'app': 'fap-attendance',
            'kind': 'folder',
            'workspaceId': workspaceId,
            'pathHash': pathHashFor(folderPaths[index]),
          },
        );
      }
      final bytes = await entity.readAsBytes();
      final properties = {
        'app': 'fap-attendance',
        'workspaceId': workspaceId,
        'kind': _kindFor(relative),
        'pathHash': pathHashFor(relative),
      };
      final currentExisting = await _findOne(properties, parentId: parentId);
      final existing =
          currentExisting ??
          await _findLegacyFile(
            parentId: parentId,
            name: parts.last,
            workspaceId: workspaceId,
          );
      final localChecksum = md5.convert(bytes).toString();
      if (currentExisting?.md5Checksum == localChecksum) {
        unchanged++;
        continue;
      }
      if (existing?.md5Checksum != null &&
          existing!.md5Checksum != localChecksum &&
          existing.modifiedTime != null &&
          existing.modifiedTime!.isAfter(
            (await entity.lastModified()).toUtc(),
          )) {
        final remote = await _download(existing.id!);
        await File('${entity.path}.drive-conflict')
            .writeAsBytes(remote, flush: true);
        conflicts.add(relative);
        continue;
      }
      await _upsert(
        existing: existing,
        name: parts.last,
        parentId: parentId,
        bytes: bytes,
        properties: properties,
      );
      uploaded++;
    }
    if (conflicts.isNotEmpty) throw DriveConflictException(conflicts);
    final cleanedFiles = await _cleanupLegacySessionFiles(workspaceId);
    return DriveSyncResult(
      uploaded: uploaded,
      unchanged: unchanged,
      cleanedFolders: cleanedFolders,
      cleanedFiles: cleanedFiles,
    );
  }

  Future<int> _cleanupLegacySessionFiles(String workspaceId) async {
    final result = await api.files.list(
      q: "trashed = false and appProperties has { key='app' and value='fap-attendance' } and appProperties has { key='kind' and value='session' } and appProperties has { key='workspaceId' and value='$workspaceId' }",
      spaces: 'drive',
      pageSize: 1000,
      $fields: 'files(id,name,parents)',
    );
    final legacyName = RegExp(
      r'^(M\d{2}_\d{4}-\d{2}-\d{2})(?:_working|_v\d{3}_(?:final|correction))\.json$',
    );
    var cleaned = 0;
    for (final file in result.files ?? const <drive.File>[]) {
      final id = file.id;
      final name = file.name;
      final parents = file.parents;
      if (id == null || name == null || parents == null || parents.isEmpty) {
        continue;
      }
      final match = legacyName.firstMatch(name);
      if (match == null) continue;
      final stable = await _findLegacyFile(
        parentId: parents.first,
        name: '${match.group(1)}.json',
        workspaceId: workspaceId,
      );
      if (stable?.id == null || stable!.id == id) continue;
      await api.files.update(drive.File()..trashed = true, id);
      cleaned++;
    }
    return cleaned;
  }

  Future<int> _cleanupLegacyTopLevelFolders({
    required String semesterId,
    required String workspaceId,
  }) async {
    final result = await api.files.list(
      q: "trashed = false and '$semesterId' in parents and mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='app' and value='fap-attendance' } and appProperties has { key='kind' and value='folder' } and appProperties has { key='workspaceId' and value='$workspaceId' }",
      spaces: 'drive',
      pageSize: 1000,
      $fields: 'files(id,name,appProperties)',
    );
    var cleaned = 0;
    for (final folder in result.files ?? const <drive.File>[]) {
      final id = folder.id;
      final name = folder.name;
      if (id == null || name == null) continue;
      final actualHash = folder.appProperties?['pathHash'];
      if (actualHash == pathHashFor(name)) continue;
      await api.files.update(drive.File()..trashed = true, id);
      cleaned++;
    }
    return cleaned;
  }

  Future<List<DriveSourceFile>> listSourceFiles() async {
    final result = await api.files.list(
      q: "trashed = false and appProperties has { key='app' and value='fap-attendance' } and appProperties has { key='kind' and value='source' }",
      spaces: 'drive',
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,name)',
    );
    return (result.files ?? const [])
        .where((file) => file.id != null && file.name != null)
        .map((file) => DriveSourceFile(id: file.id!, name: file.name!))
        .toList();
  }

  Future<List<int>> downloadSource(String fileId) => _download(fileId);

  Future<String> _ensureFolder({
    required String name,
    required String? parentId,
    required Map<String, String> properties,
  }) async {
    final found = await _findOne(properties, parentId: parentId);
    if (found != null) return found.id!;
    final metadata = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..appProperties = properties
      ..parents = parentId == null ? null : [parentId];
    return (await api.files.create(metadata, $fields: 'id')).id!;
  }

  Future<drive.File?> _findOne(
    Map<String, String> properties, {
    String? parentId,
  }) async {
    final clauses = <String>['trashed = false'];
    if (parentId != null) clauses.add("'$parentId' in parents");
    for (final entry in properties.entries) {
      final key = entry.key.replaceAll("'", r"\'");
      final value = entry.value.replaceAll("'", r"\'");
      clauses.add("appProperties has { key='$key' and value='$value' }");
    }
    final result = await api.files.list(
      q: clauses.join(' and '),
      spaces: 'drive',
      pageSize: 2,
      $fields: 'files(id,name,modifiedTime,md5Checksum,parents,appProperties)',
    );
    return result.files?.firstOrNull;
  }

  Future<drive.File?> _findLegacyFile({
    required String parentId,
    required String name,
    required String workspaceId,
  }) async {
    final escapedName = name.replaceAll("'", r"\'");
    final result = await api.files.list(
      q: "trashed = false and '$parentId' in parents and name = '$escapedName' and mimeType != 'application/vnd.google-apps.folder' and appProperties has { key='app' and value='fap-attendance' } and appProperties has { key='workspaceId' and value='$workspaceId' }",
      spaces: 'drive',
      pageSize: 2,
      $fields: 'files(id,name,modifiedTime,md5Checksum,parents,appProperties)',
    );
    return result.files?.firstOrNull;
  }

  Future<void> _upsert({
    required drive.File? existing,
    required String name,
    required String parentId,
    required List<int> bytes,
    required Map<String, String> properties,
  }) async {
    final metadata = drive.File()
      ..name = name
      ..appProperties = properties
      ..parents = existing == null ? [parentId] : null;
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existing == null) {
      await api.files.create(metadata, uploadMedia: media, $fields: 'id');
    } else {
      await api.files.update(metadata, existing.id!, uploadMedia: media);
    }
  }

  Future<List<int>> _download(String fileId) async {
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    return media.stream.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
  }

  static String _kindFor(String path) {
    if (path.endsWith('workspace.json')) return 'workspace';
    if (path.endsWith('index.json')) return 'index';
    if (path.endsWith('.csv')) return 'export';
    if (path.contains('sessions')) return 'session';
    if (path.contains('source')) return 'source';
    if (path.endsWith('class.json')) return 'class';
    return 'file';
  }

  static List<String> folderPathsFor(String path) {
    final parts = p.split(path);
    final paths = <String>[];
    var current = '';
    for (final part in parts.take(parts.length - 1)) {
      current = current.isEmpty ? part : p.join(current, part);
      paths.add(current);
    }
    return paths;
  }

  static String pathHashFor(String path) {
    final canonical = p
        .split(path)
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
