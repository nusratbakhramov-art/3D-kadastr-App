package uz.kadastr.kadastr.pano

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Low-latency orientation from the raw gyroscope (pure math, no Android dependencies).
 *
 * State: unit quaternion q = (w, x, y, z) of R_a (Android world ← device), i.e. the same contract
 * as `SensorManager.getRotationMatrixFromVector`: v_world = R_a · v_device. The Android device axes
 * are x right, y up (top edge), z out of the screen; the gyroscope reports ω in that frame (rad/s,
 * right-hand rule about each axis).
 *
 * Integration is done in the world frame with the device-frame rate: q ← q ⊗ exp(ω · dt / 2) (a
 * rotation about a *device* axis is a right-multiplication of the world←device quaternion).
 *
 * Tilt is corrected slowly towards the accelerometer's gravity (complementary filter with time
 * constant [tiltTauS]); yaw is unobservable and stays whatever it was at initialisation
 * ([initFromRotationMatrix] from the game rotation vector, or [initFromGravity]).
 *
 * Not thread-safe: use from one thread.
 */
class GyroIntegrator(private val tiltTauS: Float = 2f) {

    var qw = 1f
        private set

    var qx = 0f
        private set

    var qy = 0f
        private set

    var qz = 0f
        private set

    var initialised = false
        private set

    private var lastGyroTs = 0L
    private var ax = 0f
    private var ay = 0f
    private var az = 0f
    private var haveAccel = false
    private val r = FloatArray(9)

    /** Number of gyro samples integrated since the last (re)initialisation. */
    var samples = 0L
        private set

    fun reset() {
        qw = 1f
        qx = 0f
        qy = 0f
        qz = 0f
        initialised = false
        lastGyroTs = 0L
        haveAccel = false
        samples = 0L
    }

    /**
     * Initialises (or re-initialises) from a row-major R_a (world ← device), e.g. the rotation
     * vector.
     */
    fun initFromRotationMatrix(ra: FloatArray) {
        quaternionFromMatrix(ra)
        initialised = true
        lastGyroTs = 0L
        samples = 0L
    }

    /** Latest accelerometer sample (m/s², device frame; at rest ≈ +9.81 along world up). */
    fun onAccel(x: Float, y: Float, z: Float) {
        ax = x
        ay = y
        az = z
        haveAccel = true
    }

    /**
     * Fallback initialisation when no rotation vector sensor exists: align the device's gravity
     * with world z (yaw = 0). Returns false without an accelerometer sample.
     */
    fun initFromGravity(): Boolean {
        if (!haveAccel) return false
        val n = sqrt(ax * ax + ay * ay + az * az)
        if (n < 1e-3f) return false
        val ux = ax / n
        val uy = ay / n
        val uz = az / n // world up in the device frame
        // R (world←device): third row = u; x row = any unit vector orthogonal to u
        var xx = 1f
        var xy = 0f
        var xz = 0f
        val d = xx * ux + xy * uy + xz * uz
        xx -= d * ux
        xy -= d * uy
        xz -= d * uz
        val xn = sqrt(xx * xx + xy * xy + xz * xz)
        if (xn < 1e-3f) {
            xx = 0f
            xy = 1f
            xz = 0f
        } else {
            xx /= xn
            xy /= xn
            xz /= xn
        }
        val yx = uy * xz - uz * xy
        val yy = uz * xx - ux * xz
        val yz = ux * xy - uy * xx
        r[0] = xx
        r[1] = xy
        r[2] = xz
        r[3] = yx
        r[4] = yy
        r[5] = yz
        r[6] = ux
        r[7] = uy
        r[8] = uz
        initFromRotationMatrix(r)
        return true
    }

    /**
     * One gyroscope sample (rad/s, device frame) with its timestamp (ns). Returns true when the
     * orientation was updated (false before initialisation / for the first sample).
     */
    fun onGyro(wx: Float, wy: Float, wz: Float, tsNs: Long): Boolean {
        if (!initialised) return false
        if (lastGyroTs == 0L) {
            lastGyroTs = tsNs
            return false
        }
        val dt = ((tsNs - lastGyroTs) * 1e-9f).coerceIn(0f, 0.05f)
        lastGyroTs = tsNs
        if (dt <= 0f) return false
        samples++

        // q ← q ⊗ exp(ω dt / 2): exact exponential of the rotation vector ω·dt
        val angle = sqrt(wx * wx + wy * wy + wz * wz) * dt
        if (angle > 1e-9f) {
            val half = angle * 0.5f
            val s = sin(half) / (angle / dt) // sin(half) / |ω|
            val dw = cos(half)
            val dx = wx * s
            val dy = wy * s
            val dz = wz * s
            multiplyRight(dw, dx, dy, dz)
        }

        // tilt correction: predicted up (device frame) p = Rᵀ·z = third row of R vs measured m =
        // a/|a|
        if (haveAccel && tiltTauS > 0f) {
            val n = sqrt(ax * ax + ay * ay + az * az)
            if (n > 8.3f && n < 11.3f) { // ≈ 1 g only: ignore shakes / accelerations
                val mx = ax / n
                val my = ay / n
                val mz = az / n
                val px = 2f * (qx * qz - qy * qw)
                val py = 2f * (qy * qz + qx * qw)
                val pz = 1f - 2f * (qx * qx + qy * qy)
                // axis (device frame) that turns p towards m: p × m, |p × m| = sin(angle)
                val cx = py * mz - pz * my
                val cy = pz * mx - px * mz
                val cz = px * my - py * mx
                // gain: fraction of the error removed per sample (first-order low-pass, τ =
                // tiltTauS)
                val k = (dt / tiltTauS).coerceAtMost(1f)
                // post-multiplying q by a device-frame rotation D changes p to Dᵀ·p, so D =
                // exp(−k·(p×m))
                val vx = -cx * k
                val vy = -cy * k
                val vz = -cz * k
                val a = sqrt(vx * vx + vy * vy + vz * vz)
                if (a > 1e-9f) {
                    val h = a * 0.5f
                    val s = sin(h) / a
                    multiplyRight(cos(h), vx * s, vy * s, vz * s)
                }
            }
        }
        normalise()
        return true
    }

