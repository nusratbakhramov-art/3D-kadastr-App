package uz.kadastr.kadastr.pano

import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure rotation helpers for the sensor-based camera pose (no ARCore).
 *
 * All 3×3 matrices are row-major FloatArray(9): m[row * 3 + col].
 *
 * Frames:
 * - Android world W_a: x east, y north, z up.
 * - Android device D : x right, y up (top edge in portrait), z out of the screen.
 *   `SensorManager.getRotationMatrixFromVector` gives R_a with v_Wa = R_a · v_D.
 * - Our world W (ARKit / OpenGL): +Y up, yaw 0 = −Z (the first shot's forward).
 * - Our camera C : +X right, +Y up, −Z forward. The back camera looks along device −z, so in
 *   PORTRAIT the camera frame is the device frame (provided the JPEG is saved as an upright
 *   portrait image: image +X = camera +X, image up = camera +Y).
 *
 * Therefore R_ours (camera→world) = P · R_a with P = [[1,0,0],[0,0,1],[0,−1,0]] (ours_x = east,
 * ours_y = up = android z, ours_z = −north). The camera position is (0,0,0) for every frame; the
 * C++ bundle adjustment recovers the small translations.
 *
 * After the first shot the whole world is rotated about +Y by the first shot's yaw so that the
 * first shot looks along −Z (target 0): R_world = Ry(yaw0) · R_ours.
 */
object PoseMath {

    /** R_ours = P · R_a. */
    fun androidToOurs(ra: FloatArray, out: FloatArray = FloatArray(9)): FloatArray {
        // row 0 = row 0 of R_a
        out[0] = ra[0]
        out[1] = ra[1]
        out[2] = ra[2]
        // row 1 = row 2 of R_a  (our up = android z)
        out[3] = ra[6]
        out[4] = ra[7]
        out[5] = ra[8]
        // row 2 = −row 1 of R_a  (our z = −north)
        out[6] = -ra[3]
        out[7] = -ra[4]
        out[8] = -ra[5]
        return out
    }

    /** Camera forward in world coordinates = −(third column of R). */
    fun forward(r: FloatArray, out: FloatArray = FloatArray(3)): FloatArray {
        out[0] = -r[2]
        out[1] = -r[5]
        out[2] = -r[8]
        return out
    }

    /** yaw = atan2(f.x, −f.z): 0 at −Z, increasing towards +X (to the right / east). */
    fun yawOf(f: FloatArray): Float = atan2(f[0], -f[2])

    /** pitch = asin(f.y). */
    fun pitchOf(f: FloatArray): Float = asin(f[1].coerceIn(-1f, 1f))

    /** Rotation about world +Y: Ry(θ) = [[cosθ,0,sinθ],[0,1,0],[−sinθ,0,cosθ]]. */
    fun rotationY(theta: Float, out: FloatArray = FloatArray(9)): FloatArray {
        val c = cos(theta)
        val s = sin(theta)
        out[0] = c
        out[1] = 0f
        out[2] = s
        out[3] = 0f
        out[4] = 1f
        out[5] = 0f
        out[6] = -s
        out[7] = 0f
        out[8] = c
        return out
    }

    /** out = a · b (row-major 3×3). */
    fun multiply(a: FloatArray, b: FloatArray, out: FloatArray = FloatArray(9)): FloatArray {
        for (i in 0 until 3) for (j in 0 until 3) {
            out[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
        }
        return out
    }

    /**
     * Applies the world yaw offset: R_world = Ry(yaw0) · R. A camera whose forward had yaw `yaw0`
     * ends up with yaw 0 (looking along −Z).
     */
    fun applyWorldYaw(r: FloatArray, yaw0: Float, out: FloatArray = FloatArray(9)): FloatArray =
        multiply(rotationY(yaw0), r, out)

    /** v_cam = Rᵀ · v_world (R is camera→world). */
    fun worldToCamera(r: FloatArray, v: FloatArray, out: FloatArray = FloatArray(3)): FloatArray {
        out[0] = r[0] * v[0] + r[3] * v[1] + r[6] * v[2]
        out[1] = r[1] * v[0] + r[4] * v[1] + r[7] * v[2]
        out[2] = r[2] * v[0] + r[5] * v[1] + r[8] * v[2]
        return out
    }

    /** Column-major 4×4 (16 floats) with zero translation — the meta.json `transform`. */
    fun toColumnMajor16(r: FloatArray): FloatArray =
        floatArrayOf(
            r[0],
            r[3],
            r[6],
            0f, // column 0 = camera X axis in world
            r[1],
            r[4],
            r[7],
            0f, // column 1 = camera Y axis
            r[2],
            r[5],
            r[8],
            0f, // column 2 = camera Z axis (forward = −this)
            0f,
            0f,
            0f,
            1f, // position (0,0,0)
        )

    /** Angle in radians between two unit vectors. */
    fun angleBetween(a: FloatArray, b: FloatArray): Float {
        val d = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]).coerceIn(-1f, 1f)
        return acos(d)
    }

    /** Wraps an angle to (−π, π]. */
    fun wrapPi(a: Float): Float {
        var x = a
        while (x > Math.PI) x -= (2 * Math.PI).toFloat()
        while (x <= -Math.PI) x += (2 * Math.PI).toFloat()
        return x
    }

    /**
     * Roll about the optical axis: angle of world-up seen in the camera frame, 0 = upright
     * portrait.
     */
    fun rollDegrees(r: FloatArray): Float {
        // world up (0,1,0) in camera coords = second row of R (Rᵀ · e_y)
        val upX = r[3]
        val upY = r[4]
        return Math.toDegrees(atan2(-upX, upY).toDouble()).toFloat()
    }

    /** Re-orthonormalises a rotation matrix (Gram–Schmidt on the columns). */
    fun orthonormalize(r: FloatArray) {
        // columns
        var c0 = floatArrayOf(r[0], r[3], r[6])
        var c1 = floatArrayOf(r[1], r[4], r[7])
        c0 = normalize(c0)
        val d = c0[0] * c1[0] + c0[1] * c1[1] + c0[2] * c1[2]
        c1 = normalize(floatArrayOf(c1[0] - d * c0[0], c1[1] - d * c0[1], c1[2] - d * c0[2]))
        val c2 = cross(c0, c1)
        r[0] = c0[0]
        r[3] = c0[1]
        r[6] = c0[2]
        r[1] = c1[0]
        r[4] = c1[1]
        r[7] = c1[2]
        r[2] = c2[0]
        r[5] = c2[1]
        r[8] = c2[2]
    }

    fun normalize(v: FloatArray): FloatArray {
        val n = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
        return if (n < 1e-9f) floatArrayOf(0f, 0f, 1f)
        else floatArrayOf(v[0] / n, v[1] / n, v[2] / n)
    }

    fun cross(a: FloatArray, b: FloatArray): FloatArray =
        floatArrayOf(
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        )

    val IDENTITY: FloatArray
        get() = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)

    // ---------------------------------------------------------------------------------------
    // Quaternions (w, x, y, z), unit length — used by the orientation ring buffer to
    // interpolate the rotation at the exposure instant.

    /** Row-major rotation matrix → unit quaternion (w, x, y, z) written to [out]. */
    fun matrixToQuaternion(r: FloatArray, out: FloatArray = FloatArray(4)): FloatArray {
        val tr = r[0] + r[4] + r[8]
        var w: Float
        var x: Float
        var y: Float
        var z: Float
        if (tr > 0f) {
            val s = sqrt(tr + 1f) * 2f
            w = 0.25f * s
            x = (r[7] - r[5]) / s
            y = (r[2] - r[6]) / s
            z = (r[3] - r[1]) / s
        } else if (r[0] > r[4] && r[0] > r[8]) {
            val s = sqrt(1f + r[0] - r[4] - r[8]) * 2f
            w = (r[7] - r[5]) / s
            x = 0.25f * s
            y = (r[1] + r[3]) / s
            z = (r[2] + r[6]) / s
        } else if (r[4] > r[8]) {
            val s = sqrt(1f + r[4] - r[0] - r[8]) * 2f
            w = (r[2] - r[6]) / s
            x = (r[1] + r[3]) / s
            y = 0.25f * s
            z = (r[5] + r[7]) / s
        } else {
            val s = sqrt(1f + r[8] - r[0] - r[4]) * 2f
            w = (r[3] - r[1]) / s
            x = (r[2] + r[6]) / s
            y = (r[5] + r[7]) / s
            z = 0.25f * s
        }
        val n = sqrt(w * w + x * x + y * y + z * z)
        if (n > 1e-9f) {
            w /= n
            x /= n
            y /= n
            z /= n
        }
        out[0] = w
        out[1] = x
        out[2] = y
        out[3] = z
        return out
    }

    /** Unit quaternion (w, x, y, z) → row-major rotation matrix written to [out]. */
    fun quaternionToMatrix(q: FloatArray, out: FloatArray = FloatArray(9)): FloatArray {
        val w = q[0]
        val x = q[1]
        val y = q[2]
        val z = q[3]
        out[0] = 1f - 2f * (y * y + z * z)
        out[1] = 2f * (x * y - z * w)
        out[2] = 2f * (x * z + y * w)
        out[3] = 2f * (x * y + z * w)
        out[4] = 1f - 2f * (x * x + z * z)
        out[5] = 2f * (y * z - x * w)
        out[6] = 2f * (x * z - y * w)
        out[7] = 2f * (y * z + x * w)
        out[8] = 1f - 2f * (x * x + y * y)
        return out
    }

    /**
     * Spherical linear interpolation between unit quaternions [a] (t = 0) and [b] (t = 1), taking
     * the short arc. Falls back to normalised lerp when the quaternions are (nearly) equal.
     */
    fun slerp(a: FloatArray, b: FloatArray, t: Float, out: FloatArray = FloatArray(4)): FloatArray {
        var bw = b[0]
        var bx = b[1]
        var by = b[2]
        var bz = b[3]
        var cosHalf = a[0] * bw + a[1] * bx + a[2] * by + a[3] * bz
        if (cosHalf < 0f) {
            bw = -bw
            bx = -bx
            by = -by
            bz = -bz
            cosHalf = -cosHalf
        }
        val ka: Float
        val kb: Float
        if (cosHalf > 0.9995f) {
            ka = 1f - t
            kb = t
        } else {
            val half = acos(cosHalf.coerceIn(-1f, 1f))
            val sinHalf = sin(half)
            ka = sin((1f - t) * half) / sinHalf
            kb = sin(t * half) / sinHalf
        }
        var w = ka * a[0] + kb * bw
        var x = ka * a[1] + kb * bx
        var y = ka * a[2] + kb * by
        var z = ka * a[3] + kb * bz
        val n = sqrt(w * w + x * x + y * y + z * z)
        if (n > 1e-9f) {
            w /= n
            x /= n
            y /= n
            z /= n
        }
        out[0] = w
        out[1] = x
        out[2] = y
        out[3] = z
        return out
    }

    /** Rotation angle (radians) between two rotation matrices: acos((tr(Aᵀ·B) − 1) / 2). */
    fun rotationAngleBetween(a: FloatArray, b: FloatArray): Float {
        var tr = 0f
        for (i in 0 until 3) for (j in 0 until 3) tr += a[i * 3 + j] * b[i * 3 + j]
        return acos(((tr - 1f) / 2f).coerceIn(-1f, 1f))
    }
}
