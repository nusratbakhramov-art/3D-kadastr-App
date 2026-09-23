package uz.kadastr.kadastr.pano

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.hardware.camera2.params.*
import android.media.ImageReader
import android.os.*
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** On-device tests use real HAL streams/sensors. Synthetic processing is explicitly labelled. */
@Suppress("DEPRECATION")
@RunWith(AndroidJUnit4::class)
class PanoDeviceTest {
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    @Test
    fun testNativeSensorFallbackAndOutputs() {
        val context = instrumentation.targetContext
        assertTrue(NativeStitcher.ensureLoaded())
        val dir = File(context.cacheDir, "astra-native-test").apply { mkdirs() }
        try {
            val frames =
                List(4) { i ->
                    val file = File(dir, "frame_$i.jpg")
                    val bitmap = Bitmap.createBitmap(320, 240, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.rgb(160, 160, 160))
                    file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                    bitmap.recycle()
                    val r = PoseMath.rotationY(Math.toRadians(i * 15.0).toFloat())
                    PanoFrameMeta(
                        i,
                        i,
                        0f,
                        0f,
                        PoseMath.toColumnMajor16(r),
                        floatArrayOf(150f, 150f, 159.5f, 119.5f),
                        320,
                        240,
                        320,
                        240,
                        i.toDouble(),
                        true,
                        file.name,
                        "sensors:android",
                    )
                }
            PanoStorage.writeMetadata(dir, frames)
            val output = PanoProcessor.stitch(dir, 1024, "mvs", null) { _, _ -> }
            assertEquals(1024, output["width"])
            assertEquals(512, output["height"])
            val report = File(dir, "processing.json").readText()
            Log.i("AstraDeviceTest", "synthetic weak-input $report")
            assertTrue(report.contains("rotation-fallback"))
            val truncated = File(dir, "truncated.jpg")
            val bytes = File(dir, "pano.jpg").readBytes()
            truncated.writeBytes(bytes.copyOf(bytes.size / 2))
            var rejected = false
            try {
                PanoProcessor.validateJpeg(truncated)
            } catch (e: Exception) {
                rejected = true
            }
            assertTrue(rejected)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun testSensorHQ6144WithObservableTranslation() {
        val dir =
            File(instrumentation.targetContext.cacheDir, "astra-hq-fixture").apply { mkdirs() }
        try {
            NativeFixture.create(dir.path, .15f, false)
            val frames = PanoStorage.readMetadata(dir)
            assertEquals(17, frames.size)
            assertTrue(PanoStorage.sensorPoses(frames))
            val result =
                PanoProcessor.stitch(dir, null, "auto", null) { p, msg ->
                    Log.i("AstraHQTest", "progress=$p $msg")
                }
            assertEquals(6144, result["width"])
            assertEquals(3072, result["height"])
            val report = org.json.JSONObject(File(dir, "processing.json").readText())
            assertEquals(17, report.getInt("depthFrames"))
            assertFalse(report.getString("align").contains("rotation-fallback"))
            Log.i("AstraHQTest", "SYNTHETIC HQ complete: $report")
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun unobservedZenithRejectsSensorDepth() {
        val dir =
            File(instrumentation.targetContext.cacheDir, "astra-weak-zenith").apply { mkdirs() }
        try {
            NativeFixture.create(dir.path, .15f, false)
            val frame = PanoStorage.readMetadata(dir).last()
            val blank =
                Bitmap.createBitmap(frame.imageWidth, frame.imageHeight, Bitmap.Config.ARGB_8888)
            blank.eraseColor(Color.GRAY)
            File(dir, frame.file).outputStream().use {
                blank.compress(Bitmap.CompressFormat.JPEG, 95, it)
            }
            blank.recycle()
            PanoProcessor.stitch(dir, 1024, "auto", null) { _, _ -> }
            val result = NativeStitcher.Result.fromJson(File(dir, "processing.json").readText())
            assertTrue(result.diagnostics.getInt("baConstrainedCameras") >= 13)
            assertEquals(0, result.diagnostics.getJSONArray("baCameraObservations").getInt(16))
            assertEquals(0, result.depthFrames)
            assertEquals(0.0, result.mvsSeconds, 0.0)
            assertTrue(result.align.startsWith("rotation-fallback"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun nativePhotometryFlagChangesPixelsWithoutChangingCoverage() {
        val dir =
            File(instrumentation.targetContext.cacheDir, "photometry-fixture").apply { mkdirs() }
        try {
            val frames =
                (0..1).map { i ->
                    val file = File(dir, "frame_$i.jpg")
                    val image = Bitmap.createBitmap(320, 240, Bitmap.Config.ARGB_8888)
                    image.eraseColor(
                        if (i == 0) Color.rgb(80, 80, 80) else Color.rgb(160, 160, 160)
                    )
                    file.outputStream().use { image.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                    image.recycle()
                    PanoFrameMeta(
                        index = i,
                        targetId = i,
                        targetYaw = 0f,
                        targetPitch = 0f,
                        transform =
                            PoseMath.toColumnMajor16(
                                PoseMath.rotationY(Math.toRadians(i * 45.0).toFloat())
                            ),
                        intrinsics = floatArrayOf(150f, 150f, 159.5f, 119.5f),
                        imageWidth = 320,
                        imageHeight = 240,
                        pixelWidth = 320,
                        pixelHeight = 240,
                        timestamp = i.toDouble(),
                        highRes = true,
                        file = file.name,
                        poseSource = "sensors:android",
                        exposureDuration = .01,
                        exposureDurationNs = 10_000_000,
                        diagnostics =
                            org.json
                                .JSONObject()
                                .put("cameraId", "2")
                                .put("sensorSensitivity", 100)
                                .put("aeLocked", true)
                                .put("awbLocked", true),
                    )
                }
            val locked =
                NativeStitcher.stitch(
                    dir,
                    frames,
                    1024,
                    false,
                    true,
                    File(dir, "locked.jpg"),
                    File(dir, "locked-preview.jpg"),
                    null,
                ) { _, _ ->
                }
            val legacy =
                NativeStitcher.stitch(
                    dir,
                    frames.map { it.copy(diagnostics = null) },
                    1024,
                    false,
                    true,
                    File(dir, "legacy.jpg"),
                    File(dir, "legacy-preview.jpg"),
                    null,
                ) { _, _ ->
                }
            assertTrue(locked.ok)
            assertTrue(legacy.ok)
            assertEquals("locked-capture", locked.diagnostics.getString("gainCompensation"))
            assertEquals("overlap", legacy.diagnostics.getString("gainCompensation"))
            assertEquals(locked.coverage, legacy.coverage, 0.0)
            fun peak(file: String): Int {
                val bitmap = BitmapFactory.decodeFile(File(dir, file).path)
                var peak = 0
                for (y in 0 until bitmap.height step 8) for (x in
                    0 until bitmap.width step 8) peak =
                    maxOf(peak, Color.red(bitmap.getPixel(x, y)))
                bitmap.recycle()
                return peak
            }
            assertTrue(
                "Locked input must retain its brighter source",
                peak("locked.jpg") > peak("legacy.jpg") + 30,
            )
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun captureActivityPreviewAndCancel() {
        val context = instrumentation.targetContext
        val intent =
            android.content
                .Intent(context, UltraWideCaptureActivity::class.java)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        val activity = instrumentation.startActivitySync(intent) as UltraWideCaptureActivity
        fun texture(view: android.view.View): android.view.TextureView? {
            if (view is android.view.TextureView) return view
            if (view is android.view.ViewGroup)
                for (i in 0 until view.childCount) texture(view.getChildAt(i))?.let {
                    return it
                }
            return null
        }
        try {
            var pixels = false
            val until = SystemClock.elapsedRealtime() + 10_000
            while (!pixels && SystemClock.elapsedRealtime() < until) {
                instrumentation.runOnMainSync {
                    val t = texture(activity.findViewById(android.R.id.content))
                    val bitmap = t?.bitmap
                    if (bitmap != null) {
                        pixels =
                            bitmap.width > 0 &&
                                bitmap.height > 0 &&
                                (t.surfaceTexture?.timestamp ?: 0) > 0
                        bitmap.recycle()
                    }
                }
                if (!pixels) Thread.sleep(100)
            }
            assertFalse("Capture failed during startup", activity.isFinishing)
            assertTrue("No preview texture", pixels)
            // Exercise the activity's first-target lock handshake against the real HAL.
            fun field(name: String): java.lang.reflect.Field =
                activity.javaClass.getDeclaredField(name).apply { isAccessible = true }
            val worker = field("worker").get(activity) as Handler
            val shoot =
                activity.javaClass
                    .getDeclaredMethod("shoot", PanoTarget::class.java)
                    .apply { isAccessible = true }
            var locked = false
            val lockDeadline = SystemClock.elapsedRealtime() + 8000
            while (!locked && SystemClock.elapsedRealtime() < lockDeadline) {
                val sample = CountDownLatch(1)
                worker.post {
                    if (!field("photometryLocked").getBoolean(activity))
                        shoot.invoke(
                            activity,
                            PanoTargetGrid.ultraWide().first(),
                        )
                    locked =
                        field("photometryLocked").getBoolean(activity) &&
                            field("frameReady").getBoolean(activity)
                    sample.countDown()
                }
                assertTrue(sample.await(1, TimeUnit.SECONDS))
                if (!locked) Thread.sleep(100)
            }
            assertTrue("HAL never confirmed the activity's exposure/white-balance lock", locked)
            instrumentation.runOnMainSync { activity.onBackPressedDispatcher.onBackPressed() }
            Thread.sleep(500)
            assertTrue("Cancel did not finish capture", activity.isFinishing)
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun testPhysicalCameraExposureContract() {
        val context = instrumentation.targetContext
        val choice = UltraWideCamera.discover(context) ?: error("No compatible ultra-wide camera")
        val latch = CountDownLatch(1)
        val thread = HandlerThread("AstraHALTest").apply { start() }
        val handler = Handler(thread.looper)
        var failure: Throwable? = null
        var camera: CameraDevice? = null
        var session: CameraCaptureSession? = null
        val motion = CaptureMotion(context, handler, { _, _, _ -> })
        val reader =
            ImageReader.newInstance(choice.jpeg.width, choice.jpeg.height, ImageFormat.JPEG, 2)
        var bytes: ByteArray? = null
        var timestamp = 0L
        var capture: CaptureResult? = null
        fun validate() {
            val result = capture ?: return
            val data = bytes ?: return
            try {
                val start = result[CaptureResult.SENSOR_TIMESTAMP] ?: error("No timestamp")
                val exposure = result[CaptureResult.SENSOR_EXPOSURE_TIME] ?: error("No exposure")
                assertEquals(timestamp, start)
                assertNotNull(ExposureClock.midpoint(start, exposure, choice.lens.realtime))
                val bounds =
                    android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
                assertEquals(choice.jpeg.width, bounds.outWidth)
                assertEquals(choice.jpeg.height, bounds.outHeight)
                // Device must be stationary for this test; wait for the exposure-end sensor sample.
                handler.postDelayed(
                    {
                        try {
                            assertNotNull(
                                "No safe sensor bracket for exposure",
                                motion.history.exposure(start, exposure),
                            )
                            val calibration =
                                result[CaptureResult.LENS_INTRINSIC_CALIBRATION]
                                    ?: choice.chars[
                                            CameraCharacteristics.LENS_INTRINSIC_CALIBRATION]!!
                            val raw = File(context.cacheDir, "astra-probe-raw.jpg")
                            val rotated = File(context.cacheDir, "astra-probe-upright.jpg")
                            try {
                                raw.writeBytes(data)
                                val rotation =
                                    choice.chars[CameraCharacteristics.SENSOR_ORIENTATION]!!
                                val distortion =
                                    result[CaptureResult.LENS_DISTORTION]
                                        ?: choice.chars[CameraCharacteristics.LENS_DISTORTION]
                                        ?: floatArrayOf()
                                assertTrue(
                                    NativeStitcher.rotateJpegFile(
                                        raw,
                                        rotated,
                                        rotation,
                                        intrinsics = calibration.copyOf(4),
                                        distortion = distortion,
                                    )
                                )
                                val size = PanoProcessor.validateJpeg(rotated)
                                assertEquals(
                                    if (rotation % 180 == 0) choice.jpeg.width
                                    else choice.jpeg.height,
                                    size.first,
                                )
                                assertEquals(
                                    if (rotation % 180 == 0) choice.jpeg.height
                                    else choice.jpeg.width,
                                    size.second,
                                )
                                Log.i(
                                    "AstraDeviceTest",
                                    "real JPEG calibrated correction + physical rotation passed: $size",
                                )
                            } finally {
                                raw.delete()
                                rotated.delete()
                            }
                            Log.i(
                                "AstraDeviceTest",
                                "REAL HAL verified open=${choice.lens.openId} physical=${choice.lens.physicalId} fov=${choice.lens.horizontalFov} size=${bounds.outWidth}x${bounds.outHeight} sensorOrientation=${choice.chars[CameraCharacteristics.SENSOR_ORIENTATION]} timestamp=$start exposure=$exposure crop=${result[CaptureResult.SCALER_CROP_REGION]} focal=${result[CaptureResult.LENS_FOCAL_LENGTH]} calibration=${result[CaptureResult.LENS_INTRINSIC_CALIBRATION]?.contentToString()}",
                            )
                        } catch (e: Throwable) {
                            failure = e
                        } finally {
                            latch.countDown()
                        }
                    },
                    150,
                )
            } catch (e: Throwable) {
                failure = e
                latch.countDown()
            }
        }
        handler.post {
            try {
                assertTrue(motion.start())
                reader.setOnImageAvailableListener(
                    { r ->
                        r.acquireNextImage()?.use { im ->
                            timestamp = im.timestamp
                            bytes =
                                ByteArray(im.planes[0].buffer.remaining()).also {
                                    im.planes[0].buffer.get(it)
                                }
                            validate()
                        }
                    },
                    handler,
                )
                (context.getSystemService(Context.CAMERA_SERVICE) as CameraManager).openCamera(
                    choice.lens.openId,
                    object : CameraDevice.StateCallback() {
                        override fun onOpened(c: CameraDevice) {
                            camera = c
                            val out =
                                OutputConfiguration(reader.surface).apply {
                                    choice.lens.physicalId?.let { setPhysicalCameraId(it) }
                                }
                            c.createCaptureSession(
                                SessionConfiguration(
                                    SessionConfiguration.SESSION_REGULAR,
                                    listOf(out),
                                    { r -> handler.post(r) },
                                    object : CameraCaptureSession.StateCallback() {
                                        override fun onConfigured(s: CameraCaptureSession) {
                                            session = s
                                            handler.postDelayed(
                                                {
                                                    val req =
                                                        c.createCaptureRequest(
                                                                CameraDevice.TEMPLATE_STILL_CAPTURE
                                                            )
                                                            .apply {
                                                                addTarget(reader.surface)
                                                                set(
                                                                    CaptureRequest.JPEG_ORIENTATION,
                                                                    0,
                                                                )
                                                            }
                                                    s.capture(
                                                        req.build(),
                                                        object :
                                                            CameraCaptureSession.CaptureCallback() {
                                                            override fun onCaptureCompleted(
                                                                s: CameraCaptureSession,
                                                                r: CaptureRequest,
                                                                t: TotalCaptureResult,
                                                            ) {
                                                                capture =
                                                                    choice.lens.physicalId?.let {
                                                                        t.physicalCameraResults[it]
                                                                    } ?: t
                                                                validate()
                                                            }
                                                        },
                                                        handler,
                                                    )
                                                },
                                                1500,
                                            )
                                        }

                                        override fun onConfigureFailed(s: CameraCaptureSession) {
                                            failure = IllegalStateException("Session failed")
                                            latch.countDown()
                                        }
                                    },
                                )
                            )
                        }

                        override fun onDisconnected(c: CameraDevice) {
                            failure = IllegalStateException("Disconnected")
                            latch.countDown()
                        }

                        override fun onError(c: CameraDevice, e: Int) {
                            failure = IllegalStateException("Camera error $e")
                            latch.countDown()
                        }
                    },
                    handler,
                )
            } catch (e: Throwable) {
                failure = e
                latch.countDown()
            }
        }
        try {
            assertTrue("Camera timeout", latch.await(20, TimeUnit.SECONDS))
            failure?.let { throw AssertionError(it) }
        } finally {
            handler.post {
                session?.close()
                camera?.close()
                reader.close()
                motion.stop()
                thread.quitSafely()
            }
        }
    }
}

object NativeFixture {
    init {
        System.loadLibrary("astra_fixtures")
    }

    external fun create(path: String, pivot: Float, measured: Boolean)
}
