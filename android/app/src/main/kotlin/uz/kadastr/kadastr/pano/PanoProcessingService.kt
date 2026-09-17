package uz.kadastr.kadastr.pano

import android.app.*
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.Executors

/**
 * Keeps an accepted capture processing through Activity backgrounding; all inputs remain retryable.
 */
class PanoProcessingService : Service() {
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
        @Volatile private var job: (() -> Unit)? = null

        @Synchronized
        fun reserve(work: () -> Unit): Boolean {
            if (job != null) return false
            job = work
            return true
        }

        @Synchronized
        fun release() {
            job = null
        }
    }

    private var started = false

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(
                    NotificationChannel(
                        "panorama_processing",
                        "360° panorama",
                        NotificationManager.IMPORTANCE_LOW,
                    )
                )
        }
        startForeground(
            360,
            NotificationCompat.Builder(this, "panorama_processing")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setContentTitle("3D kadastr · 360°")
                .setContentText("Panorama…")
                .setOngoing(true)
                .build(),
        )
        if (!started) {
            started = true
            executor.execute {
                try {
                    job?.invoke()
                } finally {
                    release()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }
}

object PanoProcessor {
    fun validateJpeg(file: File): Pair<Int, Int> {
        require(file.length() >= 4) { "Empty JPEG: ${file.name}" }
        java.io.RandomAccessFile(file, "r").use {
            require(it.readUnsignedShort() == 0xffd8) { "Invalid JPEG header" }
            it.seek(it.length() - 2)
            require(it.readUnsignedShort() == 0xffd9) { "Truncated JPEG" }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Cannot decode JPEG" }
        // Decode a small image too, not just dimensions from a truncated header.
        val bitmap =
            BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = 8 })
                ?: error("Invalid JPEG pixels")
        bitmap.recycle()
        return bounds.outWidth to bounds.outHeight
    }

    fun stitch(
        dir: File,
        width: Int?,
        mode: String,
        logo: File?,
        progress: NativeStitcher.ProgressCallback,
    ): Map<String, Any> {
        val frames = PanoStorage.readMetadata(dir)
        val sensors = PanoStorage.sensorPoses(frames)
        frames.forEach { frame ->
            require(
                validateJpeg(File(dir, frame.file)) == (frame.pixelWidth to frame.pixelHeight)
            ) {
                "Saved JPEG dimensions do not match metadata"
            }
        }
        val outputWidth = width ?: if (sensors) 6144 else 4096
        require(outputWidth in 1024..6144 && outputWidth % 2 == 0)
        val mvs = sensors || mode != "fast"
        Log.i(
            "PanoProcessor",
            "preset width=$outputWidth HQ=$mvs sensorPoses=$sensors frames=${frames.size}",
        )
        val pano = File(dir, "pano.pending.jpg")
        val preview = File(dir, "preview.pending.jpg")
        val result =
            NativeStitcher.stitch(
                dir,
                frames,
                outputWidth,
                mvs,
                sensors,
                pano,
                preview,
                logo,
                progress,
            )
        require(result.ok) { result.error }
        require(validateJpeg(pano) == outputWidth to outputWidth / 2) {
            "Invalid panorama dimensions"
        }
        val dimensions = validateJpeg(preview)
        require(dimensions.first == dimensions.second * 2)
        // Pano is the completion marker; install it last, after both outputs are verified.
        check(preview.renameTo(File(dir, "preview.jpg")))
        check(pano.renameTo(File(dir, "pano.jpg")))
        Log.i(
            "PanoProcessor",
            "completed seconds=${result.seconds} align=${result.align} depthFrames=${result.depthFrames}",
        )
        File(dir, "processing.json")
            .writeText(
                org.json
                    .JSONObject()
                    .put("width", outputWidth)
                    .put("height", outputWidth / 2)
                    .put("sensorPoses", sensors)
                    .put("seconds", result.seconds)
                    .put("align", result.align)
                    .put("depthFrames", result.depthFrames)
                    .toString()
            )
        return mapOf(
            "pano" to File(dir, "pano.jpg").path,
            "preview" to File(dir, "preview.jpg").path,
            "width" to outputWidth,
            "height" to outputWidth / 2,
            "frames" to frames.size,
            "coverage" to result.coverage,
            "seconds" to result.seconds,
            "mode" to if (mvs) "mvs" else "fast",
        )
    }
}
