package uz.kadastr.kadastr.pano

import java.nio.ByteBuffer

/**
 * `YUV_420_888` → `NV21` o'girish.
 *
 * NEGA ALOHIDA. Bu butun Android portidagi eng xavfli o'n qator: kamera
 * tekisliklari TEKISLANGAN bo'ladi (`rowStride` kenglikdan katta) va
 * xrominansda `pixelStride` 2 bo'lishi mumkin. Indeksda bitta xato rasmni
 * qiyshaytiradi yoki yashil qiladi, va buni FAQAT qurilmada ko'rish
 * mumkin. Bu yerda `android.media.Image` emas, oddiy [ByteBuffer] olinadi —
 * shuning uchun oddiy JVM testi bilan tekshiriladi
 * (`src/test/.../PanoYuvTest.kt`).
 *
 * NV21 tartibi: to'liq Y tekisligi, so'ng **V va U** baytlari navbatma-navbat
 * (yarim o'lchamda). `android.graphics.YuvImage` aynan shuni kutadi.
 */
object PanoYuv {

    /** Natija uzunligi: `w * h * 3 / 2`. */
    fun sizeOf(width: Int, height: Int): Int = width * height * 3 / 2

    fun toNv21(
        width: Int,
        height: Int,
        y: ByteBuffer,
        yRowStride: Int,
        u: ByteBuffer,
        uRowStride: Int,
        uPixelStride: Int,
        v: ByteBuffer,
        vRowStride: Int,
        vPixelStride: Int,
    ): ByteArray {
        require(width > 0 && height > 0) { "o'lcham musbat bo'lishi kerak" }
        require(width % 2 == 0 && height % 2 == 0) { "YUV_420 o'lchami juft bo'ladi" }

        val out = ByteArray(sizeOf(width, height))
        var pos = 0

        // Y — `pixelStride` spetsifikatsiya bo'yicha HAR DOIM 1, shuning
        // uchun faqat `rowStride` ni hisobga olish yetarli.
        if (yRowStride == width) {
            y.position(0)
            y.get(out, 0, width * height)
            pos = width * height
        } else {
            for (r in 0 until height) {
                y.position(r * yRowStride)
                y.get(out, pos, width)
                pos += width
            }
        }

        val cw = width / 2
        val ch = height / 2
        for (r in 0 until ch) {
            val uBase = r * uRowStride
            val vBase = r * vRowStride
            for (c in 0 until cw) {
                out[pos++] = v.get(vBase + c * vPixelStride)
                out[pos++] = u.get(uBase + c * uPixelStride)
            }
        }
        return out
    }
}
