package vn.edu.fpt.fap_attendance

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "vn.edu.fpt.fap_attendance/meet",
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.arguments as? String
            val uri = url?.let { Uri.parse(it) }
            if (uri == null || uri.scheme != "https" || uri.host != "meet.google.com") {
                result.error("INVALID_MEET_URL", "Expected a Google Meet URL.", null)
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri))
                result.success(null)
            } catch (_: ActivityNotFoundException) {
                result.error("NO_URL_HANDLER", "No app can open this URL.", null)
            }
        }
    }
}