    /** q ← q ⊗ p. */
    private fun multiplyRight(pw: Float, px: Float, py: Float, pz: Float) {
        val nw = qw * pw - qx * px - qy * py - qz * pz
        val nx = qw * px + pw * qx + (qy * pz - qz * py)
        val ny = qw * py + pw * qy + (qz * px - qx * pz)
        val nz = qw * pz + pw * qz + (qx * py - qy * px)
        qw = nw
        qx = nx
        qy = ny
        qz = nz
    }

    private fun normalise() {
        val n = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        if (n > 1e-9f) {
            qw /= n
            qx /= n
            qy /= n
            qz /= n
        }
        if (qw < 0f) {
            qw = -qw
            qx = -qx
            qy = -qy
            qz = -qz
        } // canonical sign (w ≥ 0)
    }

    private fun quaternionFromMatrix(m: FloatArray) {
        val tr = m[0] + m[4] + m[8]
        if (tr > 0f) {
            val s = sqrt(tr + 1f) * 2f
            qw = 0.25f * s
            qx = (m[7] - m[5]) / s
            qy = (m[2] - m[6]) / s
            qz = (m[3] - m[1]) / s
        } else if (m[0] > m[4] && m[0] > m[8]) {
            val s = sqrt(1f + m[0] - m[4] - m[8]) * 2f
            qw = (m[7] - m[5]) / s
            qx = 0.25f * s
            qy = (m[1] + m[3]) / s
            qz = (m[2] + m[6]) / s
        } else if (m[4] > m[8]) {
            val s = sqrt(1f + m[4] - m[0] - m[8]) * 2f
            qw = (m[2] - m[6]) / s
            qx = (m[1] + m[3]) / s
            qy = 0.25f * s
            qz = (m[5] + m[7]) / s
        } else {
            val s = sqrt(1f + m[8] - m[0] - m[4]) * 2f
            qw = (m[3] - m[1]) / s
            qx = (m[2] + m[6]) / s
            qy = (m[5] + m[7]) / s
            qz = 0.25f * s
        }
        normalise()
    }

    /** Unit quaternion (w, x, y, z) of R_a. */
    fun quaternion(out: FloatArray = FloatArray(4)): FloatArray {
        out[0] = qw
        out[1] = qx
        out[2] = qy
        out[3] = qz
        return out
    }

    /** Row-major R_a (world ← device). */
    fun rotationMatrix(out: FloatArray = FloatArray(9)): FloatArray {
        out[0] = 1f - 2f * (qy * qy + qz * qz)
        out[1] = 2f * (qx * qy - qz * qw)
        out[2] = 2f * (qx * qz + qy * qw)
        out[3] = 2f * (qx * qy + qz * qw)
        out[4] = 1f - 2f * (qx * qx + qz * qz)
        out[5] = 2f * (qy * qz - qx * qw)
        out[6] = 2f * (qx * qz - qy * qw)
        out[7] = 2f * (qy * qz + qx * qw)
        out[8] = 1f - 2f * (qx * qx + qy * qy)
        return out
    }

    /**
     * Angle (rad) between the estimated up and the accelerometer's up — a tilt-error diagnostic.
     */
    fun tiltErrorRad(): Float {
        if (!haveAccel) return 0f
        val n = sqrt(ax * ax + ay * ay + az * az)
        if (n < 1e-3f) return 0f
        val px = 2f * (qx * qz - qy * qw)
        val py = 2f * (qy * qz + qx * qw)
        val pz = 1f - 2f * (qx * qx + qy * qy)
        val d = ((px * ax + py * ay + pz * az) / n).coerceIn(-1f, 1f)
        return kotlin.math.acos(d).let { if (abs(it) < 1e-6f) 0f else it }
    }
}
