package uz.kadastr.kadastr.pano

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI

/**
 * Verifies the sensor → camera pose convention documented in PoseMath / README:
 *   R_ours = P · R_a,  P = [[1,0,0],[0,0,1],[0,−1,0]],  forward = −(third column of R_ours).
 *
 * R_a (Android world ← device) is built by hand for two well-known attitudes. Android world:
 * x east, y north, z up. Device: x right, y up (top edge), z out of the screen.
 */
class PoseMathTest {
    private val eps = 1e-5f

    /** Columns of R_a are the device axes expressed in the Android world frame. */
    private fun ra(devX: FloatArray, devY: FloatArray, devZ: FloatArray) = floatArrayOf(
        devX[0], devY[0], devZ[0],
        devX[1], devY[1], devZ[1],
        devX[2], devY[2], devZ[2],
    )

    @Test
    fun phoneFlatOnTableScreenUp_looksDown() {
        // device x = east, y = north, z (out of screen) = up  → R_a = identity
        val r = PoseMath.androidToOurs(ra(floatArrayOf(1f, 0f, 0f), floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, 0f, 1f)))
        val f = PoseMath.forward(r)
        assertArrayEquals(floatArrayOf(0f, -1f, 0f), f, eps)          // back camera looks at the floor
        assertEquals(-PI.toFloat() / 2, PoseMath.pitchOf(f), eps)
        assertEquals(0f, PoseMath.rollDegrees(r), 1e-3f)
    }

    @Test
    fun phoneUprightFacingNorth_forwardIsMinusZ() {
        // top edge up: device y = up (0,0,1); screen faces south → device z = −north (0,−1,0); x = east
        val r = PoseMath.androidToOurs(ra(floatArrayOf(1f, 0f, 0f), floatArrayOf(0f, 0f, 1f), floatArrayOf(0f, -1f, 0f)))
        assertArrayEquals(PoseMath.IDENTITY, r, eps)                   // camera frame == our world frame
        val f = PoseMath.forward(r)
        assertArrayEquals(floatArrayOf(0f, 0f, -1f), f, eps)
        assertEquals(0f, PoseMath.yawOf(f), eps)
        assertEquals(0f, PoseMath.pitchOf(f), eps)
        // world up (0,1,0) must be camera +Y (row 1 of R = (0,1,0))
        assertArrayEquals(floatArrayOf(0f, 1f, 0f), floatArrayOf(r[3], r[4], r[5]), eps)
    }

    @Test
    fun phoneUprightFacingEast_yawIsPlus90() {
        // back camera looks east: device z (out of screen) = west (−1,0,0); y = up; x = north (0,1,0)
        val r = PoseMath.androidToOurs(ra(floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, 0f, 1f), floatArrayOf(-1f, 0f, 0f)))
        val f = PoseMath.forward(r)
        assertArrayEquals(floatArrayOf(1f, 0f, 0f), f, eps)            // our +X = east
        assertEquals(PI.toFloat() / 2, PoseMath.yawOf(f), eps)
        // anchoring at this shot must turn its forward into −Z (target 0)
        val anchored = PoseMath.applyWorldYaw(r, PoseMath.yawOf(f))
        assertArrayEquals(floatArrayOf(0f, 0f, -1f), PoseMath.forward(anchored), eps)
        assertEquals(0f, PoseMath.rollDegrees(anchored), 1e-3f)
    }

    @Test
    fun columnMajorTransformMatchesArkitLayout() {
        val r = floatArrayOf(1f, 2f, 3f, 4f, 5f, 6f, 7f, 8f, 9f)   // row-major
        val t = PoseMath.toColumnMajor16(r)
        // column 0 = (r00, r10, r20)
        assertArrayEquals(floatArrayOf(1f, 4f, 7f, 0f), t.copyOfRange(0, 4), eps)
        assertArrayEquals(floatArrayOf(2f, 5f, 8f, 0f), t.copyOfRange(4, 8), eps)
        assertArrayEquals(floatArrayOf(3f, 6f, 9f, 0f), t.copyOfRange(8, 12), eps)
        assertArrayEquals(floatArrayOf(0f, 0f, 0f, 1f), t.copyOfRange(12, 16), eps)
        // forward = −column 2 = −(r02, r12, r22)
        assertArrayEquals(floatArrayOf(-3f, -6f, -9f), PoseMath.forward(r), eps)
    }

    @Test
    fun worldToCameraIsTranspose() {
        val r = PoseMath.rotationY(0.7f)
        val v = floatArrayOf(0.2f, 0.5f, -0.8f)
        val c = PoseMath.worldToCamera(r, v)
        // R · c == v
        val back = floatArrayOf(
            r[0] * c[0] + r[1] * c[1] + r[2] * c[2],
            r[3] * c[0] + r[4] * c[1] + r[5] * c[2],
            r[6] * c[0] + r[7] * c[1] + r[8] * c[2],
        )
        assertArrayEquals(v, back, eps)
    }
}
