package uz.kadastr.kadastr.pano

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.camera2.*
import android.hardware.camera2.CameraCharacteristics as C
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.*
import android.util.Log
import android.view.*
import android.widget.*
import java.io.File
import java.util.UUID
import kotlin.math.*
import org.json.JSONArray
import org.json.JSONObject

/** Camera2 physical-lens stills + Astra Android gyro poses. All capture state belongs to worker. */
@androidx.annotation.RequiresApi(28)
class UltraWideCaptureActivity :
    androidx.activity.ComponentActivity(), TextureView.SurfaceTextureListener {
    private val thread = HandlerThread("AstraCapture")
    private lateinit var worker: Handler
    private val ui = Handler(Looper.getMainLooper())
    private lateinit var motion: CaptureMotion
    private lateinit var texture: TextureView
    private lateinit var overlay: PanoOverlayView
    private lateinit var label: TextView
    private lateinit var done: Button
    private lateinit var undo: Button
    private lateinit var dir: File
    private var selection: UltraWideCamera.Selection? = null
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var surface: Surface? = null
    private val targets = PanoTargetGrid.ultraWide()
    private val metas = mutableListOf<PanoFrameMeta>()
    private val gate = CaptureGate()
    private var pending: PanoTarget? = null
    private var stillResult: CaptureResult? = null
    private var jpeg: Pair<Long, ByteArray>? = null
    private var captureToken = 0
    private var finishingCapture = false
    private var opened = false
    private var frameReady = false
    private var lastPoseNs = 0L
    private var nextFrameNs = 0L
    private var correction = CaptureRequest.DISTORTION_CORRECTION_MODE_OFF
    private var lastUiNs = 0L
    private var displayDegrees = 0
    private var strings: Map<String, String> = emptyMap()

    private fun s(key: String, fallback: String) = strings[key] ?: fallback

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        onBackPressedDispatcher.addCallback(
            this,
            object : androidx.activity.OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (::worker.isInitialized) worker.post { finishCapture(false) }
                }
            },
        )
        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        val supplied =
            intent.getSerializableExtra(PanoCaptureActivity.EXTRA_STRINGS)
                as? HashMap<String, String>
        strings = supplied ?: emptyMap()
        @Suppress("DEPRECATION") val displayRotation = windowManager.defaultDisplay.rotation
        displayDegrees = displayRotation * 90
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        dir = File(File(filesDir, "pano"), UUID.randomUUID().toString())
        if (!dir.mkdirs()) {
            fail("CAPTURE_IO")
            return
        }
        thread.start()
        worker = Handler(thread.looper)
        motion = CaptureMotion(this, worker, ::onPose) { fail("MOTION_FAILED") }
        texture = TextureView(this).also { it.surfaceTextureListener = this }
        overlay = PanoOverlayView(this)
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)
        root.addView(texture, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        label =
            TextView(this).apply {
                setTextColor(Color.WHITE)
                textSize = 18f
                gravity = Gravity.CENTER
                setBackgroundColor(0x88000000.toInt())
                text = s("uw_hint", "Nishonni markazga olib keling")
            }
        root.addView(label, FrameLayout.LayoutParams(-1, 160, Gravity.TOP))
        val buttons = LinearLayout(this).apply { gravity = Gravity.CENTER }
        fun button(text: String, action: () -> Unit) =
            Button(this).apply {
                this.text = text
                setOnClickListener { action() }
                buttons.addView(this, LinearLayout.LayoutParams(0, -2, 1f))
            }
        button(s("close", "Yopish")) { worker.post { finishCapture(false) } }
        undo = button("↶") { worker.post { undoLast() } }
        done =
            button(s("finish", "Yakunlash")) {
                worker.post {
                    if (metas.size >= 4 && pending == null)
                        ui.post {
                            AlertDialog.Builder(this)
                                .setTitle(s("finish_title", "Tushirishni yakunlash?"))
                                .setMessage(
                                    s("early_finish", "Kam kadr — sferada bo‘shliq bo‘ladi.")
                                )
                                .setPositiveButton(s("finish_yes", "Yakunlash")) { _, _ ->
                                    worker.post { finishCapture(true) }
                                }
                                .setNegativeButton(s("finish_no", "Davom etish"), null)
                                .show()
                        }
                }
            }
        done.isEnabled = false
        undo.isEnabled = false
        root.addView(buttons, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 42)
    }

    override fun onRequestPermissionsResult(
        code: Int,
        permissions: Array<String>,
        grants: IntArray,
    ) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 42) {
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                if (texture.isAvailable) startCamera()
            } else fail("CAMERA_PERMISSION")
        }
    }

    override fun onSurfaceTextureAvailable(t: SurfaceTexture, w: Int, h: Int) {
        startCamera()
    }

    override fun onSurfaceTextureSizeChanged(t: SurfaceTexture, w: Int, h: Int) {
        configurePreview()
    }

    override fun onSurfaceTextureUpdated(t: SurfaceTexture) {}

    override fun onSurfaceTextureDestroyed(t: SurfaceTexture): Boolean {
        if (::worker.isInitialized) worker.post { closeCamera() }
        return true
    }

    private fun configurePreview() {
        val selected = selection ?: return
        val rotation = selected.chars[C.SENSOR_ORIENTATION] ?: return
        val w = texture.width.toFloat()
        val h = texture.height.toFloat()
        val sw = selected.preview.width.toFloat()
        val sh = selected.preview.height.toFloat()
        // TextureView already compensates SENSOR_ORIENTATION. Undo only its aspect
        // stretch, then compensate display rotation (important on landscape-native devices).
        val naturalW = if (rotation % 180 != 0) sh else sw
        val naturalH = if (rotation % 180 != 0) sw else sh
        val outputRotation = (rotation - displayDegrees + 360) % 360
        val finalW = if (outputRotation % 180 != 0) sh else sw
        val finalH = if (outputRotation % 180 != 0) sw else sh
        val scale = max(w / finalW, h / finalH)
        val m = Matrix()
        m.setScale(naturalW / w, naturalH / h, w / 2, h / 2)
        m.postRotate(-displayDegrees.toFloat(), w / 2, h / 2)
        m.postScale(scale, scale, w / 2, h / 2)
        texture.setTransform(m)
    }

    private fun startCamera() {
        if (
            Build.VERSION.SDK_INT < 28 ||
                opened ||
                checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        )
            return
        opened = true
        worker.post {
            try {
                val chosen = UltraWideCamera.discover(this) ?: error("NO_ULTRAWIDE_CAMERA")
                selection = chosen
                require(NativeStitcher.ensureLoaded()) { "UNSUPPORTED" }
                val modes = chosen.chars[C.DISTORTION_CORRECTION_AVAILABLE_MODES] ?: intArrayOf()
                correction =
                    when {
                        modes.contains(CaptureRequest.DISTORTION_CORRECTION_MODE_HIGH_QUALITY) ->
                            CaptureRequest.DISTORTION_CORRECTION_MODE_HIGH_QUALITY
                        modes.contains(CaptureRequest.DISTORTION_CORRECTION_MODE_FAST) ->
                            CaptureRequest.DISTORTION_CORRECTION_MODE_FAST
                        else -> CaptureRequest.DISTORTION_CORRECTION_MODE_OFF
                    }
                require(
                    chosen.chars[C.LENS_DISTORTION] == null ||
                        chosen.chars[C.LENS_INTRINSIC_CALIBRATION] != null
                ) {
                    "MISSING_LENS_CALIBRATION"
                }
                require(motion.start()) { "NO_DEVICE_MOTION" }
                ui.post { configurePreview() }
                texture.surfaceTexture!!.setDefaultBufferSize(
                    chosen.preview.width,
                    chosen.preview.height,
                )
                surface = Surface(texture.surfaceTexture)
                reader =
                    ImageReader.newInstance(
                            chosen.jpeg.width,
                            chosen.jpeg.height,
                            ImageFormat.JPEG,
                            2,
                        )
                        .apply {
                            setOnImageAvailableListener(
                                { source ->
                                    source.acquireNextImage()?.use { image ->
                                        if (pending != null) {
                                            val bytes =
                                                ByteArray(image.planes[0].buffer.remaining())
                                            image.planes[0].buffer.get(bytes)
                                            jpeg = image.timestamp to bytes
                                            trySave()
                                        }
                                    }
                                },
                                worker,
                            )
                        }
                val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                manager.openCamera(
                    chosen.lens.openId,
                    object : CameraDevice.StateCallback() {
                        override fun onOpened(c: CameraDevice) {
                            if (finishingCapture) {
                                c.close()
                                return
                            }
                            camera = c
                            try {
                                createSession()
                            } catch (e: Exception) {
                                Log.e("AstraCapture", "session", e)
                                fail("CAMERA_FAILED")
                            }
                        }

                        override fun onDisconnected(c: CameraDevice) {
                            c.close()
                            fail("CAMERA_INTERRUPTED")
                        }

                        override fun onError(c: CameraDevice, error: Int) {
                            c.close()
                            fail("CAMERA_FAILED")
                        }
                    },
                    worker,
                )
            } catch (e: Exception) {
                Log.e("AstraCapture", "open", e)
                fail(
                    if (
                        e.message in setOf("NO_ULTRAWIDE_CAMERA", "UNSUPPORTED", "NO_DEVICE_MOTION")
                    )
                        e.message!!
                    else "CAMERA_FAILED"
                )
            }
        }
    }

    private fun createSession() {
        val c = camera ?: return
        val chosen = selection ?: return
        val outputs =
            listOf(surface!!, reader!!.surface).map {
                OutputConfiguration(it).apply {
                    chosen.lens.physicalId?.let { id -> setPhysicalCameraId(id) }
                }
            }
        c.createCaptureSession(
            SessionConfiguration(
                SessionConfiguration.SESSION_REGULAR,
                outputs,
                { r -> worker.post(r) },
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        if (finishingCapture) {
                            s.close()
                            return
                        }
                        session = s
                        try {
                            val request =
                                c.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                    addTarget(surface!!)
                                    configure(this)
                                }
                            s.setRepeatingRequest(
                                request.build(),
                                object : CameraCaptureSession.CaptureCallback() {
                                    override fun onCaptureCompleted(
                                        session: CameraCaptureSession,
                                        request: CaptureRequest,
                                        result: TotalCaptureResult,
                                    ) {
                                        frameReady = true
                                    }
                                },
                                worker,
                            )
                        } catch (e: Exception) {
                            fail("CAMERA_FAILED")
                        }
                    }

                    override fun onConfigureFailed(s: CameraCaptureSession) {
                        fail("CAMERA_FAILED")
                    }
                },
            )
        )
    }

    private fun configure(b: CaptureRequest.Builder) {
        b.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
        b.set(
            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF,
        )
        b.set(
            CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
            CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_OFF,
        )
        if (selection!!.chars[C.DISTORTION_CORRECTION_AVAILABLE_MODES] != null)
            b.set(CaptureRequest.DISTORTION_CORRECTION_MODE, correction)
        if (
            Build.VERSION.SDK_INT >= 31 &&
                selection!!
                    .chars[C.SCALER_AVAILABLE_ROTATE_AND_CROP_MODES]
                    ?.contains(CaptureRequest.SCALER_ROTATE_AND_CROP_NONE) == true
        )
            b.set(CaptureRequest.SCALER_ROTATE_AND_CROP, CaptureRequest.SCALER_ROTATE_AND_CROP_NONE)
        b.set(
            CaptureRequest.JPEG_ORIENTATION,
            0,
        ) // Always raw sensor axes; physically rotate once ourselves.
        b.set(CaptureRequest.JPEG_QUALITY, 95.toByte())
        val active =
            selection!!
                .chars[
                    if (correction == CaptureRequest.DISTORTION_CORRECTION_MODE_OFF)
                        C.SENSOR_INFO_PRE_CORRECTION_ACTIVE_ARRAY_SIZE
                    else C.SENSOR_INFO_ACTIVE_ARRAY_SIZE]
                ?: selection!!.chars[C.SENSOR_INFO_ACTIVE_ARRAY_SIZE]!!
        b.set(CaptureRequest.SCALER_CROP_REGION, active)
        val af = selection!!.chars[C.CONTROL_AF_AVAILABLE_MODES] ?: intArrayOf()
        if (af.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE))
            b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
    }

    private fun onPose(ns: Long, deviceRotation: FloatArray, speed: Float) {
        val orientation = selection?.chars?.get(C.SENSOR_ORIENTATION) ?: 0
        val r =
            poseForSavedImage(
                deviceRotation,
                orientation,
                (orientation - displayDegrees + 360) % 360,
            )
        lastPoseNs = ns
        if (finishingCapture || !frameReady || pending != null) return
        val remaining = targets.filter { t -> metas.none { it.targetId == t.id } }
        val forward = PoseMath.forward(r)
        val near =
            remaining.minByOrNull {
                PoseMath.angleBetween(forward, floatArrayOf(it.dirX, it.dirY, it.dirZ))
            } ?: return
        val angle = PoseMath.angleBetween(forward, floatArrayOf(near.dirX, near.dirY, near.dirZ))
        val dwell =
            if (ns < nextFrameNs) 0f
            else
                gate.progress(near.id, ns, SystemClock.elapsedRealtimeNanos() - ns, angle, speed, r)
        if (ns - lastUiNs > 40_000_000L) {
            lastUiNs = ns
            val count = metas.size
            val positions =
                targets.map { t ->
                    val v = PoseMath.worldToCamera(r, floatArrayOf(t.dirX, t.dirY, t.dirZ))
                    // HUD projection uses selected physical sensor FOV and the same aspect crop as
                    // preview.
                    val selected = selection!!
                    val phys = selected.chars[C.SENSOR_INFO_PHYSICAL_SIZE]!!
                    val sensorRotation =
                        (selected.chars[C.SENSOR_ORIENTATION]!! - displayDegrees + 360) % 360
                    val physicalW = if (sensorRotation % 180 == 0) phys.width else phys.height
                    val physicalH = if (sensorRotation % 180 == 0) phys.height else phys.width
                    val focal =
                        max(texture.width / physicalW, texture.height / physicalH) *
                            selected.lens.focalMm
                    PanoOverlayView.Dot(
                        texture.width / 2f + focal * v[0] / -v[2],
                        texture.height / 2f - focal * v[1] / -v[2],
                        v[2] < -.05f,
                        metas.any { it.targetId == t.id },
                        false,
                    )
                }
            ui.post {
                overlay.submit(positions, dwell, angle <= CaptureGate.AIM)
                label.text =
                    "$count / 17\n" +
                        if (!CaptureGate.level(r)) s("uw_level", "Telefonni tekis tuting")
                        else s("uw_hint", "Nishonni markazga olib keling")
                done.isEnabled = count >= 4
                undo.isEnabled = count > 0
            }
        }
        if (dwell >= 1f) shoot(near)
    }

    private fun shoot(target: PanoTarget) {
        val c = camera ?: return
        val s = session ?: return
        pending = target
        gate.reset()
        jpeg = null
        stillResult = null
        val token = ++captureToken
        ui.post {
            done.isEnabled = false
            undo.isEnabled = false
        }
        try {
            val request =
                c.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                    .apply {
                        addTarget(reader!!.surface)
                        configure(this)
                    }
                    .build()
            s.capture(
                request,
                object : CameraCaptureSession.CaptureCallback() {
                    override fun onCaptureCompleted(
                        session: CameraCaptureSession,
                        request: CaptureRequest,
                        result: TotalCaptureResult,
                    ) {
                        if (token != captureToken) return
                        stillResult =
                            selection!!.lens.physicalId?.let { result.physicalCameraResults[it] }
                                ?: if (selection!!.lens.physicalId == null) result else null
                        trySave()
                    }

                    override fun onCaptureFailed(
                        session: CameraCaptureSession,
                        request: CaptureRequest,
                        failure: CaptureFailure,
                    ) {
                        if (token != captureToken) return
                        reject("capture failed")
                    }
                },
                worker,
            )
            worker.postDelayed(
                {
                    if (token == captureToken && pending != null)
                        reject("exposure metadata timeout")
                },
                4000,
            )
        } catch (e: Exception) {
            reject(e.message ?: "capture failed")
        }
    }

    private fun trySave() {
        val target = pending ?: return
        val result = stillResult ?: return
        val image = jpeg ?: return
        val start = result[CaptureResult.SENSOR_TIMESTAMP] ?: return
        val exposure = result[CaptureResult.SENSOR_EXPOSURE_TIME] ?: return
        if (image.first != start) {
            reject("JPEG/result timestamp mismatch")
            return
        }
        val skew = result[CaptureResult.SENSOR_ROLLING_SHUTTER_SKEW] ?: 0L
        if (skew !in 0..100_000_000L) {
            reject("invalid rolling shutter interval")
            return
        }
        val interval = exposure + skew
        val instant =
            ExposureClock.midpoint(start, interval, selection!!.lens.realtime)
                ?: run {
                    reject("unknown exposure clock")
                    return
                }
        if (
            lastPoseNs < start + interval &&
                SystemClock.elapsedRealtimeNanos() - start < 1_000_000_000L
        ) {
            worker.postDelayed({ trySave() }, 20)
            return
        }
        val deviceRotation =
            motion.history.exposure(start, interval)
                ?: run {
                    reject("unsafe exposure pose")
                    return
                }
        val sensorOrientation = selection!!.chars[C.SENSOR_ORIENTATION]!!
        val pixelRotation = (sensorOrientation - displayDegrees + 360) % 360
        val rotation = poseForSavedImage(deviceRotation, sensorOrientation, pixelRotation)
        if (
            !CaptureGate.level(rotation) ||
                PoseMath.angleBetween(
                    PoseMath.forward(rotation),
                    floatArrayOf(target.dirX, target.dirY, target.dirZ),
                ) > CaptureGate.AIM
        ) {
            reject("moved during exposure")
            return
        }
        try {
            val chosen = selection!!
            val chars = chosen.chars
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(image.second, 0, image.second.size, bounds)
            require(
                bounds.outWidth == chosen.jpeg.width && bounds.outHeight == chosen.jpeg.height
            ) {
                "HAL rotated JPEG despite JPEG_ORIENTATION=0"
            }
            val active = chars[C.SENSOR_INFO_ACTIVE_ARRAY_SIZE]!!
            val crop = result[CaptureResult.SCALER_CROP_REGION] ?: error("missing result crop")
            val pixel = chars[C.SENSOR_INFO_PIXEL_ARRAY_SIZE]!!
            val calibration =
                result[CaptureResult.LENS_INTRINSIC_CALIBRATION]
                    ?: chars[C.LENS_INTRINSIC_CALIBRATION]
            val k =
                if (calibration != null && calibration.size >= 5 && abs(calibration[4]) < 1e-3f) {
                    CaptureIntrinsics(
                        calibration[0],
                        calibration[1],
                        calibration[2] +
                            (chars[C.SENSOR_INFO_PRE_CORRECTION_ACTIVE_ARRAY_SIZE]?.left ?: 0),
                        calibration[3] +
                            (chars[C.SENSOR_INFO_PRE_CORRECTION_ACTIVE_ARRAY_SIZE]?.top ?: 0),
                        pixel.width,
                        pixel.height,
                        "lensCalibration",
                    )
                } else {
                    val physical = chars[C.SENSOR_INFO_PHYSICAL_SIZE]!!
                    CaptureIntrinsics.physical(
                        result[CaptureResult.LENS_FOCAL_LENGTH] ?: chosen.lens.focalMm,
                        physical.width,
                        physical.height,
                        pixel.width,
                        pixel.height,
                    )
                }
            val sensorK =
                k.cropped(
                    crop.left.toFloat(),
                    crop.top.toFloat(),
                    crop.width().toFloat(),
                    crop.height().toFloat(),
                    bounds.outWidth,
                    bounds.outHeight,
                )
            val saved = sensorK.rotated(pixelRotation)
            val actualCorrection =
                result[CaptureResult.DISTORTION_CORRECTION_MODE]
                    ?: CaptureRequest.DISTORTION_CORRECTION_MODE_OFF
            val distortion =
                if (actualCorrection == CaptureRequest.DISTORTION_CORRECTION_MODE_OFF)
                    (result[CaptureResult.LENS_DISTORTION]
                        ?: chars[C.LENS_DISTORTION]
                        ?: floatArrayOf())
                else floatArrayOf()
            require(distortion.isEmpty() || calibration != null) {
                "Missing distortion calibration"
            }
            val index = metas.size
            val raw = File(dir, "pending.jpg")
            raw.outputStream().use {
                it.write(image.second)
                it.fd.sync()
            }
            val name = "frame_${index}.jpg"
            val photo = File(dir, name)
            require(
                NativeStitcher.rotateJpegFile(
                    raw,
                    photo,
                    pixelRotation,
                    intrinsics = sensorK.array(),
                    distortion = distortion,
                )
            ) {
                "JPEG rotation failed"
            }
            raw.delete()
            val meta =
                PanoFrameMeta(
                    index,
                    target.id,
                    target.yaw,
                    target.pitch,
                    PoseMath.toColumnMajor16(rotation),
                    saved.array(),
                    saved.width,
                    saved.height,
                    saved.width,
                    saved.height,
                    instant * 1e-9,
                    true,
                    name,
                    "sensors:android",
                    exposure * 1e-9,
                    JSONObject()
                        .put("cameraId", chosen.lens.openId)
                        .put("physicalCameraId", chosen.lens.physicalId)
                        .put("rollingShutterSkewNs", skew)
                        .put("sensorTimestampNs", start)
                        .put("poseInstantNs", instant)
                        .put("poseTimestampSource", "realtime:frameExposureMidpoint")
                        .put("intrinsicsSource", saved.source)
                        .put("sensorOrientation", sensorOrientation)
                        .put("pixelRotation", pixelRotation)
                        .put(
                            "distortionCorrection",
                            result[CaptureResult.DISTORTION_CORRECTION_MODE],
                        )
                        .put("softwareUndistortion", distortion.isNotEmpty())
                        .put(
                            "cropRegion",
                            JSONArray(listOf(crop.left, crop.top, crop.right, crop.bottom)),
                        )
                        .put("activeArray", active.toShortString()),
                )
            PanoStorage.writeMetadata(dir, metas + meta)
            metas.add(meta)
            Log.i(
                "AstraCapture",
                "saved target=${target.id} index=$index camera=${chosen.lens} K=$saved timestamp=$instant exposure=$exposure",
            )
            pending = null
            jpeg = null
            stillResult = null
            nextFrameNs = SystemClock.elapsedRealtimeNanos() + 400_000_000L
            if (metas.size == 17) finishCapture(true)
        } catch (e: Exception) {
            Log.e("AstraCapture", "save failed", e)
            reject(e.message ?: "save failed")
        }
    }

    private fun reject(reason: String) {
        Log.w("AstraCapture", "rejected: $reason")
        pending = null
        stillResult = null
        jpeg = null
        captureToken++
        gate.reset()
        nextFrameNs = SystemClock.elapsedRealtimeNanos() + 1_000_000_000L
        ui.post {
            label.text = s("uw_retry", "Qayta urinib ko‘ring")
            done.isEnabled = metas.size >= 4
            undo.isEnabled = metas.isNotEmpty()
        }
    }

    private fun undoLast() {
        if (pending != null || metas.isEmpty()) return
        try {
            val last = metas.last()
            PanoStorage.writeMetadata(dir, metas.dropLast(1))
            metas.removeAt(metas.lastIndex)
            File(dir, last.file).delete()
            gate.reset()
        } catch (e: Exception) {
            fail("CAPTURE_IO")
        }
    }

    private fun closeCamera() {
        session?.close()
        session = null
        camera?.close()
        camera = null
        reader?.setOnImageAvailableListener(null, null)
        reader?.close()
        reader = null
        surface?.release()
        surface = null
        if (::motion.isInitialized) motion.stop()
    }

    private fun finishCapture(accept: Boolean) {
        if (finishingCapture) return
        finishingCapture = true
        closeCamera()
        val count = metas.size
        if (!accept) dir.deleteRecursively()
        ui.post {
            if (accept && count >= 4)
                setResult(
                    RESULT_OK,
                    Intent()
                        .putExtra(PanoCaptureActivity.EXTRA_DIR, dir.absolutePath)
                        .putExtra(PanoCaptureActivity.EXTRA_FRAMES, count),
                )
            else setResult(RESULT_CANCELED)
            finish()
        }
    }

    private fun fail(code: String) {
        if (finishingCapture) return
        val resultCode = if (!frameReady && code == "CAMERA_FAILED") "NO_ULTRAWIDE_CAMERA" else code
        finishingCapture = true
        if (::worker.isInitialized) worker.post { closeCamera() }
        ui.post {
            setResult(
                PanoCaptureActivity.RESULT_FAILED,
                Intent().putExtra(PanoCaptureActivity.EXTRA_ERROR, resultCode).putExtra("code", resultCode),
            )
            finish()
        }
    }

    override fun onStop() {
        super.onStop()
        if (::worker.isInitialized)
            worker.post {
                if (!finishingCapture) {
                    if (metas.size >= 4) finishCapture(true) else fail("CAPTURE_INTERRUPTED")
                }
            }
    }

    override fun onDestroy() {
        if (::worker.isInitialized)
            worker.post {
                closeCamera()
                thread.quitSafely()
            }
        super.onDestroy()
    }
}
