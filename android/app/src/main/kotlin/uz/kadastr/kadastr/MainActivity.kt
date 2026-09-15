package uz.kadastr.kadastr

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kadastr/downloads"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDownloads" -> {
                    result.success(try { openDownloads() } catch (e: Exception) { false })
                }
                "saveToDownloads" -> {
                    val path = call.argument<String>("path")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (path == null || fileName == null) {
                        result.error("bad_args", "path/fileName required", null)
                    } else {
                        // Katta fayl (.max 1.5 GB'gacha) nusxasini asosiy ip (thread)
                        // ustida ko'chirish ANR beradi — fon ipida bajaramiz,
                        // natijani UI ipiga qaytaramiz.
                        Thread {
                            val uri = try {
                                saveToDownloads(path, fileName, mimeType)
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread { result.success(uri) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Tizimning "Downloads" (Yuklamalar) ekranini ochadi — foydalanuvchi
    /// yuklab olgan faylni o'sha yerda ko'radi.
    private fun openDownloads(): Boolean {
        val view = android.content.Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS)
        view.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(view)
            return true
        } catch (_: Exception) {}
        // Zaxira: Fayllar ilovasini Downloads jildida ochishga urinamiz.
        return try {
            val alt = android.content.Intent(android.content.Intent.ACTION_VIEW)
            alt.setDataAndType(MediaStore.Downloads.EXTERNAL_CONTENT_URI, "resource/folder")
            alt.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(alt)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// Tugallangan faylni umumiy "Downloads/3D kadastr" (MediaStore) papkasiga
    /// nusxalaydi — Samsung "Fayllar → Yaqinda"/"Yuklamalar"da ko'rinsin.
    /// Android 10+ (API 29) uchun ruxsat kerak emas. Eski versiyalarda null
    /// qaytaradi — u yerda ilova ulashish (share) oynasiga tayanadi.
    private fun saveToDownloads(path: String, fileName: String, mimeType: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val src = java.io.File(path)
        if (!src.exists()) return null

        val resolver = contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relPath = "${Environment.DIRECTORY_DOWNLOADS}/3D kadastr/"

        // Qayta yuklashda dubl to'planmasin — avvalgi nusxani o'chiramiz.
        try {
            resolver.delete(
                collection,
                "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf(relPath, fileName),
            )
        } catch (_: Exception) {}

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relPath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: return null
        resolver.openOutputStream(uri)?.use { out ->
            src.inputStream().use { it.copyTo(out) }
        } ?: run {
            resolver.delete(uri, null, null)
            return null
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
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
