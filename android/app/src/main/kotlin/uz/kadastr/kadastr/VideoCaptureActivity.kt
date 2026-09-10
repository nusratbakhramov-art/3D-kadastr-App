package uz.kadastr.kadastr

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Range
import android.util.TypedValue
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.RequiresApi
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraFilter
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.DynamicRange
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File
import kotlin.math.roundToInt

/**
 * Debug-only video recorder — CameraX orqali eng keng lens (ultra-wide bo'lsa
 * 0.5x/0.6x) va qurilma qo'llaydigan eng yuqori sifatda (UHD → FHD → HD)
 * yozadi. `VideoCaptureRecorder.swift` (iOS) ning egizagi.
 *
 * Lens tanlash: `availableCameraInfos` ichidan fokus masofasi eng qisqasi
 * (= eng keng kadr) tanlanadi — logical kameradan 1.0'dan past zoom so'rash
 * ko'p OEM'da ishlamaydi (HAL 1.0 ga qisib qo'yadi). Fizik ultra-wide alohida
 * camera id sifatida ko'rinmasa, default kameraga qaytamiz va badge halol
 * "1x" yozadi.
 *
 * Ovoz yozilmaydi (RECORD_AUDIO so'ralmaydi) — iOS bilan bir xil.
 */
class VideoCaptureActivity : ComponentActivity() {

    companion object {
        private const val TAG = "VideoCapture"

        const val EXTRA_PATH = "path"
        const val EXTRA_SIZE = "sizeBytes"
        const val EXTRA_DURATION = "durationMs"
        const val EXTRA_WIDTH = "width"
        const val EXTRA_HEIGHT = "height"
        const val EXTRA_ZOOM = "zoom"
        const val EXTRA_QUALITY = "quality"
        const val EXTRA_LENS = "lens"
        const val EXTRA_BITRATE = "bitrate"
        const val EXTRA_ERROR = "error"
        const val RESULT_FAILED = Activity.RESULT_FIRST_USER

        /**
         * Elektron stabilizatsiya (EIS). Sifatni sezilarli yaxshilaydi, LEKIN
         * kadrni ~10% qirqadi — ya'ni 0.5x ning keng ko'rish burchagidan biroz
         * yo'qotadi. Fotogrammetriya uchun xom kadr kerak bo'lsa `false` qiling.
         */
        private const val STABILIZATION = true
    }

    private lateinit var previewView: PreviewView
    private lateinit var recordButton: View
    private lateinit var recordInner: View
    private lateinit var timerLabel: TextView
    private lateinit var badgeLabel: TextView
    private lateinit var closeButton: TextView

    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var isRecording = false
    private var startedAt = 0L
    private var delivered = false

    private var zoomLabel = "1x"
    private var lensFovRatio = 1f
    private var zoomProbed = false
    private var qualityLabel = "…"
    private var lensLabel = ""
    private var videoWidth = 0
    private var videoHeight = 0
    private var videoBitrate = 0

