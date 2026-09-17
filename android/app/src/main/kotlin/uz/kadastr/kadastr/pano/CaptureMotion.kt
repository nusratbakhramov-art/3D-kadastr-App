package uz.kadastr.kadastr.pano

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.HandlerThread
import kotlin.math.sqrt

/** Astra Android's raw-gyro complementary filter: avoids vendor rotation-vector pipeline lag. */
class CaptureMotion(
    context: Context,
    private val handler: Handler,
    private val onPose: (Long, FloatArray, Float) -> Unit,
    private val onFailure: () -> Unit = {},
) : SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    // JPEG correction can occupy the camera worker for hundreds of milliseconds.
    // Drain motion on its own Looper so those samples are never dropped behind image IO.
    private val sensorThread = HandlerThread("AstraMotion").apply { start() }
    private val sensorHandler = Handler(sensorThread.looper)
    @Volatile private var active = false
    @Volatile private var closed = false
    private val integrator = GyroIntegrator()
    val history = CapturePoseHistory()
    private var last = 0L
    private var anchor: Float? = null

    fun start(): Boolean {
        if (closed) return false
        if (active) return true
        val gyro = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: return false
        val accel = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return false
        active = true
        val a = manager.registerListener(this, accel, 10_000, sensorHandler)
        val g = manager.registerListener(this, gyro, 5_000, sensorHandler)
        if (!a || !g) stop()
        return a && g
    }

    fun stop() {
        active = false
        closed = true
        manager.unregisterListener(this)
        sensorThread.quitSafely()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(e: SensorEvent) {
        if (!active) return
        if (e.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            integrator.onAccel(e.values[0], e.values[1], e.values[2])
            if (!integrator.initialised) integrator.initFromGravity()
            return
        }
        if (e.sensor.type != Sensor.TYPE_GYROSCOPE) return
        // A gap means integration cannot recover the missed rotation. Do not save such poses.
        if (last != 0L && e.timestamp - last > 50_000_000L) {
            stop()
            handler.post { onFailure() }
            return
        }
        last = e.timestamp
        if (!integrator.onGyro(e.values[0], e.values[1], e.values[2], e.timestamp)) return
        val r = PoseMath.androidToOurs(integrator.rotationMatrix())
        if (anchor == null) anchor = PoseMath.yawOf(PoseMath.forward(r))
        val world = PoseMath.applyWorldYaw(r, anchor!!)
        val speed = sqrt(e.values.take(3).sumOf { (it * it).toDouble() }).toFloat()
        history.add(e.timestamp, world, speed)
        val timestamp = e.timestamp
        handler.post { if (active) onPose(timestamp, world, speed) }
    }
}
