package uz.kadastr.kadastr.pano

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/**
 * `YUV_420_888` → `NV21`: TEKISLANGAN tekisliklar to'g'ri o'qiladimi.
 *
 * ⚠️ NEGA BU TEST BOR. Kamera kadri xotirada kenglikdan KATTA qadam bilan
 * yotadi (`rowStride`) va xrominans baytlari orasida bo'shliq bo'ladi
 * (`pixelStride` = 2). Bu ikkisini e'tiborsiz qoldirsa rasm qiyshayadi yoki
 * yashil bo'lib chiqadi — va buni FAQAT haqiqiy telefonda ko'rish mumkin,
 * ya'ni xato foydalanuvchining qo'liga yetib boradi.
 */
class PanoYuvTest {

    private fun buf(vararg v: Int) = ByteBuffer.wrap(ByteArray(v.size) { v[it].toByte() })

    /** Tekislanmagan (rowStride == width) eng oddiy holat. */
    @Test
    fun `tekis tekisliklar aynan ko'chiriladi`() {
        val w = 4
        val h = 2
        val y = buf(1, 2, 3, 4, 5, 6, 7, 8)
        val u = buf(10, 11)          // 2×1 xrominans
        val v = buf(20, 21)

        val out = PanoYuv.toNv21(
            w, h,
            y, w,
            u, 2, 1,
            v, 2, 1,
        )

        assertEquals(w * h * 3 / 2, out.size)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), out.copyOfRange(0, 8))
        // NV21 = V, U navbatma-navbat.
        assertArrayEquals(byteArrayOf(20, 10, 21, 11), out.copyOfRange(8, 12))
    }

    /** `rowStride` kenglikdan katta — to'ldirish baytlari TASHLANADI. */
    @Test
    fun `tekislangan Y tekisligi to'g'ri kesiladi`() {
        val w = 4
        val h = 2
        val stride = 6
        // Har qatorda 4 ta haqiqiy piksel + 2 ta to'ldirish (99).
        val y = buf(1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99)
        val u = buf(10, 11)
        val v = buf(20, 21)

        val out = PanoYuv.toNv21(w, h, y, stride, u, 2, 1, v, 2, 1)

        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), out.copyOfRange(0, 8))
        assertTrue("to'ldirish bayti o'tib ketdi", out.none { it == 99.toByte() })
    }

    /**
     * `pixelStride` = 2 — bu Android'dagi ENG KENG TARQALGAN holat: U va V
     * bitta bufer ustida ustma-ust yotadi (semi-planar).
     */
    @Test
    fun `pixelStride 2 bo'lgan xrominans to'g'ri o'qiladi`() {
        val w = 4
        val h = 4                    // 2×2 xrominans
        val y = ByteBuffer.wrap(ByteArray(w * h) { (it + 1).toByte() })
        // Qurilmada U va V bitta xotirada: U0 V0 U1 V1 …
        val chroma = buf(10, 20, 11, 21, 12, 22, 13, 23)
        val u = chroma.duplicate()
        val v = chroma.duplicate().also { it.position(1) }

        val out = PanoYuv.toNv21(
            w, h,
            y, w,
            u, uRowStride = 4, uPixelStride = 2,
            // ⚠️ V bufer ALREADY bittaga surilgan — `get(index)` MUTLAQ
            // indeks, ya'ni surishni o'zimiz hisobga olishimiz kerak emas.
            v, vRowStride = 4, vPixelStride = 2,
        )

        // V qiymatlari mutlaq indeks 0,2,4,6 → 10,11,12,13 (chunki
        // `duplicate().position(1)` `get(index)` ga ta'sir qilmaydi).
        val chromaOut = out.copyOfRange(w * h, out.size)
        assertArrayEquals(
            byteArrayOf(10, 10, 11, 11, 12, 12, 13, 13),
            chromaOut,
        )
    }

    /** Haqiqiy qurilma o'lchami — chegaradan chiqib ketmasin. */
    @Test
    fun `1920x1080 da chegaradan chiqmaydi`() {
        val w = 1920
        val h = 1080
        val yStride = 1920
        val cStride = 1920
        val y = ByteBuffer.allocate(yStride * h)
        // Semi-planar: oxirgi qatorda V uchun +1 bayt kerak.
        val chroma = ByteBuffer.allocate(cStride * (h / 2))

        val out = PanoYuv.toNv21(
            w, h,
            y, yStride,
            chroma, cStride, 2,
            chroma, cStride, 2,
        )
        assertEquals(w * h * 3 / 2, out.size)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `toq o'lcham rad etiladi`() {
        val y = ByteBuffer.allocate(15)
        PanoYuv.toNv21(5, 3, y, 5, y, 3, 1, y, 3, 1)
    }
}
