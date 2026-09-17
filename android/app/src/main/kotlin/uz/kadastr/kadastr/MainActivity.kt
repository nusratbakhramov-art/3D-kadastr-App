package uz.kadastr.kadastr

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
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
import uz.kadastr.kadastr.pano.*

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

        val panoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kadastr/pano_capture")
        panoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported", "isARCoreCaptureSupported" -> {
                    if (NativeStitcher.ensureLoaded()) resolveArCore(result) else result.success(false)
                }
                "isARKitCaptureSupported", "isViewerSupported" -> result.success(false) // Android uses the existing Flutter tour viewer.
                "isSensorProcessingSupported" -> result.success(NativeStitcher.ensureLoaded())
                "ultraWideCapability" -> {
                    val camera = try { UltraWideCamera.discover(this) } catch (e: Exception) { null }
                    val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                    result.success(mapOf("available" to (camera != null && NativeStitcher.ensureLoaded()),
                        "cameraAuthorization" to if (granted) "authorized" else "notDetermined",
                        "reason" to if (camera == null) "NO_ULTRAWIDE_CAMERA" else null))
                }
                "start" -> if (call.argument<String>("mode") == "ultrawide") {
                    if (Build.VERSION.SDK_INT < 28) result.error("UNSUPPORTED", "Ultra-wide requires Android 9", null)
                    else if (pendingPanoResult != null) result.error("BUSY", "Capture is open", null)
                    else {
                        pendingPanoResult = result
                        try {
                            startActivityForResult(Intent(this, UltraWideCaptureActivity::class.java)
                                .putExtra(PanoCaptureActivity.EXTRA_STRINGS, HashMap(call.argument<Map<String,String>>("strings") ?: emptyMap())), PANO_CAPTURE_REQUEST)
                        } catch (e: Exception) { pendingPanoResult = null; result.error("LAUNCH_FAILED", e.message, null) }
                    }
                } else startPanoCapture(call.argument("strings"), result)
                "stitch" -> {
                    val path = call.argument<String>("dir")
                    val dir = path?.let { File(it).canonicalFile }
                    val roots = listOf(File(filesDir,"pano").canonicalFile,File(cacheDir,"pano").canonicalFile)
                    if (dir == null || roots.none { dir.parentFile == it }) result.error("BAD_DIR", "Invalid capture directory", null)
                    else {
                        val width = call.argument<Int>("width")
                        val mode = call.argument<String>("mode") ?: "auto"
                        val logoAsset = call.argument<String>("logoAsset")
                        val started = PanoProcessingRunner.start {
                            try {
                                val logo = logoAsset?.let { asset ->
                                    File(dir,"nadir.png").also { out ->
                                        assets.open(io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)).use { input ->
                                            out.outputStream().use { input.copyTo(it) }
                                        }
                                    }
                                }
                                val response = PanoProcessor.stitch(dir,width,mode,logo) { p,msg ->
                                    mainHandler.post { panoChannel.invokeMethod("progress",mapOf("p" to p,"msg" to msg)) }
                                }
                                mainHandler.post { result.success(response) }
                            } catch(e:Throwable) {
                                Log.e("PanoProcessor","stitch failed",e)
                                mainHandler.post { result.error("STITCH_FAILED",e.message,null) }
                            }
                        }
                        if (!started) result.error("BUSY","Processing is running",null)
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
                data?.getStringExtra("code") ?: "CAPTURE_FAILED",
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
