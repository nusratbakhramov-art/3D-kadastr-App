package uz.kadastr.kadastr.pano

import kotlin.math.atan

/** IDs are opaque. Compare field of view, never camera-ID order or manufacturer. */
data class LensCandidate(
    val openId: String,
    val physicalId: String?,
    val rear: Boolean,
    val focalMm: Float,
    val sensorWidthMm: Float,
    val realtime: Boolean,
    val jpeg: Boolean,
    val preview: Boolean,
) {
    val horizontalFov: Double
        get() = Math.toDegrees(2 * atan(sensorWidthMm / (2.0 * focalMm)))
}

object UltraWideSelection {
    fun select(candidates: List<LensCandidate>): LensCandidate? =
        candidates
            .filter {
                it.rear &&
                    it.realtime &&
                    it.jpeg &&
                    it.preview &&
                    it.focalMm > 0 &&
                    it.sensorWidthMm > 0 &&
                    it.horizontalFov >= 95.0
            }
            .sortedWith(
                compareByDescending<LensCandidate> { it.horizontalFov }
                    .thenBy { it.physicalId != null }
            )
            .firstOrNull()
}