    private val ticker = object : Runnable {
        override fun run() {
            if (!isRecording) return
            val elapsed = ((System.currentTimeMillis() - startedAt) / 1000).toInt()
            timerLabel.text = String.format("%02d:%02d", elapsed / 60, elapsed % 60)
            timerLabel.postDelayed(this, 200)
        }
    }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) startCamera() else failWith("Kameraga ruxsat berilmagan")
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildUI())
        sweepStaleClips()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        // Yozuv ketayotganda chiqib ketilsa (back tugmasi) — faylni tashlaymiz,
        // aks holda Finalize `finish()` dan keyin kelib, natija yo'qoladi.
        recording?.close()
        recording = null
        super.onDestroy()
    }

    /** Dart iste'mol qilmagan eski kliplar cache'da yig'ilib qolmasin. */
    private fun sweepStaleClips() {
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        cacheDir.listFiles { f -> f.name.startsWith("kadastr_video_") }
            ?.filter { it.lastModified() < cutoff }
            ?.forEach { it.delete() }
    }

    // MARK: - Kamera

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = try {
                providerFuture.get()
            } catch (e: Exception) {
                failWith(e.message ?: "Kamera ochilmadi")
                return@addListener
            }

            val rotation = previewView.display?.rotation ?: Surface.ROTATION_0
            val previewBuilder = Preview.Builder()
                .apply { if (STABILIZATION) setPreviewStabilizationEnabled(true) }
                .setTargetRotation(rotation)
            probeAppliedZoom(previewBuilder)
            val preview = previewBuilder
                .build()
                .also { it.setSurfaceProvider(previewView.surfaceProvider) }

            // Sifat: qurilma qo'llasa 4K, bo'lmasa 1080p, bo'lmasa 720p.
            // CODEC_CAPABILITIES — CamcorderProfile default'i standart bo'lmagan
            // camera id'lar uchun sifatlarni kam ko'rsatib yuboradi.
            val recorder = Recorder.Builder()
                .setVideoCapabilitiesSource(
                    Recorder.VIDEO_CAPABILITIES_SOURCE_CODEC_CAPABILITIES
                )
                .setQualitySelector(
                    QualitySelector.fromOrderedList(
                        listOf(Quality.UHD, Quality.FHD, Quality.HD),
                        FallbackStrategy.higherQualityOrLowerThan(Quality.FHD),
                    )
                )
                .setAspectRatio(AspectRatio.RATIO_16_9)
                .build()

            val capture = VideoCapture.Builder(recorder)
                .apply { if (STABILIZATION) setVideoStabilizationEnabled(true) }
                .setTargetFrameRate(Range(30, 30))
                .setTargetRotation(rotation)
                .build()

            val backInfos = provider.availableCameraInfos
                .filter { it.lensFacing == CameraSelector.LENS_FACING_BACK }
            val widest = widestCamera(backInfos)
            val reference = try {
                CameraSelector.DEFAULT_BACK_CAMERA.filter(backInfos).firstOrNull()
            } catch (e: Exception) {
                null
            }

            val group = UseCaseGroup.Builder()
                .addUseCase(preview)
                .addUseCase(capture)
                .apply { previewView.viewPort?.let { setViewPort(it) } }
                .build()

            // Avval eng keng fizik kamerani bog'lashga urinamiz; qurilma uni
            // video oqimi uchun bermasa — default orqa kameraga qaytamiz.
            var camera = if (widest != null && widest !== reference) {
                try {
                    provider.unbindAll()
                    provider.bindToLifecycle(this, selectorFor(widest), group)
                } catch (e: Exception) {
                    Log.w(TAG, "ultra-wide bind failed, falling back", e)
                    null
                }
            } else {
                null
            }
            if (camera == null) {
                camera = try {
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        this, CameraSelector.DEFAULT_BACK_CAMERA, group,
                    )
                } catch (e: Exception) {
                    failWith(e.message ?: "Kamera bog'lanmadi")
                    return@addListener
                }
            }

            videoCapture = capture
            lensLabel = describe(camera.cameraInfo)
            qualityLabel = try {
                val supported = Recorder
                    .getVideoCapabilities(
                        camera.cameraInfo,
                        Recorder.VIDEO_CAPABILITIES_SOURCE_CODEC_CAPABILITIES,
                    )
                    .getSupportedQualities(DynamicRange.SDR)
                when {
                    supported.contains(Quality.UHD) -> "2160p"
                    supported.contains(Quality.FHD) -> "1080p"
                    supported.contains(Quality.HD) -> "720p"
                    else -> "SD"
                }
            } catch (e: Exception) {
                "?"
            }

            applyWidestZoom(camera.cameraInfo, camera.cameraControl, reference)
            refreshBadge()
            recordButton.isEnabled = true
        }, ContextCompat.getMainExecutor(this))
    }

    /**
     * Eng past zoom'ni qo'llaydi va badge'ni FAQAT muvaffaqiyatdan keyin
     * yangilaydi. `zoomState` ni qayta o'qish yaramaydi — CameraX so'ralgan
     * qiymatni darhol LiveData'ga yozadi, ya'ni u har doim "muvaffaqiyatli"
     * ko'rinadi (haqiqatda HAL 1.0 ga qisib qo'ygan bo'lsa ham).
     */
    private fun applyWidestZoom(
        info: CameraInfo,
        control: androidx.camera.core.CameraControl,
        reference: CameraInfo?,
    ) {
        lensFovRatio = fovRatio(info, reference)
        val minRatio = info.zoomState.value?.minZoomRatio ?: 1f
        zoomLabel = formatZoom(lensFovRatio)  // fizik lensdan kelgan qism
        if (minRatio >= 1f) return

        val future = control.setZoomRatio(minRatio)
        future.addListener({
            val ok = try {
                future.get(); true
            } catch (e: Exception) {
                Log.w(TAG, "zoom $minRatio rad etildi", e); false
            }
            // Muvaffaqiyat ham kafolat emas — ko'p OEM HAL so'rovni qabul
            // qilib, 1.0 ga qisib qo'yadi. Haqiqiy qiymat capture result'dan
            // keladi (probeAppliedZoom); u kelguncha vaqtincha ko'rsatamiz.
            if (ok && !zoomProbed) {
                zoomLabel = formatZoom(lensFovRatio * minRatio)
                refreshBadge()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    /**
     * Badge'ni HAL haqiqatda qo'llagan zoom bilan yangilaydi. `zoomState` ham,
     * `setZoomRatio` future'i ham so'ralgan qiymatni tasdiqlaydi — yagona
     * ishonchli manba capture result'dagi `CONTROL_ZOOM_RATIO` (API 30+).
     */
    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun probeAppliedZoom(builder: Preview.Builder) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        Camera2Interop.Extender(builder).setSessionCaptureCallback(
            object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    session: CameraCaptureSession,
                    request: CaptureRequest,
                    result: TotalCaptureResult,
                ) {
                    if (zoomProbed) return
                    val applied = appliedZoom(result) ?: return
                    zoomProbed = true
                    Log.d(TAG, "HAL zoom = $applied")
                    runOnUiThread {
                        zoomLabel = formatZoom(lensFovRatio * applied)
                        refreshBadge()
                    }
                }
            }
        )
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun appliedZoom(result: TotalCaptureResult): Float? =
        result.get(CaptureResult.CONTROL_ZOOM_RATIO)

    /** Eng keng (fokus masofasi eng qisqa, sensorga nisbatan) orqa kamera. */
    private fun widestCamera(infos: List<CameraInfo>): CameraInfo? =
        infos.maxByOrNull { angularWidth(it) ?: -1f }

    /**
     * Ko'rish burchagi o'lchovi: sensor eni / fokus masofasi. Katta = kengroq.
     * Faqat fokus masofasini solishtirish noto'g'ri — sensor o'lchamlari har xil.
     */
    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun angularWidth(info: CameraInfo): Float? = try {
        val c2 = Camera2CameraInfo.from(info)
        val focal = c2
            .getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            ?.minOrNull()
        val sensor = c2
            .getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        if (focal != null && focal > 0f && sensor != null) sensor.width / focal else null
    } catch (e: Exception) {
        null
    }

    /** Tanlangan kameraning default kameraga nisbatan zoom koeffitsiyenti. */
    private fun fovRatio(chosen: CameraInfo, reference: CameraInfo?): Float {
        if (reference == null || reference === chosen) return 1f
        val a = angularWidth(chosen) ?: return 1f
        val b = angularWidth(reference) ?: return 1f
        return if (a > 0f) b / a else 1f
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun describe(info: CameraInfo): String = try {
        "Back camera id=${Camera2CameraInfo.from(info).getCameraId()}"
    } catch (e: Exception) {
        "Back camera"
    }

    /** Tanlangan CameraInfo'ni aynan o'zini bog'laydigan selector. */
    private fun selectorFor(target: CameraInfo): CameraSelector =
        CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .addCameraFilter(
                CameraFilter { infos ->
                    val hit = infos.filter { it === target }
                    // Hech qachon bo'sh qaytarmaslik shart.
                    (if (hit.isEmpty()) infos else hit).toMutableList()
                }
            )
            .build()

    /** 0.5 → "0.5x", 1.0 → "1x". */
    private fun formatZoom(ratio: Float): String {
        val rounded = (ratio * 10).roundToInt() / 10f
        return if (rounded == rounded.toInt().toFloat()) "${rounded.toInt()}x" else "${rounded}x"
    }

    private fun refreshBadge() {
        badgeLabel.text = "  $zoomLabel · $qualityLabel  "
    }

    // MARK: - Yozish

    private fun toggleRecording() {
        val capture = videoCapture ?: return
        if (isRecording) {
            isRecording = false
            recordButton.isEnabled = false
            setRecordingUI(false)
            recording?.stop()
            return
        }

        val file = File(cacheDir, "kadastr_video_${System.currentTimeMillis()}.mp4")
        val options = FileOutputOptions.Builder(file).build()

        // Ovozsiz — withAudioEnabled() chaqirilmaydi, RECORD_AUDIO kerak emas.
        recording = try {
            capture.output
                .prepareRecording(this, options)
                .start(ContextCompat.getMainExecutor(this)) { event ->
                    if (event !is VideoRecordEvent.Finalize) return@start
                    isRecording = false
                    if (event.hasError()) {
                        file.delete()
                        failWith("Yozib bo'lmadi (kod ${event.error})")
                        return@start
                    }
                    finishWith(file, event.recordingStats.recordedDurationNanos / 1_000_000)
                }
        } catch (e: Exception) {
            file.delete()
            failWith(e.message ?: "Yozuv boshlanmadi")
            return
        }

        isRecording = true
        startedAt = System.currentTimeMillis()
        setRecordingUI(true)
        timerLabel.post(ticker)
    }

    private fun setRecordingUI(recording: Boolean) {
        timerLabel.visibility = if (recording) View.VISIBLE else View.INVISIBLE
        recordInner.background = circle(
            Color.parseColor("#FF3B30"),
            if (recording) dp(6f) else dp(28f),
        )
        recordInner.scaleX = if (recording) 0.55f else 1f
        recordInner.scaleY = if (recording) 0.55f else 1f
    }

    // MARK: - Natija

    private fun finishWith(file: File, durationMs: Long) {
        if (delivered || isFinishing || isDestroyed) {
            file.delete()
            return
        }
        delivered = true
        // MediaMetadataRetriever — sinxron fayl parsingi, main thread'da emas.
        Thread {
            readMetadata(file)
            runOnUiThread {
                setResult(
                    Activity.RESULT_OK,
                    Intent()
                        .putExtra(EXTRA_PATH, file.absolutePath)
                        .putExtra(EXTRA_SIZE, file.length())
                        .putExtra(EXTRA_DURATION, durationMs)
                        .putExtra(EXTRA_WIDTH, videoWidth)
                        .putExtra(EXTRA_HEIGHT, videoHeight)
                        .putExtra(EXTRA_ZOOM, zoomLabel)
                        .putExtra(EXTRA_QUALITY, qualityLabel)
                        .putExtra(EXTRA_LENS, lensLabel)
                        .putExtra(EXTRA_BITRATE, videoBitrate),
                )
                finish()
            }
        }.start()
    }

    /** Yozilgan faylning haqiqiy o'lchami, aylanishi va bitrate'i. */
    private fun readMetadata(file: File) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            var w = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            var h = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val t = w; w = h; h = t
            }
            videoWidth = w
            videoHeight = h
            videoBitrate = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toIntOrNull() ?: 0
            if (w > 0 && h > 0) qualityLabel = "${minOf(w, h)}p"
        } catch (e: Exception) {
            Log.w(TAG, "metadata o'qilmadi", e)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // e'tiborsiz
            }
        }
    }

    private fun failWith(message: String) {
        if (delivered) return
        delivered = true
        setResult(RESULT_FAILED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    private fun cancel() {
        if (delivered) return
        delivered = true
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    // MARK: - UI

    private fun buildUI(): View {
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        // FIT_CENTER — preview aynan yoziladigan kadrni ko'rsatadi (FILL_CENTER
        // chetlarini qirqib, ko'rish burchagini yolg'on ko'rsatardi).
        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FIT_CENTER
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        root.addView(previewView)

        closeButton = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            background = circle(Color.argb(115, 0, 0, 0), dp(20f))
            layoutParams = FrameLayout.LayoutParams(dp(40f).toInt(), dp(40f).toInt()).apply {
                gravity = Gravity.TOP or Gravity.START
                leftMargin = dp(16f).toInt()
                topMargin = dp(28f).toInt()
            }
            setOnClickListener { if (isRecording) toggleRecording() else cancel() }
        }
        root.addView(closeButton)

        badgeLabel = TextView(this).apply {
            text = "  …  "
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            background = circle(Color.argb(115, 0, 0, 0), dp(13f))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(26f).toInt(),
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(35f).toInt()
            }
        }
        root.addView(badgeLabel)

        timerLabel = TextView(this).apply {
            text = "00:00"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            visibility = View.INVISIBLE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(122f).toInt()
            }
        }
        root.addView(timerLabel)

        recordButton = FrameLayout(this).apply {
            background = ring(Color.WHITE, dp(36f), dp(4f))
            isEnabled = false
            layoutParams = FrameLayout.LayoutParams(dp(72f).toInt(), dp(72f).toInt()).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(36f).toInt()
            }
            setOnClickListener { toggleRecording() }
        }
        recordInner = View(this).apply {
            background = circle(Color.parseColor("#FF3B30"), dp(28f))
            layoutParams = FrameLayout.LayoutParams(dp(56f).toInt(), dp(56f).toInt()).apply {
                gravity = Gravity.CENTER
            }
        }
        (recordButton as FrameLayout).addView(recordInner)
        root.addView(recordButton)

        return root
    }

    private fun circle(color: Int, radius: Float) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(color)
    }

    private fun ring(color: Int, radius: Float, width: Float) = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(Color.TRANSPARENT)
        setStroke(width.toInt(), color)
    }

    private fun dp(value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)
}
