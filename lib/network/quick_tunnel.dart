import 'dart:async';
import 'dart:convert';
import 'dart:io';

class QuickTunnel {
  Process? _process;
  String? _url;

  String? get url => _url;

  Future<String> start(String localOrigin) async {
    if (_url != null) return _url!;
    final process = await Process.start(
      _executable(),
      ['tunnel', '--url', localOrigin],
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    _process = process;
    final ready = Completer<String>();
    final pattern = RegExp(r'https://[a-z0-9-]+\.trycloudflare\.com');
    String? discoveredUrl;
    var connected = false;
    void inspect(String line) {
      final found = pattern.firstMatch(line)?.group(0);
      if (found != null) discoveredUrl = found;
      if (line.contains('Registered tunnel connection')) connected = true;
      if (connected && discoveredUrl != null && !ready.isCompleted) {
        _url = discoveredUrl;
        ready.complete(discoveredUrl!);
      }
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(inspect);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(inspect);
    unawaited(
      process.exitCode.then((code) {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('Tunnel đã dừng trước khi cấp URL (mã $code).'),
          );
        }
        if (identical(_process, process)) {
          _process = null;
          _url = null;
        }
      }),
    );
    try {
      return await ready.future.timeout(const Duration(seconds: 50));
    } on Object {
      process.kill();
      if (identical(_process, process)) _process = null;
      _url = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _url = null;
    process?.kill();
  }

  static String _executable() {
    if (!Platform.isWindows) return 'cloudflared';
    final candidates = [
      if (Platform.environment['LOCALAPPDATA'] != null)
        '${Platform.environment['LOCALAPPDATA']}\\FAP Attendance Tools\\cloudflared.exe',
      r'C:\Program Files\cloudflared\cloudflared.exe',
      r'C:\Program Files (x86)\cloudflared\cloudflared.exe',
      r'C:\Program Files\Cloudflare\cloudflared.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'cloudflared';
  }
}
