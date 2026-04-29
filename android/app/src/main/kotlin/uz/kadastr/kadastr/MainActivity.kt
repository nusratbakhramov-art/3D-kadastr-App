package uz.kadastr.kadastr

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kadastr/scan_capability"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probe())
                else -> result.notImplemented()
            }
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // Opt into the display's highest refresh rate on OEMs (Samsung OneUI etc.)
        // that otherwise clamp Flutter apps to 60Hz.
        val layoutParams = window.attributes
        layoutParams.preferredRefreshRate = 120f
        window.attributes = layoutParams
    }

    private fun probe(): Map<String, Any> = mapOf(
        "platform" to "android",
        "hasLidar" to false,
        "hasRoomPlan" to false,
        "hasArCore" to false,
        "hasDepthApi" to false,
        "arWorldTrackingSupported" to false,
        "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
        "osVersion" to Build.VERSION.RELEASE,
    )
}
