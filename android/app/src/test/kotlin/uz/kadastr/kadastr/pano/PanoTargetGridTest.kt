package uz.kadastr.kadastr.pano

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Nishon panjarasi iOS BILAN BIR XIL bo'lishi shart.
 *
 * ⚠️ NEGA. Server ikkala platformadan kelgan kadrlarni farqlamaydi va
 * qamrovni nishonlar joylashuvi belgilaydi. Android panjarasi «surilib»
 * ketsa, panorama qutb yoki gorizont yaqinida bo'sh chiqadi — bu esa
 * tikishdan KEYIN, foydalanuvchi kutib bo'lgach bilinadi.
 *
 * Etalon: `ios/Runner/PanoCapture.swift` → `PanoTargetGrid.build()`.
 */
class PanoTargetGridTest {

    private val targets = PanoTargetGrid.build()

    @Test
    fun `30 nishon, 28 tasi majburiy`() {
        assertEquals(30, targets.size)
        assertEquals(2, targets.count { it.optional })
        assertEquals(28, targets.count { !it.optional })
    }

    @Test
    fun `id lar 0 dan ketma-ket`() {
        assertEquals(targets.indices.toList(), targets.map { it.id })
    }

    @Test
    fun `qatorlar — 12 gorizont, 8 yuqori, 8 past, 2 qutb`() {
        fun deg(r: Float) = Math.toDegrees(r.toDouble())
        val rows = targets.groupBy { Math.round(deg(it.pitch)).toInt() }
        assertEquals(setOf(0, 45, -45, 89, -89), rows.keys)
        assertEquals(12, rows.getValue(0).size)
        assertEquals(8, rows.getValue(45).size)
        assertEquals(8, rows.getValue(-45).size)
        assertEquals(1, rows.getValue(89).size)
        assertEquals(1, rows.getValue(-89).size)
    }

    @Test
    fun `qutblardan boshqasi ixtiyoriy EMAS`() {
        for (t in targets) {
            val pitchDeg = Math.toDegrees(t.pitch.toDouble())
            assertEquals(
                "pitch=$pitchDeg",
                abs(pitchDeg) > 80,
                t.optional,
            )
        }
    }

    @Test
    fun `yo'nalish birlik vektor`() {
        for (t in targets) {
            val n = sqrt(t.dirX * t.dirX + t.dirY * t.dirY + t.dirZ * t.dirZ)
            assertEquals("id=${t.id}", 1.0, n.toDouble(), 1e-5)
        }
    }

    /**
     * yaw 0 = dunyo −Z. Bu ARKit va ARCore uchun bir xil konvensiya; buzilsa
     * panorama 90° burилган chiqardi.
     */
    @Test
    fun `yaw 0 pitch 0 aynan minus Z`() {
        val t = targets.first()
        assertEquals(0.0, t.dirX.toDouble(), 1e-6)
        assertEquals(0.0, t.dirY.toDouble(), 1e-6)
        assertEquals(-1.0, t.dirZ.toDouble(), 1e-6)
    }

    /** yaw 90° → +X (o'ngga), ya'ni soat yo'nalishida. */
    @Test
    fun `yaw 90 daraja plyus X`() {
        val t = targets.first { Math.round(Math.toDegrees(it.yaw.toDouble())) == 90L && it.pitch == 0f }
        assertEquals(1.0, t.dirX.toDouble(), 1e-6)
        assertEquals(-0.0, t.dirZ.toDouble(), 1e-6)
    }

    @Test
    fun `gorizont nishonlari 30 daraja oraliqda`() {
        val yaws = targets.filter { it.pitch == 0f }
            .map { Math.round(Math.toDegrees(it.yaw.toDouble())).toInt() }
            .sorted()
        assertEquals((0 until 12).map { it * 30 }, yaws)
    }

    @Test
    fun `qiya qatorlar gorizontga nisbatan SURILGAN`() {
        // 22.5° surish — qo'shni qatorlar orasida ustma-ustlikni oshiradi.
        val upper = targets.filter { Math.round(Math.toDegrees(it.pitch.toDouble())) == 45L }
        assertTrue(
            upper.all { Math.toDegrees(it.yaw.toDouble()) % 45.0 in 22.0..23.0 }
        )
    }
}
