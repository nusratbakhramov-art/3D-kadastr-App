package uz.kadastr.kadastr.pano

import kotlin.math.*

/** Strict exposure-time interpolation. Never substitutes a shutter-request pose. */
class CapturePoseHistory {
    data class Sample(val ns: Long, val q: FloatArray, val speed: Float)

    private val samples = ArrayDeque<Sample>()

    @Synchronized fun clear() = samples.clear()

    @Synchronized
    fun add(ns: Long, rotation: FloatArray, speed: Float) {
        if (ns <= (samples.lastOrNull()?.ns ?: 0L) || !rotation.all { it.isFinite() }) return
        samples.addLast(Sample(ns, PoseMath.matrixToQuaternion(rotation), speed))
        while (samples.size > 1 && samples.first().ns < ns - 5_000_000_000L) samples.removeFirst()
    }

    @Synchronized
    fun at(ns: Long): FloatArray? {
        if (samples.isEmpty() || ns < samples.first().ns || ns > samples.last().ns) return null
        val right = samples.indexOfFirst { it.ns >= ns }
        val b = samples.elementAt(right)
        val a = samples.elementAt(maxOf(0, right - 1))
        if (b.ns - a.ns > 50_000_000L || max(a.speed, b.speed) > CaptureGate.MAX_SPEED) return null
        if (a.ns == b.ns) return PoseMath.quaternionToMatrix(b.q)
        return PoseMath.quaternionToMatrix(
            PoseMath.slerp(a.q, b.q, (ns - a.ns).toFloat() / (b.ns - a.ns))
        )
    }

    @Synchronized
    fun exposure(start: Long, duration: Long): FloatArray? {
        if (start <= 0 || duration <= 0 || duration > 250_000_000L) return null
        if (at(start) == null || at(start + duration) == null) return null
        if (samples.any { it.ns in start..(start + duration) && it.speed > CaptureGate.MAX_SPEED })
            return null
        return at(start + duration / 2)
    }
}

object ExposureClock {
    // Camera2 REALTIME explicitly shares SensorEvent.timestamp's elapsedRealtimeNanos domain.
    // UNKNOWN cannot be safely calibrated from callback arrival (unknown ISP/transport latency).
    fun midpoint(timestamp: Long, exposure: Long, realtime: Boolean): Long? =
        if (
            realtime &&
                timestamp > 0 &&
                exposure in 1..250_000_000L &&
                timestamp <= Long.MAX_VALUE - exposure
        )
            timestamp + exposure / 2
        else null
}

class CaptureGate {
    companion object {
        val MAX_SPEED = Math.toRadians(8.0).toFloat()
        val AIM = Math.toRadians(6.0).toFloat()
        const val DWELL_NS = 350_000_000L

        fun level(rotation: FloatArray): Boolean {
            val f = PoseMath.forward(rotation)
            // Roll is undefined looking vertically; don't block the required zenith.
            return abs(f[1]) > sin(Math.toRadians(75.0)) ||
                abs(PoseMath.rollDegrees(rotation)) <= 12f
        }
    }

    private var target: Int? = null
    private var since = 0L

    fun reset() {
        target = null
        since = 0L
    }

    fun progress(
        id: Int,
        ns: Long,
        ageNs: Long,
        angle: Float,
        speed: Float,
        rotation: FloatArray,
    ): Float {
        if (
            ageNs !in 0..100_000_000L ||
                angle > AIM ||
                !angle.isFinite() ||
                speed > MAX_SPEED ||
                !level(rotation)
        ) {
            reset()
            return 0f
        }
        if (target != id) {
            target = id
            since = ns
        }
        return ((ns - since).toFloat() / DWELL_NS).coerceIn(0f, 1f)
    }
}

/** Intrinsics in pixel-center coordinates. Crop and scale share one isotropic scale. */
data class CaptureIntrinsics(
    val fx: Float,
    val fy: Float,
    val cx: Float,
    val cy: Float,
    val width: Int,
    val height: Int,
    val source: String,
) {
    init {
        require(
            width > 0 &&
                height > 0 &&
                fx > 0 &&
                fy > 0 &&
                listOf(fx, fy, cx, cy).all { it.isFinite() }
        )
    }

    fun array() = floatArrayOf(fx, fy, cx, cy)

    fun cropped(
        left: Float,
        top: Float,
        cropWidth: Float,
        cropHeight: Float,
        outW: Int,
        outH: Int,
    ): CaptureIntrinsics {
        require(cropWidth > 0 && cropHeight > 0 && left >= 0 && top >= 0)
        require(left + cropWidth <= width + 1 && top + cropHeight <= height + 1)
        val scale = max(outW / cropWidth, outH / cropHeight)
        val dx = (cropWidth * scale - outW) / 2
        val dy = (cropHeight * scale - outH) / 2
        return CaptureIntrinsics(
            fx * scale,
            fy * scale,
            (cx - left + .5f) * scale - .5f - dx,
            (cy - top + .5f) * scale - .5f - dy,
            outW,
            outH,
            source,
        )
    }

    fun rotated(degrees: Int): CaptureIntrinsics =
        when ((degrees % 360 + 360) % 360) {
            0 -> this
            90 -> CaptureIntrinsics(fy, fx, height - 1 - cy, cx, height, width, source)
            180 -> CaptureIntrinsics(fx, fy, width - 1 - cx, height - 1 - cy, width, height, source)
            270 -> CaptureIntrinsics(fy, fx, cy, width - 1 - cx, height, width, source)
            else -> error("JPEG rotation must be a multiple of 90")
        }

    companion object {
        fun physical(focalMm: Float, sensorW: Float, sensorH: Float, pixelW: Int, pixelH: Int) =
            CaptureIntrinsics(
                focalMm * pixelW / sensorW,
                focalMm * pixelH / sensorH,
                (pixelW - 1) / 2f,
                (pixelH - 1) / 2f,
                pixelW,
                pixelH,
                "physicalSize",
            )
    }
}

/** R_device←saved-image: physically rotating by sensorOrientation produces upright device axes. */
fun poseForSavedImage(
    deviceToWorld: FloatArray,
    sensorOrientation: Int,
    pixelRotation: Int,
): FloatArray {
    val a = Math.toRadians((pixelRotation - sensorOrientation).toDouble()).toFloat()
    val c = cos(a)
    val s = sin(a)
    return PoseMath.multiply(deviceToWorld, floatArrayOf(c, -s, 0f, s, c, 0f, 0f, 0f, 1f))
}
