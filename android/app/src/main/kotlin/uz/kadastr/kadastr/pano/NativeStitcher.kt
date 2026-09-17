package uz.kadastr.kadastr.pano

import android.util.Log
import java.io.File
import org.json.JSONObject

/**
 * Kotlin side of the JNI bridge to the shared C++ core (`core/uy360_*.cpp`, built by
 * `app/src/main/cpp/CMakeLists.txt` into `libuy360.so`).
 *
 * Frames are passed as parallel primitive arrays (paths, 16 floats per transform, 4 floats per
 * intrinsics, 2 ints per size) — simpler and safer than parsing JSON in C++.
 */
@androidx.annotation.Keep
object NativeStitcher {
    private const val TAG = "NativeStitcher"

    /** Called from OpenCV worker threads — never touch views directly in the implementation. */
    @androidx.annotation.Keep
    fun interface ProgressCallback {
        fun onProgress(progress: Float, message: String)
    }

    /** Parsed `{ok,width,height,...}` result of a native stitch call. */
    data class Result(
        val ok: Boolean,
        val width: Int,
        val height: Int,
        val frames: Int,
        val coverage: Double,
        val seconds: Double,
        val baSeconds: Double,
        val mvsSeconds: Double,
        val stitchSeconds: Double,
        val depthFrames: Int,
        val pairs: Int,
        val residualBefore: Double,
        val residualAfter: Double,
        val blend: String,
        val align: String,
        val error: String,
    ) {
        companion object {
            fun fromJson(s: String): Result {
                val o = JSONObject(s)
                return Result(
                    ok = o.optBoolean("ok", false),
                    width = o.optInt("width"),
                    height = o.optInt("height"),
                    frames = o.optInt("frames"),
                    coverage = o.optDouble("coverage", 0.0),
                    seconds = o.optDouble("seconds", 0.0),
                    baSeconds = o.optDouble("baSeconds", 0.0),
                    mvsSeconds = o.optDouble("mvsSeconds", 0.0),
                    stitchSeconds = o.optDouble("stitchSeconds", 0.0),
                    depthFrames = o.optInt("depthFrames"),
                    pairs = o.optInt("pairs"),
                    residualBefore = o.optDouble("residualBefore", 0.0),
                    residualAfter = o.optDouble("residualAfter", 0.0),
                    blend = o.optString("blend"),
                    align = o.optString("align"),
                    error = o.optString("error"),
                )
            }
        }
    }

    @Volatile private var loaded = false
    @Volatile private var loadError: Throwable? = null

    /** Loads libuy360.so once; returns false (and logs) when the ABI is unsupported. */
    @Synchronized
    fun ensureLoaded(): Boolean {
        if (loaded) return true
        if (loadError != null) return false
        return try {
            System.loadLibrary("uy360")
            loaded = true
            Log.i(TAG, "loaded: " + version())
            true
        } catch (t: Throwable) {
            loadError = t
            Log.e(TAG, "cannot load libuy360", t)
            false
        }
    }

    /** Human readable message when the library failed to load. */
    fun loadErrorMessage(): String = loadError?.let { "libuy360: ${it.message}" } ?: ""

    private external fun version(): String

    /**
     * Signature mirrored by `Java_uz_uy360_capture_stitch_NativeStitcher_stitch` in
     * cpp/uy360_jni.cpp.
     */
    private external fun stitch(
        paths: Array<String>,
        transforms: FloatArray,
        intrinsics: FloatArray,
        sizes: IntArray,
        targetPitch: FloatArray,
        width: Int,
        mvs: Boolean,
        sensorPoses: Boolean,
        panoPath: String,
        previewPath: String,
        logoPath: String,
        cb: ProgressCallback,
    ): String

    private external fun rotateJpeg(
        src: String,
        dst: String,
        degrees: Int,
        quality: Int,
        intrinsics: FloatArray,
        distortion: FloatArray,
    ): Boolean

    /**
     * Runs the pipeline synchronously (call from a background dispatcher).
     *
     * @param mvs true → bundle adjustment + depth-from-motion + depth re-projection (minutes);
     *   false → rotation-only SIFT refine + graph-cut seams (~1 min).
     * @param sensorPoses true → the transforms are rotation-only gyro/accelerometer poses
     *   (`PipelineOptions.sensorPoses`: loose position / relative-rotation priors); false →
     *   accurate 6-DoF poses (ARCore / ARKit): the core's default priors.
     * @param logoFile PNG (square, alpha optional) stamped as a disc over the bottom 28° cap of the
     *   panorama (`Options.nadirLogoPath`) in both modes — hides feet / the mirror fill, same as
     *   the iOS app; null → no logo.
     */
    fun stitch(
        dir: File,
        frames: List<PanoFrameMeta>,
        width: Int,
        mvs: Boolean,
        sensorPoses: Boolean,
        panoFile: File,
        previewFile: File,
        logoFile: File?,
        progress: ProgressCallback,
    ): Result {
        if (!ensureLoaded())
            return Result.fromJson("""{"ok":false,"error":"${loadErrorMessage()}"}""")
        val n = frames.size
        val paths = Array(n) { File(dir, frames[it].file).absolutePath }
        val transforms = FloatArray(16 * n)
        val intrinsics = FloatArray(4 * n)
        val sizes = IntArray(2 * n)
        val pitch = FloatArray(n)
        frames.forEachIndexed { i, f ->
            f.transform.copyInto(transforms, 16 * i)
            f.intrinsics.copyInto(intrinsics, 4 * i)
            sizes[2 * i] = f.imageWidth
            sizes[2 * i + 1] = f.imageHeight
            pitch[i] = f.targetPitch
        }
        val json =
            stitch(
                paths,
                transforms,
                intrinsics,
                sizes,
                pitch,
                width,
                mvs,
                sensorPoses,
                panoFile.absolutePath,
                previewFile.absolutePath,
                logoFile?.absolutePath ?: "",
                progress,
            )
        Log.i(TAG, "result: $json")
        return Result.fromJson(json)
    }

    /**
     * Physically rotates [src] by [degrees] clockwise into [dst] (quality 95 JPEG, no EXIF). Done
     * natively: a 12-16 MP frame would need 2 × 64 MB of Java heap as Bitmaps.
     */
    fun rotateJpegFile(
        src: File,
        dst: File,
        degrees: Int,
        quality: Int = 95,
        intrinsics: FloatArray = floatArrayOf(),
        distortion: FloatArray = floatArrayOf(),
    ): Boolean {
        if (!ensureLoaded()) return false
        return rotateJpeg(
            src.absolutePath,
            dst.absolutePath,
            degrees,
            quality,
            intrinsics,
            distortion,
        )
    }
}
