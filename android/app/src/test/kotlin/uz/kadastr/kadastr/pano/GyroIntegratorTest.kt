package uz.kadastr.kadastr.pano

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

/**
 * Direction conventions of [GyroIntegrator] (device-frame ω integrated in the world frame,
 * q ← q ⊗ exp(ω dt / 2)) checked through the R_ours convention of [PoseMath]:
 *
 *   phone upright, back camera facing north  ⇒  R_a = [[1,0,0],[0,0,1],[0,−1,0]]ᵀ… i.e. device
 *   x = east, y = up, z (out of the screen) = south  ⇒  R_ours = P · R_a = I.
 *
 * Android gyroscope: positive ω about an axis = counter-clockwise rotation when looking from the
 * positive end of that axis towards the origin (right-hand rule).
 */
class GyroIntegratorTest {
    private val eps = 1e-3f

    /** R_a for the phone upright facing north: columns = device axes in the Android world frame. */
    private fun uprightNorth() = floatArrayOf(
        1f, 0f, 0f,     // world x (east)  = device x
        0f, 0f, -1f,    // world y (north) = −device z
        0f, 1f, 0f,     // world z (up)    = device y
    )

    private fun integrate(g: GyroIntegrator, wx: Float, wy: Float, wz: Float, seconds: Float, hz: Int = 400) {
        val n = (seconds * hz).toInt()
        val dtNs = (1e9 / hz).toLong()
        var t = 1_000_000_000L
        g.onGyro(wx, wy, wz, t)          // first sample only sets the time base
        for (i in 0 until n) {
            t += dtNs
            g.onGyro(wx, wy, wz, t)
        }
    }

    private fun rOurs(g: GyroIntegrator): FloatArray = PoseMath.androidToOurs(g.rotationMatrix())

    @Test
    fun initialisationMatchesRotationVectorConvention() {
        val g = GyroIntegrator(tiltTauS = 0f)
        g.initFromRotationMatrix(uprightNorth())
        assertArrayEquals(PoseMath.IDENTITY, rOurs(g), eps)
        assertEquals(0f, PoseMath.yawOf(PoseMath.forward(rOurs(g))), eps)
    }

    @Test
    fun rollAboutDeviceZ_oneRadPerSecondForOneSecond() {
        val g = GyroIntegrator(tiltTauS = 0f)
        g.initFromRotationMatrix(uprightNorth())
        integrate(g, 0f, 0f, 1f, 1f)
        val r = rOurs(g)
        val theta = 1f   // 57.3°
        // Right-hand rotation about device +z (screen normal, pointing at the user): the device x
        // axis (right edge) turns towards device y (up) — seen by the user the phone turns
        // counter-clockwise. Camera +X in world (column 0 of R_ours) is therefore (cos θ, sin θ, 0):
        assertArrayEquals(floatArrayOf(cos(theta), sin(theta), 0f), floatArrayOf(r[0], r[3], r[6]), eps)
        // camera +Y (top edge) tilts to the left: (−sin θ, cos θ, 0)
        assertArrayEquals(floatArrayOf(-sin(theta), cos(theta), 0f), floatArrayOf(r[1], r[4], r[7]), eps)
        // forward stays north (−Z): a pure roll
        assertArrayEquals(floatArrayOf(0f, 0f, -1f), PoseMath.forward(r), eps)
        // roll magnitude 57.3° (PoseMath.rollDegrees measures the image rotation, i.e. the opposite sign)
        assertEquals(-Math.toDegrees(theta.toDouble()).toFloat(), PoseMath.rollDegrees(r), 0.1f)
        assertEquals(theta, PoseMath.rotationAngleBetween(PoseMath.IDENTITY, r), eps)
    }

