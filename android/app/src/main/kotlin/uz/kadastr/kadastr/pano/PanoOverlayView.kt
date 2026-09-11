package uz.kadastr.kadastr.pano

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/**
 * Kamera ustidagi yo'naltiruvchi qatlam: nishon nuqtalari + markaziy reticle.
 *
 * `ios/Runner/PanoCapture.swift` dagi `dots` va `reticle` ko'rinishlarining
 * ekvivalenti. Ranglar va o'lchamlar ATAYLAB bir xil — ikkala platformada
 * bir xil tushirish tajribasi bo'lishi kerak.
 */
class PanoOverlayView(context: Context) : View(context) {

    /** Bitta nishonning ekrandagi holati. */
    class Dot(
        @JvmField var x: Float,
        @JvmField var y: Float,
        @JvmField var visible: Boolean,
        @JvmField var captured: Boolean,
        @JvmField var optional: Boolean,
    )

    private var dots: List<Dot> = emptyList()
    private var dwell: Float = 0f
    private var near: Boolean = false

    private val density = context.resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val check = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.WHITE
        strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND
    }
    private val checkPath = Path()
    private val arcRect = RectF()

    init {
        setWillNotDraw(false)
        // Faqat chizadi — teginishlar ostidagi tugmalarga o'tsin.
        isClickable = false
        isFocusable = false
    }

    /** GL oqimidan keladi; [postInvalidate] UI oqimida chizishni so'raydi. */
    fun submit(newDots: List<Dot>, dwellProgress: Float, isNear: Boolean) {
        dots = newDots
        dwell = dwellProgress
        near = isNear
        postInvalidate()
    }

    override fun onDraw(canvas: Canvas) {
        for (d in dots) {
            if (!d.visible) continue
            val r = if (d.captured) dp(9f) else dp(13f)
            fill.color = when {
                d.captured -> Color.argb(90, 52, 199, 89)      // yashil, shaffof
                d.optional -> Color.argb(153, 255, 149, 0)     // to'q sariq
                else -> Color.argb(217, 255, 255, 255)
            }
            canvas.drawCircle(d.x, d.y, r, fill)
            if (d.captured) {
                val s = dp(4f)
                checkPath.reset()
                checkPath.moveTo(d.x - s, d.y)
                checkPath.lineTo(d.x - s * 0.15f, d.y + s * 0.8f)
                checkPath.lineTo(d.x + s, d.y - s * 0.7f)
                canvas.drawPath(checkPath, check)
            }
        }

        val cx = width / 2f
        val cy = height / 2f
        val rr = dp(32f)
        stroke.color = if (near) Color.rgb(52, 199, 89) else Color.argb(204, 255, 255, 255)
        stroke.strokeWidth = dp(3f)
        canvas.drawCircle(cx, cy, rr, stroke)

        if (dwell > 0f) {
            stroke.color = Color.rgb(52, 199, 89)
            stroke.strokeWidth = dp(5f)
            stroke.strokeCap = Paint.Cap.ROUND
            arcRect.set(cx - rr, cy - rr, cx + rr, cy + rr)
            canvas.drawArc(arcRect, -90f, 360f * dwell.coerceIn(0f, 1f), false, stroke)
            stroke.strokeCap = Paint.Cap.BUTT
        }

        fill.color = if (near) Color.rgb(52, 199, 89) else Color.WHITE
        canvas.drawCircle(cx, cy, dp(3f), fill)
    }
}
