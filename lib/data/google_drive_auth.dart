import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GoogleDriveAuth {
  GoogleDriveAuth({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _credentialKey = 'google_drive_credentials';
  final FlutterSecureStorage _storage;

  Future<AutoRefreshingAuthClient?> restore({
    required String clientId,
    required String clientSecret,
  }) async {
    final value = await _storage.read(key: _credentialKey);
    if (value == null) return null;
    final credentials = AccessCredentials.fromJson(
      (jsonDecode(value) as Map).cast<String, dynamic>(),
    );
    if (credentials.refreshToken == null) return null;
    return autoRefreshingClient(
      ClientId(clientId, clientSecret),
      credentials,
      http.Client(),
    );
  }

  Future<AutoRefreshingAuthClient> signIn({
    required String clientId,
    required String clientSecret,
  }) async {
    final client = await clientViaUserConsent(
      ClientId(clientId, clientSecret),
      const [drive.DriveApi.driveFileScope],
      (url) => Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        url,
      ], mode: ProcessStartMode.detached),
    );
    await _storage.write(
      key: _credentialKey,
      value: jsonEncode(client.credentials.toJson()),
    );
    return client;
  }

  Future<void> signOut() => _storage.delete(key: _credentialKey);
}
