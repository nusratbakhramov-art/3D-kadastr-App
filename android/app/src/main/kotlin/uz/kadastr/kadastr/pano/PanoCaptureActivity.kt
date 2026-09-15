package uz.kadastr.kadastr.pano

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageFormat
import android.graphics.Matrix as BitmapMatrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.graphics.drawable.GradientDrawable
import android.media.Image
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.google.ar.core.ArCoreApk
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.UnavailableException
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.EnumSet
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.acos
import kotlin.math.min
import kotlin.math.sqrt

/**
 * 360° panorama uchun ARCore bilan yo'naltirilgan suratga olish.
 *
 * `ios/Runner/PanoCapture.swift` ning EGIZAGI: bir xil 30 nishon, bir xil
 * avtomatik zatvor chegaralari, bir xil `meta.json`. Server ikkala
 * platformani farqlamaydi — `app/services/pano_stitch.py` faqat
 * `transform` + `intrinsics` ni o'qiydi va konvensiya ikkalasida ham bir xil
 * (OpenGL: +X o'ng, +Y yuqori, −Z oldinga).
 *
 * ARKit'dan UCHTA farqi bor va uchalasi ham platforma cheklovi:
 *
 *  1. **Kamera oqimi qo'lda chiziladi** — ARCore'da `ARSCNView` ekvivalenti
 *     yo'q ([PanoBackgroundRenderer]).
 *  2. **Alohida yuqori aniqlikdagi kadr YO'Q.** ARKit'ning
 *     `captureHighResolutionFrame` iga mos narsa ARCore'da yo'q; o'rniga
 *     eng katta CPU kadr o'lchamiga ega kamera konfiguratsiyasi tanlanadi
 *     (odatda 1920×1080). Kadrlar baribir 1280px ga kichraytirilib
 *     yuborilgani uchun amalda farq yo'q.
 *  3. **Ekspozitsiya QULFLANMAYDI.** ARKit'da `AVCaptureDevice` ga to'g'ridan
 *     murojaat bor; ARCore'da buning uchun Shared Camera (Camera2) qatlami
 *     kerak bo'lardi. Kadrlar orasidagi yorqinlik farqini server o'zi
 *     tekislaydi (gain kompensatsiyasi + ko'p bandli aralashtirish).
 *     ⚠️ Chok ko'rinib qolsa — birinchi shu yerga qaytish kerak.
 *
 * Natija: `cacheDir/pano/<uuid>/` ichida `frame_N.jpg` + `meta.json`.
 * Dart shu katalogni o'qib serverga yuklaydi va yuklagach O'ZI o'chiradi.
 */
class PanoCaptureActivity : Activity() {

    companion object {
        private const val TAG = "PanoCapture"

        /** Dart'dan keladigan tarjimalar (`HashMap<String, String>`). */
        const val EXTRA_STRINGS = "strings"

        /** Natija: kadrlar turgan katalog va ularning soni. */
        const val EXTRA_DIR = "dir"
        const val EXTRA_FRAMES = "frames"
        const val EXTRA_ERROR = "error"

        const val RESULT_FAILED = Activity.RESULT_FIRST_USER

        private const val CAMERA_PERMISSION_REQUEST = 9401

        /** Nishonda shuncha turilsa surat olinadi (sekund). */
        private const val DWELL_SECONDS = 0.35
        /** Nishonga shuncha yaqin bo'lishi kerak (radian). */
        private const val ANGLE_THRESHOLD = (3.5 * Math.PI / 180).toFloat()
        /** Shundan tez burilayotganda olinmaydi — surat xira chiqardi. */
        private const val MAX_ANGULAR_SPEED = (12 * Math.PI / 180).toFloat()
        /** Yozilayotgan JPEG'ning uzun tomoni. */
        private const val MAX_EDGE = 1280
        /** Shundan uzoqroq siljilsa parallaks ogohlantirishi chiqadi (metr). */
        private const val MAX_DRIFT = 0.2f
        /** Shundan kam kadr bilan tikishning ma'nosi yo'q. */
        private const val MIN_FRAMES = 4
    }

    // ── Holat ────────────────────────────────────────────────────────────────
    private lateinit var strings: Map<String, String>
    private lateinit var dir: File
    private val targets = PanoTargetGrid.build()
    private val requiredTotal = targets.count { !it.optional }

