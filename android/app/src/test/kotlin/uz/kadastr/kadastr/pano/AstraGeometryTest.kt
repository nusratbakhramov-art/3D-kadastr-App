package uz.kadastr.kadastr.pano

import org.junit.Assert.*
import org.junit.Test

class AstraGeometryTest {
    private fun rad(d: Double) = Math.toRadians(d).toFloat()

    private val id = PoseMath.IDENTITY

    @Test
    fun grid() {
        val g = PanoTargetGrid.ultraWide()
        assertEquals(17, g.size)
        assertEquals(17, g.map { it.id }.toSet().size)
        assertTrue(g.none { it.optional })
        assertEquals((0..7).map { rad(it * 45.0) }, g.take(8).map { it.yaw })
        assertEquals(
            listOf(52.0, -52.0).flatMap { p -> List(4) { rad(p) } } + rad(89.0),
            g.drop(8).map { it.pitch },
        )
        assertEquals(
            listOf(45.0, 135.0, 225.0, 315.0).map { rad(it) },
            g.subList(8, 12).map { it.yaw },
        )
    }

    @Test
    fun coordinates() {
        val ra = floatArrayOf(1f, 0f, 0f, 0f, 0f, -1f, 0f, 1f, 0f)
        assertArrayEquals(id, PoseMath.androidToOurs(ra), 1e-6f)
        assertArrayEquals(
            floatArrayOf(0f, 0f, 0f, 1f),
            PoseMath.toColumnMajor16(id).sliceArray(12..15),
            0f,
        )
        assertArrayEquals(floatArrayOf(0f, 0f, -1f), PoseMath.forward(id), 0f)
    }

    @Test
    fun exposureInterpolation() {
        val h = CapturePoseHistory()
        assertNull(h.at(1))
        h.add(1_000_000_000, id, 0f)
        h.add(1_020_000_000, PoseMath.rotationY(rad(.1)), rad(5.0))
        assertArrayEquals(PoseMath.rotationY(rad(.05)), h.at(1_010_000_000), 1e-5f)
        assertNotNull(h.exposure(1_002_000_000, 16_000_000))
        assertNull(h.at(999_000_000))
        assertNull(h.at(1_030_000_000))
        h.add(1_100_000_000, id, 0f)
        assertNull(h.at(1_050_000_000))
        h.add(1_110_000_000, id, rad(9.0))
        assertNull(h.at(1_105_000_000))
        assertArrayEquals(
            id,
            PoseMath.quaternionToMatrix(
                PoseMath.slerp(floatArrayOf(1f, 0f, 0f, 0f), floatArrayOf(-1f, 0f, 0f, 0f), .5f)
            ),
            1e-5f,
        )
    }

    @Test
    fun sharedClockOnly() {
        assertEquals(1_010_000_000L, ExposureClock.midpoint(1_000_000_000, 20_000_000, true))
        assertNull(ExposureClock.midpoint(1_000_000_000, 20_000_000, false))
        assertNull(ExposureClock.midpoint(1_000_000_000, 0, true))
    }

    @Test
    fun gates() {
        val g = CaptureGate()
        assertEquals(0f, g.progress(1, 1_000_000_000, 0, 0f, 0f, id), 0f)
        assertEquals(1f, g.progress(1, 1_350_000_000, 0, 0f, 0f, id), 0f)
        assertEquals(0f, g.progress(2, 1_400_000_000, 0, 0f, 0f, id), 0f)
        assertEquals(0f, g.progress(2, 1_800_000_000, 0, rad(7.0), 0f, id), 0f)
        assertFalse(CaptureGate.level(poseForSavedImage(id, 0, 90)))
        assertTrue(CaptureGate.level(floatArrayOf(1f, 0f, 0f, 0f, 0f, -1f, 0f, 1f, 0f)))
        assertEquals(0f, g.progress(2, 2_000_000_000, 200_000_000, 0f, 0f, id), 0f)
        assertEquals(0f, g.progress(2, 2_000_000_000, 0, 0f, rad(9.0), id), 0f)
    }

    @Test
    fun cropAndRotation() {
        val k = CaptureIntrinsics(2000f, 2000f, 1999.5f, 1499.5f, 4000, 3000, "test")
        val s = k.cropped(1000f, 750f, 2000f, 1500f, 1000, 500)
        assertEquals(1000f, s.fx, 0f)
        assertEquals(499.5f, s.cx, 0f)
        assertEquals(249.5f, s.cy, 0f)
        for (d in listOf(0, 90, 180, 270)) {
            assertEquals(k, k.rotated(d).rotated(360 - d))
            assertArrayEquals(id, poseForSavedImage(id, d, d), 1e-5f)
        }
        val f = CaptureIntrinsics.physical(2f, 6f, 4.5f, 4000, 3000)
        assertEquals(f.fx, f.fy, 1e-4f)
    }

    @Test
    fun cameraSelection() {
        val w = LensCandidate("anything", null, true, 5.4f, 8.16f, true, true, true)
        val u = LensCandidate("logical", "physical-xyz", true, 2.2f, 5.6f, true, true, true)
        assertEquals(u, UltraWideSelection.select(listOf(w, u)))
        assertNull(UltraWideSelection.select(listOf(w, u.copy(realtime = false))))
        assertNull(UltraWideSelection.select(listOf(u.copy(rear = false))))
        assertEquals(
            u.copy(physicalId = null),
            UltraWideSelection.select(listOf(u, u.copy(physicalId = null))),
        )
    }
}
