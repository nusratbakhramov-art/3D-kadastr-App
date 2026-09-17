package uz.kadastr.kadastr.pano

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics as C
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Log
import android.util.Size

/**
 * Camera topology discovery; includes public cameras and hidden physical members of logical
 * cameras.
 */
object UltraWideCamera {
    data class Selection(val lens: LensCandidate, val chars: C, val jpeg: Size, val preview: Size)

    fun discover(context: Context): Selection? {
        if (Build.VERSION.SDK_INT < 28) return null
        val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        if (
            sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE) == null ||
                sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) == null
        )
            return null
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val selections = mutableListOf<Selection>()
        fun add(openId: String, physicalId: String?) {
            try {
                val c = manager.getCameraCharacteristics(physicalId ?: openId)
                val map = c[C.SCALER_STREAM_CONFIGURATION_MAP] ?: return
                val jpeg =
                    map.getOutputSizes(ImageFormat.JPEG)
                        ?.filter { it.width.toLong() * it.height <= 16_000_000 && it.width >= 1920 }
                        ?.maxByOrNull { it.width.toLong() * it.height } ?: return
                val preview =
                    map.getOutputSizes(SurfaceTexture::class.java)
                        ?.filter { it.width <= 1920 && it.height <= 1440 }
                        ?.minByOrNull {
                            kotlin.math.abs(
                                it.width.toDouble() / it.height -
                                    jpeg.width.toDouble() / jpeg.height
                            ) * 10000 - it.width
                        } ?: return
                val focal = c[C.LENS_INFO_AVAILABLE_FOCAL_LENGTHS]?.minOrNull() ?: return
                val physical = c[C.SENSOR_INFO_PHYSICAL_SIZE] ?: return
                val lens =
                    LensCandidate(
                        openId,
                        physicalId,
                        c[C.LENS_FACING] == C.LENS_FACING_BACK,
                        focal,
                        physical.width,
                        c[C.SENSOR_INFO_TIMESTAMP_SOURCE] ==
                            C.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME,
                        true,
                        true,
                    )
                Log.i(
                    "PanoCamera",
                    "candidate open=$openId physical=$physicalId focal=$focal sensor=$physical fov=${lens.horizontalFov} realtime=${lens.realtime} jpeg=$jpeg",
                )
                selections.add(Selection(lens, c, jpeg, preview))
            } catch (e: Exception) {
                Log.w("PanoCamera", "unavailable open=$openId physical=$physicalId", e)
            }
        }
        for (id in manager.cameraIdList) {
            val chars = manager.getCameraCharacteristics(id)
            // A logical camera's default stream can switch lenses; bind a physical stream instead.
            if (chars.physicalCameraIds.isEmpty()) add(id, null)
            else for (physical in chars.physicalCameraIds) add(id, physical)
        }
        val chosen = UltraWideSelection.select(selections.map { it.lens }) ?: return null
        return selections
            .first { it.lens == chosen }
            .also {
                Log.i(
                    "PanoCamera",
                    "selected open=${chosen.openId} physical=${chosen.physicalId} fov=${chosen.horizontalFov} JPEG=${it.jpeg}",
                )
            }
    }
}