    private var session: Session? = null
    private var installRequested = false

    private val bg = PanoBackgroundRenderer()
    private lateinit var glView: GLSurfaceView
    private lateinit var overlay: PanoOverlayView
    private lateinit var counterView: TextView
    private lateinit var messageView: TextView
    private lateinit var thumbView: ImageView
    private lateinit var finishButton: Button

    /** Faqat GL oqimida tegiladi (iOS'dagi `arQueue` ning ekvivalenti). */
    private val captured = HashSet<Int>()
    private var capturing = false
    private var lastFwdX = 0f
    private var lastFwdY = 0f
    private var lastFwdZ = 0f
    private var hasLastFwd = false
    private var lastTime = 0.0
    private var dwellStart = 0.0
    private var dwellTarget = -1
    private var anchorX = 0f
    private var anchorY = 0f
    private var anchorZ = 0f
    private var hasAnchor = false
    private var frameIndex = 0
    /** GL oqimida oxirgi yuborilgan xabar — har kadrda post qilmaslik uchun. */
    private var lastMessage: String? = null

    /**
     * Sirt o'lchami o'zgardi, lekin sessiyaga hali aytilmadi: `(rot, w, h)`.
     *
     * ⚠️ `onSurfaceChanged` sessiya HALI YO'Q paytda chaqirilishi mumkin
     * (masalan kamera ruxsati so'ralib, `onResume` erta qaytgan bo'lsa).
     * O'shanda `setDisplayGeometry` jimgina yo'qolardi va ARCore o'z
     * sukutiga qolardi — kamera tasviri cho'zilgan, nishonlar esa ekranning
     * noto'g'ri joyida chiqardi. Shuning uchun geometriya SESSIYA TIRIK
     * bo'lgan kadrda qo'llanadi.
     */
    @Volatile
    private var pendingGeometry: IntArray? = null

    private val poseM = FloatArray(16)
    private val viewM = FloatArray(16)
    private val projM = FloatArray(16)
    private val vpM = FloatArray(16)
    private val pointV = FloatArray(4)
    private val clipV = FloatArray(4)

    /** Faqat [io] oqimida tegiladi (iOS'dagi `ioQueue`). */
    private val metas = ArrayList<PanoFrameMeta>()
    private val io: ExecutorService = Executors.newSingleThreadExecutor()

    private var capturedCount = 0   // faqat UI oqimi
    private var finished = false

    private fun s(key: String, fallback: String): String = strings[key] ?: fallback

    // ── Hayot sikli ──────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        strings = readStrings()

        // `cacheDir` — kadrlar VAQTINCHALIK. Dart ularni yuklab o'chiradi;
        // o'chirmasa ham OS kerak bo'lganda keshni o'zi tozalaydi.
        dir = File(File(cacheDir, "pano"), UUID.randomUUID().toString())
        if (!dir.mkdirs()) {
            failWith("Katalog yaratilmadi: ${dir.absolutePath}")
            return
        }

