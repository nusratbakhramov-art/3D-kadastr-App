package uz.kadastr.kadastr

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import uz.kadastr.kadastr.pano.PanoCaptureActivity

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val VIDEO_CAPTURE_REQUEST = 9301
        private const val SYSTEM_VIDEO_REQUEST = 9302
        private const val CAMERA_PERMISSION_REQUEST = 9303
        private const val PANO_CAPTURE_REQUEST = 9304
    }

    /** `record` / `recordSystem` chaqirig'i — natija kelguncha saqlanadi. */
    private var pendingVideoResult: MethodChannel.Result? = null

    /** `kadastr/pano_capture` → `start` — nativ ekran yopilguncha saqlanadi. */
    private var pendingPanoResult: MethodChannel.Result? = null

    /** Oxirgi ANIQ javob; `null` — hali hisoblanmagan. */
    private var arCoreSupported: Boolean? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var systemVideoFile: File? = null

    /// Ruxsat berilgach bajariladigan ish (kamera ochish).
    private var pendingCameraAction: (() -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ARCore tekshiruvi ASINXRON: shu yerda bir marta turtib qo'yamiz,
        // toki Dart «Tavsif» qadamiga yetganda javob allaqachon tayyor bo'lsin.
        try {
            arCoreSupported = ArCoreApk.getInstance().checkAvailability(this)
                .takeIf { it != ArCoreApk.Availability.UNKNOWN_CHECKING }
                ?.isSupported
        } catch (e: Exception) {
            Log.w(TAG, "ARCore tekshiruvi boshlanmadi", e)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kadastr/scan_capability"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probe())
                else -> result.notImplemented()
            }
        }

        // Debug-only video capture — o'z recorder'imiz (eng keng lens + max
        // sifat) yoki qurilmaning o'z kamera ilovasi. iOS'dagi
        // `kadastr/video_capture` kanalining egizagi.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kadastr/video_capture"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(
                    packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
                )

                "record" -> launch(result) {
                    startActivityForResult(
                        Intent(this, VideoCaptureActivity::class.java),
                        VIDEO_CAPTURE_REQUEST,
                    )
                }

                "recordSystem" -> launch(result) {
                    withCameraPermission { startSystemCamera() }
                }

                else -> result.notImplemented()
            }
        }

        // 360° panorama capture — iOS'dagi `kadastr/pano_capture` kanalining
        // egizagi (`ios/Runner/AppDelegate.swift`). Nativ taraf faqat KADR
        // YIG'ADI; tikish serverda.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kadastr/pano_capture"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> resolveArCore(result)
                "start" -> startPanoCapture(call.argument("strings"), result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Qurilma ARCore'ni qo'llaydimi — javob Dart'ga ASINXRON qaytadi.
     *
     * `SUPPORTED_NOT_INSTALLED` va `SUPPORTED_APK_TOO_OLD` ham `true`:
     * qurilma qobiliyatli, faqat «Google Play Services for AR» yangilanishi
     * kerak — buni `PanoCaptureActivity` ochilganda ARCore'ning O'ZI so'raydi.
     *
     * ⚠️ `checkAvailability` birinchi chaqiruvda `UNKNOWN_CHECKING` qaytarib,
     * javobni FONDA hisoblaydi. Shu holatda `false` qaytarish 360 qatorini
     * qo'llaydigan qurilmada ham yashirib qo'yardi (va u faqat keyingi
     * kirishda paydo bo'lardi). Shuning uchun javob tayyor bo'lguncha
     * ~1 sekundgacha qayta so'raladi — UI oqimini BLOKLAMASDAN,
     * `Handler.postDelayed` bilan.
     */
    private fun resolveArCore(result: MethodChannel.Result, tries: Int = 0) {
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(this)
        } catch (e: Exception) {
            Log.w(TAG, "ARCore holati aniqlanmadi", e)
            null
        }
        when {
            availability == null -> result.success(false)

            availability == ArCoreApk.Availability.UNKNOWN_CHECKING && tries < 10 ->
                mainHandler.postDelayed({ resolveArCore(result, tries + 1) }, 100)

            else -> {
                arCoreSupported = availability.isSupported
                result.success(availability.isSupported)
            }
        }
    }

    private fun startPanoCapture(
        strings: Map<String, String>?,
        result: MethodChannel.Result,
    ) {
        if (pendingPanoResult != null) {
            result.error("BUSY", "Suratga olish allaqachon ochiq", null)
            return
        }
        // ⚠️ FAQAT qurilma aniq qo'llamasa rad etamiz. `UNKNOWN_*` holatlarida
        // ekran ochiladi: ARCore o'rnatish/yangilashni O'ZI so'raydi va
        // muvaffaqiyatsiz bo'lsa tushunarli xato qaytaradi. Bu yerda
        // ehtiyotkorlik qilib rad etsak, ARCore'ni endi o'rnatgan
        // foydalanuvchi 360 ga umuman kira olmasdi.
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(this)
        } catch (e: Exception) {
            null
        }
        if (availability == ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE) {
            result.error("UNSUPPORTED", "Qurilma ARCore'ni qoʻllamaydi", null)
            return
        }
        pendingPanoResult = result
        try {
            startActivityForResult(
                Intent(this, PanoCaptureActivity::class.java).putExtra(
                    PanoCaptureActivity.EXTRA_STRINGS,
                    HashMap(strings ?: emptyMap()),
                ),
                PANO_CAPTURE_REQUEST,
            )
        } catch (e: Exception) {
            pendingPanoResult = null
            result.error("LAUNCH_FAILED", e.message ?: "Ekran ochilmadi", null)
        }
    }

    private fun handlePanoResult(resultCode: Int, data: Intent?) {
        val pending = pendingPanoResult ?: return
        pendingPanoResult = null
        when (resultCode) {
            RESULT_OK -> pending.success(
                mapOf(
                    "dir" to data?.getStringExtra(PanoCaptureActivity.EXTRA_DIR),
                    "frames" to (data?.getIntExtra(PanoCaptureActivity.EXTRA_FRAMES, 0) ?: 0),
                )
            )

            PanoCaptureActivity.RESULT_FAILED -> pending.error(
                "CAPTURE_FAILED",
                data?.getStringExtra(PanoCaptureActivity.EXTRA_ERROR) ?: "Suratga olinmadi",
                null,
            )

            // RESULT_CANCELED — foydalanuvchi bekor qildi.
            else -> pending.success(null)
        }
    }

    /** Bitta vaqtda bitta yozuv; xato bo'lsa pending qulflanib qolmaydi. */
    private fun launch(result: MethodChannel.Result, block: () -> Unit) {
        if (pendingVideoResult != null) {
            result.error("ALREADY_RECORDING", "Oldingi video yozuv hali tugamagan", null)
            return
        }
        pendingVideoResult = result
        try {
            block()
        } catch (e: ActivityNotFoundException) {
            pendingVideoResult = null
            systemVideoFile?.delete()
            systemVideoFile = null
            result.error("NO_CAMERA_APP", "Qurilmada kamera ilovasi topilmadi", null)
        } catch (e: Exception) {
            pendingVideoResult = null
            systemVideoFile?.delete()
            systemVideoFile = null
            result.error("LAUNCH_FAILED", e.message ?: "Kamera ochilmadi", null)
        }
    }

    /**
     * Kamera ruxsatini ta'minlaydi, so'ng [action] ni bajaradi.
     *
     * Manifestda `CAMERA` e'lon qilingani uchun Android tizim kamerasini
     * `ACTION_VIDEO_CAPTURE` intenti bilan ochishga ham ruxsat talab qiladi —
     * aks holda "Permission Denial ... with revoked permission" bilan
     * yiqiladi. Ilova kamerani o'zi ishlatmasa ham shu qoida amal qiladi.
     */
    private fun withCameraPermission(action: () -> Unit) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            action()
            return
        }
        pendingCameraAction = action
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            val action = pendingCameraAction
            pendingCameraAction = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && action != null) {
                action()
            } else {
                val pending = pendingVideoResult
                pendingVideoResult = null
                pending?.error("PERMISSION", "Kameraga ruxsat berilmagan", null)
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    /**
     * Qurilmaning O'Z kamera ilovasini ochadi (`ACTION_VIDEO_CAPTURE`) — OEM
     * ishlov berish quvuri, 4K/HDR/stabilizatsiya, hammasi o'zining sifatida.
     *
     * Cheklov: platformada rezolutsiya/bitrate/lens uchun extra YO'Q.
     * `EXTRA_VIDEO_QUALITY` (0|1) yagona sifat bayrog'i va u ham maslahat
     * xarakterida — 0.5x ni majburlab bo'lmaydi, uni foydalanuvchi kamera
     * ilovasining o'zida bosadi.
     */
    private fun startSystemCamera() {
        val dir = File(cacheDir, "video").apply { mkdirs() }
        val file = File(dir, "kadastr_system_${System.currentTimeMillis()}.mp4")
        systemVideoFile = file
        val uri = FileProvider.getUriForFile(
            this, "$packageName.videocapture.fileprovider", file,
        )

        val intent = Intent(MediaStore.ACTION_VIDEO_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1) // 1 = high
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            clipData = ClipData.newRawUri("", uri)
        }
        // Bayroqlarning o'zi ba'zi OEM kamera ilovalarida yetmaydi — aniq grant.
        packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .forEach {
                grantUriPermission(
                    it.activityInfo.packageName, uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }

        startActivityForResult(intent, SYSTEM_VIDEO_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            VIDEO_CAPTURE_REQUEST -> handleRecorderResult(resultCode, data)
            SYSTEM_VIDEO_REQUEST -> handleSystemResult(resultCode, data)
            PANO_CAPTURE_REQUEST -> handlePanoResult(resultCode, data)
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handleRecorderResult(resultCode: Int, data: Intent?) {
        val pending = pendingVideoResult ?: return
        pendingVideoResult = null
        when {
            resultCode == RESULT_OK && data != null -> pending.success(
                mapOf(
                    "path" to data.getStringExtra(VideoCaptureActivity.EXTRA_PATH),
                    "sizeBytes" to data.getLongExtra(VideoCaptureActivity.EXTRA_SIZE, 0),
                    "durationMs" to data.getLongExtra(VideoCaptureActivity.EXTRA_DURATION, 0),
                    "width" to data.getIntExtra(VideoCaptureActivity.EXTRA_WIDTH, 0),
                    "height" to data.getIntExtra(VideoCaptureActivity.EXTRA_HEIGHT, 0),
                    "zoom" to data.getStringExtra(VideoCaptureActivity.EXTRA_ZOOM),
                    "quality" to data.getStringExtra(VideoCaptureActivity.EXTRA_QUALITY),
                    "lens" to data.getStringExtra(VideoCaptureActivity.EXTRA_LENS),
                    "bitrate" to data.getIntExtra(VideoCaptureActivity.EXTRA_BITRATE, 0),
                )
            )

            resultCode == VideoCaptureActivity.RESULT_FAILED -> pending.error(
                "RECORD_FAILED",
                data?.getStringExtra(VideoCaptureActivity.EXTRA_ERROR)
                    ?: "Video yozib bo'lmadi",
                null,
            )

            // RESULT_CANCELED — foydalanuvchi bekor qildi.
            else -> pending.success(null)
        }
    }

    private fun handleSystemResult(resultCode: Int, data: Intent?) {
        val pending = pendingVideoResult ?: return
        pendingVideoResult = null
        val file = systemVideoFile
        systemVideoFile = null

        if (resultCode != RESULT_OK || file == null) {
            file?.delete()
            pending.success(null) // bekor qilindi
            return
        }

        // Ba'zi OEM kamera ilovalari EXTRA_OUTPUT ni e'tiborsiz qoldirib,
        // o'z content:// URI'sini qaytaradi — uni ko'chirib olamiz.
        Thread {
            try {
                if (file.length() == 0L) {
                    val src: Uri? = data?.data
                    if (src != null) {
                        contentResolver.openInputStream(src)?.use { input ->
                            file.outputStream().use { input.copyTo(it) }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "system video ko'chirilmadi", e)
            }

            val meta = readMetadata(file)
            runOnUiThread {
                if (file.length() == 0L) {
                    file.delete()
                    pending.error("EMPTY", "Kamera ilovasi video qaytarmadi", null)
                } else {
                    pending.success(meta + mapOf("path" to file.absolutePath))
                }
            }
        }.start()
    }

    private fun readMetadata(file: File): Map<String, Any?> {
        var width = 0
        var height = 0
        var duration = 0L
        var bitrate = 0
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val t = width; width = height; height = t
            }
            duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            bitrate = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            Log.w(TAG, "metadata o'qilmadi", e)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // e'tiborsiz
            }
        }
        return mapOf(
            "sizeBytes" to file.length(),
            "durationMs" to duration,
            "width" to width,
            "height" to height,
            "zoom" to "system",
            "quality" to if (width > 0 && height > 0) "${minOf(width, height)}p" else "?",
            "lens" to "Qurilma kamera ilovasi",
            "bitrate" to bitrate,
        )
    }

    override fun onDestroy() {
        // Process o'lsa Dart Future'i abadiy osilib qolmasin.
        pendingVideoResult?.error("CANCELLED", "Ekran yopildi", null)
        pendingVideoResult = null
        pendingPanoResult?.error("CANCELLED", "Ekran yopildi", null)
        pendingPanoResult = null
        super.onDestroy()
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
        "hasArCore" to (arCoreSupported ?: false),
        "hasDepthApi" to false,
        "arWorldTrackingSupported" to false,
        "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
        "osVersion" to Build.VERSION.RELEASE,
    )
}
