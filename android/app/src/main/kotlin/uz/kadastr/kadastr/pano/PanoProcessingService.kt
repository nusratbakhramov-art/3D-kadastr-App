package uz.kadastr.kadastr.pano

import android.graphics.BitmapFactory
import android.util.Log
import java.io.File
import java.util.concurrent.Executors

/**
 * Runs one panorama processing job at a time off the platform channel thread.
 */
object PanoProcessingRunner {
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var running = false

    @Synchronized
    fun start(work: () -> Unit): Boolean {
        if (running) return false
        running = true
        executor.execute {
            try {
                work()
            } finally {
                finish()
            }
        }
        return true
    }

    @Synchronized
    private fun finish() {
        running = false
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