        setContentView(buildUi())
    }

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun readStrings(): Map<String, String> {
        val raw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getSerializableExtra(EXTRA_STRINGS, HashMap::class.java)
        } else {
            intent.getSerializableExtra(EXTRA_STRINGS)
        }
        return (raw as? HashMap<String, String>) ?: emptyMap()
    }

    override fun onResume() {
        super.onResume()
        if (finished) return

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST,
            )
            return
        }

        if (session == null && !createSession()) return
        // Sirt allaqachon tayyor bo'lsa (ruxsat so'ralib qaytilgan holat) —
        // geometriya yangi sessiyaga qaytadan aytiladi.
        if (glView.width > 0 && glView.height > 0) {
            pendingGeometry = intArrayOf(displayRotation(), glView.width, glView.height)
            bg.invalidateGeometry()
        }
        try {
            session?.resume()
        } catch (e: CameraNotAvailableException) {
            failWith(s("ar_error", "AR xatosi") + ": " + (e.message ?: "kamera band"))
            return
        }
        glView.onResume()
    }

    override fun onPause() {
        super.onPause()
        if (session != null) {
            glView.onPause()
            session?.pause()
        }
    }

    override fun onDestroy() {
        // Sessiyani kadrlardan OLDIN yopamiz — aks holda GL oqimi allaqachon
        // o'chirilgan katalogga yozishga urinishi mumkin.
        session?.close()
        session = null
        io.shutdown()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            val ok = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (!ok) {
                failWith(s("ar_error", "AR xatosi") + ": kameraga ruxsat berilmadi")
            }
            // Ruxsat berilgan bo'lsa tizim `onResume` ni qayta chaqiradi.
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // ── ARCore sessiyasi ─────────────────────────────────────────────────────

    /** `false` qaytsa ekran yopilgan yoki o'rnatish so'ralgan. */
    private fun createSession(): Boolean {
        try {
            when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    installRequested = true
                    return false
                }
                ArCoreApk.InstallStatus.INSTALLED -> Unit
            }

            val ses = Session(this)

            // CPU kadr o'lchami — meta'dagi `imageWidth/imageHeight` shu.
            // ⚠️ `setCameraConfig` FAQAT `resume()` dan oldin ishlaydi.
            pickCameraConfig(ses)

            ses.configure(
                Config(ses).apply {
                    focusMode = Config.FocusMode.AUTO
                    // Yoritish baholash, tekislik qidirish va chuqurlik bizga
                    // KERAK EMAS — o'chirilgani kadr tezligini saqlaydi.
                    lightEstimationMode = Config.LightEstimationMode.DISABLED
                    planeFindingMode = Config.PlaneFindingMode.DISABLED
                    depthMode = Config.DepthMode.DISABLED
                }
            )
            session = ses
            return true
        } catch (e: UnavailableException) {
            failWith(s("ar_error", "AR xatosi") + ": " + (e.message ?: e.javaClass.simpleName))
            return false
        } catch (e: Exception) {
            failWith(s("ar_error", "AR xatosi") + ": " + (e.message ?: e.javaClass.simpleName))
            return false
        }
    }

    /**
     * Eng katta CPU kadrini beradigan konfiguratsiya.
     *
     * ⚠️ Uzun tomoni 1920 dan oshiqlari ATAYLAB olinmaydi: ARCore hujjati
     * 1080p dan katta CPU kadri kadr tezligini tushirishi mumkinligini
     * aytadi, biz esa kadrni baribir 1280px ga kichraytiramiz.
     */
    private fun pickCameraConfig(ses: Session) {
        try {
            val filter = CameraConfigFilter(ses)
                .setTargetFps(
                    EnumSet.of(
                        CameraConfig.TargetFps.TARGET_FPS_30,
                        CameraConfig.TargetFps.TARGET_FPS_60,
                    )
                )
                .setDepthSensorUsage(
                    EnumSet.of(CameraConfig.DepthSensorUsage.DO_NOT_USE)
                )
            val all = ses.getSupportedCameraConfigs(filter)
            if (all.isEmpty()) return
            val best = all
                .filter { maxOf(it.imageSize.width, it.imageSize.height) <= 1920 }
                .maxByOrNull { it.imageSize.width * it.imageSize.height }
                ?: all.minByOrNull { it.imageSize.width * it.imageSize.height }
            if (best != null) ses.cameraConfig = best
        } catch (e: Exception) {
            // Tanlanmasa ARCore o'z sukutini ishlatadi — ish davom etadi.
            Log.w(TAG, "kamera konfiguratsiyasi tanlanmadi", e)
        }
    }

    // ── GL oqimi ─────────────────────────────────────────────────────────────

    private inner class Renderer : GLSurfaceView.Renderer {
        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            bg.createOnGlThread()
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            bg.invalidateGeometry()
            pendingGeometry = intArrayOf(displayRotation(), width, height)
        }

        override fun onDrawFrame(gl: GL10?) {
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
            val ses = session ?: return
            try {
                pendingGeometry?.let { g ->
                    ses.setDisplayGeometry(g[0], g[1], g[2])
                    pendingGeometry = null
                }
                ses.setCameraTextureName(bg.textureId)
                val frame = ses.update()
                bg.draw(frame)
                process(frame)
            } catch (e: CameraNotAvailableException) {
                runOnUiThread {
                    failWith(s("ar_error", "AR xatosi") + ": " + (e.message ?: "kamera band"))
                }
            } catch (e: Exception) {
                Log.w(TAG, "kadr ishlanmadi", e)
            }
        }
    }

    private fun displayRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }

    /**
     * Har kadrda: nishonlarni ekranga proyeksiya qiladi va zatvor shartini
     * tekshiradi. GL oqimida ishlaydi.
     */
    private fun process(frame: Frame) {
        val cam = frame.camera
        // ⚠️ `camera.pose` — AYNAN `imageIntrinsics` ga mos poza (kadr
        // orientatsiyasida). `displayOrientedPose` EMAS: u ekran burilishiga
        // moslangan va meta'dagi intrinsics bilan mos kelmaydi.
        cam.pose.toMatrix(poseM, 0)
        val fx = -poseM[8]
        val fy = -poseM[9]
        val fz = -poseM[10]
        val px = poseM[12]
        val py = poseM[13]
        val pz = poseM[14]
        val now = frame.timestamp / 1e9

        var angSpeed = 0f
        if (hasLastFwd && now > lastTime) {
            val d = (lastFwdX * fx + lastFwdY * fy + lastFwdZ * fz).coerceIn(-1f, 1f)
            angSpeed = (acos(d) / (now - lastTime)).toFloat()
        }
        lastFwdX = fx; lastFwdY = fy; lastFwdZ = fz; hasLastFwd = true
        lastTime = now

        val tracking = cam.trackingState == TrackingState.TRACKING

        // Nishonlarni ekranga. Bu yerda EKRANGA moslangan matritsalar
        // ishlatiladi (`getViewMatrix`/`getProjectionMatrix`) — ular
        // burilishni ham, aspektni ham o'zi hisobga oladi.
        cam.getViewMatrix(viewM, 0)
        cam.getProjectionMatrix(projM, 0, 0.1f, 100f)
        Matrix.multiplyMM(vpM, 0, projM, 0, viewM, 0)

        val w = overlay.width.toFloat()
        val h = overlay.height.toFloat()
        val dots = ArrayList<PanoOverlayView.Dot>(targets.size)
        var nearestId = -1
        var nearestAng = Float.MAX_VALUE

        for (t in targets) {
            val dx = t.dirX; val dy = t.dirY; val dz = t.dirZ
            val cosA = (dx * fx + dy * fy + dz * fz).coerceIn(-1f, 1f)
            val ang = acos(cosA)
            val inFront = cosA > 0.05f
            var sx = -1000f
            var sy = -1000f
            if (inFront && w > 0f) {
                // Nishon "3 metr naridagi" nuqta — masofa ahamiyatsiz,
                // faqat yo'nalish muhim.
                pointV[0] = px + dx * 3f
                pointV[1] = py + dy * 3f
                pointV[2] = pz + dz * 3f
                pointV[3] = 1f
                Matrix.multiplyMV(clipV, 0, vpM, 0, pointV, 0)
                if (clipV[3] > 1e-6f) {
                    sx = (clipV[0] / clipV[3] * 0.5f + 0.5f) * w
                    sy = (1f - (clipV[1] / clipV[3] * 0.5f + 0.5f)) * h
                }
            }
            val isCap = captured.contains(t.id)
            dots.add(PanoOverlayView.Dot(sx, sy, inFront && sx > -999f, isCap, t.optional))
            if (!isCap && ang < nearestAng) {
                nearestAng = ang
                nearestId = t.id
            }
        }

        var dwell = 0f
        if (tracking && !capturing && nearestId >= 0 &&
            nearestAng < ANGLE_THRESHOLD && angSpeed < MAX_ANGULAR_SPEED
        ) {
            if (dwellTarget != nearestId) {
                dwellTarget = nearestId
                dwellStart = now
            }
            val elapsed = now - dwellStart
            dwell = min(1.0, elapsed / DWELL_SECONDS).toFloat()
            if (elapsed >= DWELL_SECONDS) trigger(nearestId, frame)
        } else {
            dwellTarget = -1
        }

        // Foydalanuvchi O'ZI atrofida emas, TELEFON atrofida aylanishi kerak:
        // tana atrofida aylansa 30–40 sm richag paydo bo'ladi va yaqin
        // obyektlar chokda siljiydi (parallaks).
        var moved = false
        if (hasAnchor) {
            val ax = px - anchorX; val ay = py - anchorY; val az = pz - anchorZ
            moved = sqrt(ax * ax + ay * ay + az * az) > MAX_DRIFT
        }

        val msg = when {
            !tracking -> s("tracking", "Telefonni sekin harakatlantiring…")
            moved -> s("moved", "Joyingizda turing — telefon atrofida aylaning")
            else -> ""
        }

        overlay.submit(dots, dwell, nearestAng < ANGLE_THRESHOLD)
        if (msg != lastMessage) {
            lastMessage = msg
            runOnUiThread { showMessage(msg, moved) }
        }
    }

    // ── Surat olish ──────────────────────────────────────────────────────────

    private fun trigger(targetId: Int, frame: Frame) {
        if (capturing || captured.contains(targetId)) return
        val image: Image = try {
            frame.acquireCameraImage()
        } catch (e: NotYetAvailableException) {
            return   // keyingi kadrda qayta uriniladi
        } catch (e: Exception) {
            Log.w(TAG, "kadr olinmadi", e)
            return
        }

        capturing = true
        captured.add(targetId)
        dwellTarget = -1
        if (!hasAnchor) {
            anchorX = poseM[12]; anchorY = poseM[13]; anchorZ = poseM[14]
            hasAnchor = true
        }

        val target = targets[targetId]
        val index = frameIndex++
        val name = "frame_$index.jpg"
        val transform = poseM.copyOf()
        val intr = frame.camera.imageIntrinsics
        val focal = intr.focalLength
        val principal = intr.principalPoint
        val dims = intr.imageDimensions
        val timestamp = frame.timestamp / 1e9

        io.execute {
            try {
                val jpeg = encode(image)
                File(dir, name).writeBytes(jpeg.bytes)
                metas.add(
                    PanoFrameMeta(
                        index = index,
                        targetId = target.id,
                        targetYaw = target.yaw,
                        targetPitch = target.pitch,
                        transform = transform,
                        intrinsics = floatArrayOf(
                            focal[0], focal[1], principal[0], principal[1],
                        ),
                        // ASL o'lcham — `imageIntrinsics` AYNAN shu o'lchamga
                        // tegishli (`image.width/height` bilan bir xil bo'lishi
                        // kerak, lekin manba sifatida intrinsics'niki olinadi:
                        // server ikkalasini bog'lab qayta masshtablaydi).
                        imageWidth = dims[0],
                        imageHeight = dims[1],
                        pixelWidth = jpeg.width,
                        pixelHeight = jpeg.height,
                        timestamp = timestamp,
                        highRes = false,
                        file = name,
                    )
                )
                runOnUiThread { onFrameSaved(jpeg.thumb) }
            } catch (e: Exception) {
                Log.w(TAG, "kadr yozilmadi", e)
                runOnUiThread { onFrameSaved(null) }
            } finally {
                image.close()
                glView.queueEvent { capturing = false }
            }
        }
    }

    private class Encoded(
        val bytes: ByteArray,
        val width: Int,
        val height: Int,
        val thumb: Bitmap?,
    )

    /**
     * YUV_420_888 → kichraytirilgan JPEG.
     *
     * ⚠️ Kadr SENSOR orientatsiyasida (landshaft) qoladi va AYLANTIRILMAYDI —
     * `intrinsics` aynan shu tasvirga tegishli. Portretga aylantirilsa
     * geometriya buziladi. iOS'da ham xuddi shunday.
     */
    private fun encode(image: Image): Encoded {
        val w = image.width
        val h = image.height
        val nv21 = toNv21(image)

        val full = ByteArrayOutputStream(w * h / 4)
        YuvImage(nv21, ImageFormat.NV21, w, h, null)
            .compressToJpeg(Rect(0, 0, w, h), 95, full)
        val fullBytes = full.toByteArray()

        val scale = MAX_EDGE.toFloat() / maxOf(w, h)
        if (scale >= 1f) {
            // Kadr allaqachon yetarli kichik — qayta kodlash shart emas,
            // bitmap faqat eskiz uchun ochiladi.
            val bmp = BitmapFactory.decodeByteArray(fullBytes, 0, fullBytes.size)
            val thumb = thumbOf(bmp)
            bmp?.recycle()
            return Encoded(fullBytes, w, h, thumb)
        }

        val bmp = BitmapFactory.decodeByteArray(fullBytes, 0, fullBytes.size)
            ?: return Encoded(fullBytes, w, h, null)
        val outW = (w * scale).toInt()
        val outH = (h * scale).toInt()
        val small = Bitmap.createScaledBitmap(bmp, outW, outH, true)
        val out = ByteArrayOutputStream(outW * outH / 4)
        small.compress(Bitmap.CompressFormat.JPEG, 88, out)
        val thumb = thumbOf(small)
        if (small !== bmp) {
            bmp.recycle()
            small.recycle()
        } else {
            bmp.recycle()
        }
        return Encoded(out.toByteArray(), outW, outH, thumb)
    }

    /** Ekrandagi kichik eskiz — portretga aylantirilgan NUSXA. */
    private fun thumbOf(src: Bitmap?): Bitmap? {
        if (src == null) return null
        return try {
            val m = BitmapMatrix().apply {
                postScale(0.25f, 0.25f)
                // Sensor kadri landshaft, eskiz esa portret uyachada turadi.
                postRotate(90f)
            }
            Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
        } catch (e: Exception) {
            null
        }
    }

    /** Kamera tekisliklarini [PanoYuv] ga uzatadi. */
    private fun toNv21(image: Image): ByteArray {
        val y = image.planes[0]
        val u = image.planes[1]
        val v = image.planes[2]
        return PanoYuv.toNv21(
            width = image.width,
            height = image.height,
            y = y.buffer, yRowStride = y.rowStride,
            u = u.buffer, uRowStride = u.rowStride, uPixelStride = u.pixelStride,
            v = v.buffer, vRowStride = v.rowStride, vPixelStride = v.pixelStride,
        )
    }

    // ── Yakunlash ────────────────────────────────────────────────────────────

    /**
     * `meta.json` ni yozadi va olingan kadrlar sonini qaytaradi.
     *
     * ⚠️ [io] BITTA oqimli: unga topshiriq berib kutish undan OLDIN
     * navbatga qo'yilgan hamma yozuvning tugashini kafolatlaydi (iOS'dagi
     * `ioQueue.sync` ning ekvivalenti). Busiz `meta.json` hali diskka
     * tushmagan kadrni sanab qolardi.
     */
    private fun writeMeta(): Int {
        val list = try {
            io.submit(Callable { metas.toList() }).get()
        } catch (e: Exception) {
            Log.w(TAG, "meta yig'ilmadi", e)
            emptyList()
        }
        val arr = org.json.JSONArray()
        list.sortedBy { it.index }.forEach { arr.put(it.toJson()) }
        File(dir, "meta.json").writeText(arr.toString())
        return list.size
    }

    private fun confirmFinish() {
        AlertDialog.Builder(this)
            .setTitle(s("finish_title", "Tushirishni yakunlash?"))
            .setMessage(
                s("finish_body", "%d kadr olindi. Kam kadr — sferada boʻshliq boʻladi.")
                    .replace("%d", capturedCount.toString())
            )
            .setPositiveButton(s("finish_yes", "Yakunlash")) { _, _ -> finishOk() }
            .setNegativeButton(s("finish_no", "Davom etish"), null)
            .show()
    }

    private fun finishOk() {
        if (finished) return
        finished = true
        val count = writeMeta()
        setResult(
            Activity.RESULT_OK,
            Intent()
                .putExtra(EXTRA_DIR, dir.absolutePath)
                .putExtra(EXTRA_FRAMES, count),
        )
        finish()
    }

    private fun cancel() {
        if (finished) return
        finished = true
        io.execute { dir.deleteRecursively() }
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    private fun failWith(message: String) {
        if (finished) return
        finished = true
        io.execute { dir.deleteRecursively() }
        setResult(RESULT_FAILED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    @Deprecated("API 33+ da OnBackInvokedCallback; minSdk 24 uchun shu kerak")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        cancel()
    }

    /** Zenit va nadirni "olingan" deb belgilaydi — ularsiz yakunlash uchun. */
    private fun skipOptional() {
        glView.queueEvent {
            for (t in targets) if (t.optional) captured.add(t.id)
        }
    }

    // ── UI ───────────────────────────────────────────────────────────────────

    private fun onFrameSaved(thumb: Bitmap?) {
        capturedCount++
        counterView.text = "$capturedCount / $requiredTotal"
        if (thumb != null) {
            thumbView.setImageBitmap(thumb)
            thumbView.visibility = View.VISIBLE
        }
        finishButton.isEnabled = capturedCount >= MIN_FRAMES
        finishButton.alpha = if (capturedCount >= requiredTotal) 1f else 0.75f
        vibrate()
    }

    private fun showMessage(text: String, warn: Boolean) {
        messageView.text = text
        messageView.visibility = if (text.isEmpty()) View.GONE else View.VISIBLE
        messageView.background = pill(
            if (warn) Color.argb(230, 255, 149, 0) else Color.argb(128, 0, 0, 0)
        )
    }

    private fun vibrate() {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VibratorManager::class.java))?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        if (!v.hasVibrator()) return
        v.vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun pill(color: Int): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(999).toFloat()
    }

    private fun rounded(color: Int, radiusDp: Int): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
    }

    private fun buildUi(): View {
        val root = FrameLayout(this)

        glView = GLSurfaceView(this).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setEGLConfigChooser(8, 8, 8, 8, 16, 0)
            setRenderer(Renderer())
            renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        }
        root.addView(glView, lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        overlay = PanoOverlayView(this)
        root.addView(overlay, lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        // ── Yuqori qator ────────────────────────────────────────────────────
        val close = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
            background = pill(Color.argb(102, 0, 0, 0))
            setPadding(dp(12), dp(6), dp(12), dp(8))
            setOnClickListener { cancel() }
        }
        counterView = TextView(this).apply {
            text = "0 / $requiredTotal"
            setTextColor(Color.WHITE)
            textSize = 18f
            background = rounded(Color.argb(102, 0, 0, 0), 12)
            setPadding(dp(14), dp(8), dp(14), dp(8))
        }
        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(44), dp(16), 0)
            addView(close)
            addView(View(this@PanoCaptureActivity), LinearLayout.LayoutParams(0, 1, 1f))
            addView(counterView)
        }

        messageView = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            visibility = View.GONE
            gravity = Gravity.CENTER
            background = pill(Color.argb(128, 0, 0, 0))
            setPadding(dp(14), dp(8), dp(14), dp(8))
        }

        // ── Pastki qator ────────────────────────────────────────────────────
        thumbView = ImageView(this).apply {
            visibility = View.GONE
            scaleType = ImageView.ScaleType.CENTER_CROP
        }
        val skip = Button(this).apply {
            text = s("skip_poles", "Zenit/nadirni oʻtkazish")
            textSize = 12f
            setTextColor(Color.WHITE)
            background = rounded(Color.argb(102, 0, 0, 0), 10)
            setOnClickListener { skipOptional() }
        }
        finishButton = Button(this).apply {
            text = s("finish", "Yakunlash")
            setTextColor(Color.WHITE)
            background = rounded(Color.rgb(52, 199, 89), 12)
            isEnabled = false
            alpha = 0.75f
            setOnClickListener { confirmFinish() }
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            addView(skip)
            addView(finishButton, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) })
        }
        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
            setPadding(dp(20), 0, dp(20), dp(12))
            addView(thumbView, LinearLayout.LayoutParams(dp(56), dp(74)))
            addView(View(this@PanoCaptureActivity), LinearLayout.LayoutParams(0, 1, 1f))
            addView(actions)
        }

        val hint = TextView(this).apply {
            text = s(
                "hint",
                "Xona markazida turing · telefonni koʻkrak balandligida tuting · " +
                    "nuqtaga toʻgʻrilab bir lahza ushlang",
            )
            setTextColor(Color.argb(204, 255, 255, 255))
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(24), 0, dp(24), dp(14))
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(top, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
            addView(messageView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(8)
            })
            addView(View(this@PanoCaptureActivity), LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f,
            ))
            addView(bottom, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
            addView(hint, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        root.addView(column, lp(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
        ))
        return root
    }

    private fun lp(w: Int, h: Int) = FrameLayout.LayoutParams(w, h)
}
