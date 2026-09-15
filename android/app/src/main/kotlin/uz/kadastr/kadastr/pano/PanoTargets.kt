package uz.kadastr.kadastr.pano

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.sin

/**
 * Sferadagi bitta nishon. Burchaklar RADIANDA; yaw 0 = dunyo −Z (sessiya
 * boshlanganidagi old tomon), pitch + = yuqori.
 *
 * ⚠️ `ios/Runner/PanoCapture.swift` dagi `PanoTarget` bilan AYNAN bir xil
 * bo'lishi shart: ikkala platforma bir xil qamrovni yig'adi va server
 * ikkalasini ham farqlamaydi.
 */
data class PanoTarget(
    val id: Int,
    val yaw: Float,
    val pitch: Float,
    val optional: Boolean,
) {
    /** Nishonning dunyo koordinatasidagi yo'nalishi (birlik vektor). */
    val dirX: Float get() = cos(pitch) * sin(yaw)
    val dirY: Float get() = sin(pitch)
    val dirZ: Float get() = -cos(pitch) * cos(yaw)
}

object PanoTargetGrid {
    /**
     * Gorizontda 12 (30°), +45° da 8, −45° da 8, zenit va nadir ixtiyoriy.
     * Portret asosiy linza ≈ 55°×69° FOV → hamma joyda ≥30% ustma-ustlik.
     */
    fun build(): List<PanoTarget> {
        val out = ArrayList<PanoTarget>(30)
        fun add(yawDeg: Float, pitchDeg: Float, optional: Boolean = false) {
            out.add(
                PanoTarget(
                    id = out.size,
                    yaw = (yawDeg * Math.PI / 180).toFloat(),
                    pitch = (pitchDeg * Math.PI / 180).toFloat(),
                    optional = optional,
                )
            )
        }
        for (k in 0 until 12) add(k * 30f, 0f)
        for (k in 0 until 8) add(k * 45f + 22.5f, 45f)
        for (k in 0 until 8) add(k * 45f + 22.5f, -45f)
        add(0f, 89f, optional = true)
        add(0f, -89f, optional = true)
        return out
    }
}

/**
 * Har kadr bilan serverga ketadigan meta.
 *
 * ⚠️ Nomlar `app/services/pano_stitch.py` KUTGANI bilan aynan bir xil.
 * Serverga MAJBURIY uchtasi: `transform` (camera→world 4×4, **COLUMN-MAJOR**
 * — `numpy.reshape(4, 4, order="F")` shuni kutadi), `intrinsics`
 * (fx, fy, cx, cy) va `file`. Qolganlari ma'lumot uchun.
 *
 * ⚠️ [imageWidth]/[imageHeight] — **ASL** kadr o'lchami, ya'ni [intrinsics]
 * qaysi o'lchamga tegishli bo'lsa o'sha. JPEG kichraytirilib yoziladi
 * ([pixelWidth]/[pixelHeight]) va server intrinsics'ni haqiqiy JPEG
 * o'lchamiga O'ZI qayta masshtablaydi. Bu yerga kichraytirilgan o'lchamni
 * yozsak panorama butunlay noto'g'ri chiqadi.
 */
data class PanoFrameMeta(
    val index: Int,
    val targetId: Int,
    val targetYaw: Float,
    val targetPitch: Float,
    val transform: FloatArray,
    val intrinsics: FloatArray,
    val imageWidth: Int,
    val imageHeight: Int,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val timestamp: Double,
    val highRes: Boolean,
    val file: String,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("index", index)
        put("targetId", targetId)
        put("targetYaw", targetYaw.toDouble())
        put("targetPitch", targetPitch.toDouble())
        put("transform", JSONArray().also { a -> transform.forEach { a.put(it.toDouble()) } })
        put("intrinsics", JSONArray().also { a -> intrinsics.forEach { a.put(it.toDouble()) } })
        put("imageWidth", imageWidth)
        put("imageHeight", imageHeight)
        put("pixelWidth", pixelWidth)
        put("pixelHeight", pixelHeight)
        put("timestamp", timestamp)
        put("highRes", highRes)
        put("file", file)
    }

    // `FloatArray` maydonlari borligi uchun data-class'ning generatsiya
    // qilingan `equals`/`hashCode` i havola bo'yicha solishtiradi. Bu sinf
    // faqat ro'yxatda saqlanadi va hech qayerda taqqoslanmaydi — ogohlantirish
    // chiqmasligi uchun ochiq yozamiz.
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = index
}