    @Test
    fun yawAboutDeviceY_whileUpright() {
        val g = GyroIntegrator(tiltTauS = 0f)
        g.initFromRotationMatrix(uprightNorth())
        integrate(g, 0f, 1f, 0f, 1f)
        val r = rOurs(g)
        val theta = 1f
        // Upright, device y = world up. A right-hand rotation about up turns the camera to the
        // LEFT (north → west); our yaw = atan2(f.x, −f.z) is positive towards +X (east), so it
        // must be −θ, and the forward vector (−sin θ, 0, −cos θ).
        val f = PoseMath.forward(r)
        assertArrayEquals(floatArrayOf(-sin(theta), 0f, -cos(theta)), f, eps)
        assertEquals(-theta, PoseMath.yawOf(f), eps)
        assertEquals(0f, PoseMath.pitchOf(f), eps)
        assertEquals(0f, PoseMath.rollDegrees(r), 0.1f)
        // negative ω_y turns right
        val g2 = GyroIntegrator(tiltTauS = 0f)
        g2.initFromRotationMatrix(uprightNorth())
        integrate(g2, 0f, -0.5f, 0f, 1f)
        assertEquals(0.5f, PoseMath.yawOf(PoseMath.forward(rOurs(g2))), eps)
    }

    @Test
    fun pitchAboutDeviceX_whileUpright() {
        val g = GyroIntegrator(tiltTauS = 0f)
        g.initFromRotationMatrix(uprightNorth())
        integrate(g, 0.5f, 0f, 0f, 1f)
        // right-hand about device x (pointing east): the top edge tips backwards, the camera looks up
        assertEquals(0.5f, PoseMath.pitchOf(PoseMath.forward(rOurs(g))), eps)
    }

    @Test
    fun integrationOrderIsDeviceFrame() {
        // 90° about device y (turn left) then 90° about device z (roll): the roll axis must be the
        // *new* device z (now pointing east), so the forward stays west afterwards.
        val g = GyroIntegrator(tiltTauS = 0f)
        g.initFromRotationMatrix(uprightNorth())
        integrate(g, 0f, (Math.PI / 2).toFloat(), 0f, 1f)
        assertArrayEquals(floatArrayOf(-1f, 0f, 0f), PoseMath.forward(rOurs(g)), eps)
        integrate(g, 0f, 0f, (Math.PI / 2).toFloat(), 1f)
        assertArrayEquals(floatArrayOf(-1f, 0f, 0f), PoseMath.forward(rOurs(g)), eps)
        assertEquals(-90f, PoseMath.rollDegrees(rOurs(g)), 0.1f)
    }

    @Test
    fun tiltConvergesToAccelerometerWithTimeConstant() {
        val g = GyroIntegrator(tiltTauS = 2f)
        // start upright facing north but believe we are pitched up by 20°
        val pitch = Math.toRadians(20.0).toFloat()
        val rx = floatArrayOf(1f, 0f, 0f, 0f, cos(pitch), -sin(pitch), 0f, sin(pitch), cos(pitch))   // Rx(pitch) in device coords
        g.initFromRotationMatrix(PoseMath.multiply(uprightNorth(), rx))
        assertTrue(PoseMath.pitchOf(PoseMath.forward(rOurs(g))) > 0.3f)
        // accelerometer says: up is device +y exactly (phone upright, at rest)
        g.onAccel(0f, 9.81f, 0f)
        assertEquals(pitch, g.tiltErrorRad(), 1e-2f)
        // no rotation, 2 s → error × e⁻¹
        integrate(g, 0f, 0f, 0f, 2f)
        assertEquals(pitch / Math.E.toFloat(), g.tiltErrorRad(), 0.02f)
        // 10 s more → gone; yaw untouched (still north)
        integrate(g, 0f, 0f, 0f, 10f)
        assertEquals(0f, g.tiltErrorRad(), 0.01f)
        val f = PoseMath.forward(rOurs(g))
        assertEquals(0f, PoseMath.pitchOf(f), 0.01f)
        assertEquals(0f, PoseMath.yawOf(f), 0.01f)
    }

    @Test
    fun shakesAreIgnoredByTheTiltCorrection() {
        val g = GyroIntegrator(tiltTauS = 2f)
        g.initFromRotationMatrix(uprightNorth())
        g.onAccel(0f, 20f, 5f)          // |a| = 20.6 m/s² — not gravity
        integrate(g, 0f, 0f, 0f, 5f)
        assertArrayEquals(PoseMath.IDENTITY, rOurs(g), eps)
    }
}
