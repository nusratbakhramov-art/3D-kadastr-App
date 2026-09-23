package uz.kadastr.kadastr.pano

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class PanoStorageTest {
    private fun frame(source: String? = null) =
        PanoFrameMeta(
            0,
            9,
            1f,
            .9f,
            PoseMath.toColumnMajor16(PoseMath.IDENTITY),
            floatArrayOf(100f, 100f, 50f, 50f),
            100,
            100,
            100,
            100,
            1.0,
            true,
            "frame_0.jpg",
            source,
        )

    @Test
    fun legacyAndSensorMetadata() {
        val old = PanoFrameMeta.fromJson(frame().toJson())
        assertNull(old.poseSource)
        assertFalse(PanoStorage.sensorPoses(listOf(old)))
        val new =
            PanoFrameMeta.fromJson(frame("sensors:android").copy(exposureDuration = .02).toJson())
        assertEquals(.02, new.exposureDuration!!, 0.0)
        assertTrue(PanoStorage.sensorPoses(listOf(new)))
        assertFalse(PanoStorage.sensorPoses(listOf(frame("arcore"))))
    }

    @Test
    fun rejectMixedOrFabricatedPoses() {
        for (frames in
            listOf(
                listOf(frame("sensors:android"), frame("arcore")),
                listOf(frame("unknown")),
                listOf(
                    frame("sensors:android")
                        .copy(
                            transform =
                                PoseMath.toColumnMajor16(PoseMath.IDENTITY).apply { this[12] = 1f }
                        )
                ),
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                try {
                    PanoStorage.sensorPoses(frames)
                } catch (e: IllegalStateException) {
                    throw IllegalArgumentException(e)
                }
            }
        }
    }

    @Test
    fun atomicStoragePreservesAcquisitionOrder() {
        val dir = Files.createTempDirectory("pano-test").toFile()
        try {
            val frames =
                List(4) { n ->
                    frame("sensors:android")
                        .copy(index = n, targetId = 16 - n, file = "frame_$n.jpg")
                }
            frames.forEach { File(dir, it.file).writeText("fixture") }
            PanoStorage.writeMetadata(dir, frames.reversed())
            assertEquals(listOf(16, 15, 14, 13), PanoStorage.readMetadata(dir).map { it.targetId })
            assertFalse(File(dir, "meta.json.tmp").exists())
            File(dir, frames[0].file).delete()
            assertThrows(IllegalArgumentException::class.java) { PanoStorage.readMetadata(dir) }
        } finally {
            dir.deleteRecursively()
        }
    }
    private fun lockedFrame() =
        frame("sensors:android")
            .copy(
                exposureDurationNs = 16_667_400L,
                diagnostics =
                    org.json
                        .JSONObject()
                        .put("cameraId", "2")
                        .put("sensorSensitivity", 61)
                        .put("aeLocked", true)
                        .put("awbLocked", true)
                        .put("distortionCorrection", org.json.JSONObject.NULL)
                        .put("lensIntrinsics", org.json.JSONArray(listOf(1, 2, 3, 4, 0))),
            )

    @Test
    fun lockedPhotometrySurvivesMetadataReload() {
        val saved = lockedFrame().toJson()
        val restored = PanoFrameMeta.fromJson(saved)
        assertTrue(PanoStorage.hasLockedPhotometry(listOf(restored, restored)))
        assertEquals(
            saved.getJSONArray("lensIntrinsics").toString(),
            restored.toJson().getJSONArray("lensIntrinsics").toString(),
        )
        assertTrue(restored.toJson().isNull("distortionCorrection"))
    }

    @Test
    fun incompleteOrChangingPhotometryRetainsCompensation() {
        val f = lockedFrame()
        assertFalse(PanoStorage.hasLockedPhotometry(emptyList()))
        assertFalse(PanoStorage.hasLockedPhotometry(listOf(f)))
        assertFalse(PanoStorage.hasLockedPhotometry(listOf(frame(), frame())))
        for (key in listOf("aeLocked", "awbLocked", "cameraId", "sensorSensitivity")) {
            val missing = PanoFrameMeta.fromJson(f.toJson().apply { remove(key) })
            assertFalse(key, PanoStorage.hasLockedPhotometry(listOf(f, missing)))
        }
        for (changed in
            listOf(
                f.copy(exposureDurationNs = null),
                f.copy(exposureDurationNs = 0),
                f.copy(exposureDurationNs = 8_333_700L),
                f.copy(poseSource = "arcore"),
                PanoFrameMeta.fromJson(f.toJson().put("aeLocked", false)),
                PanoFrameMeta.fromJson(f.toJson().put("awbLocked", false)),
                PanoFrameMeta.fromJson(f.toJson().put("aeLocked", "true")),
                PanoFrameMeta.fromJson(f.toJson().put("sensorSensitivity", 62)),
                PanoFrameMeta.fromJson(f.toJson().put("cameraId", "0")),
            )) assertFalse(PanoStorage.hasLockedPhotometry(listOf(f, changed)))
    }

    @Test
    fun savedCaptureRetainsPhotometryAndPreciseGeometryDiagnostics() {
        val dir = Files.createTempDirectory("pano-locked-test").toFile()
        try {
            val frames = List(4) { i ->
                lockedFrame().copy(
                    index = i,
                    file = "frame_$i.jpg",
                    poseInstantNs = 9_000_000_000L + i,
                    imageTimestampNs = 8_991_666_300L + i,
                    poseTimestampSource = "realtime:frameExposureMidpoint",
                    intrinsicsSource = "calibration",
                )
            }
            frames.forEach { File(dir, it.file).writeText("fixture") }
            PanoStorage.writeMetadata(dir, frames)
            val restored = PanoStorage.readMetadata(dir)
            assertTrue(PanoStorage.hasLockedPhotometry(restored))
            frames.zip(restored).forEach { (before, after) ->
                assertEquals(before.poseInstantNs, after.poseInstantNs)
                assertEquals(before.imageTimestampNs, after.imageTimestampNs)
                assertEquals(before.exposureDurationNs, after.exposureDurationNs)
                assertEquals(before.poseTimestampSource, after.poseTimestampSource)
                assertEquals(before.intrinsicsSource, after.intrinsicsSource)
            }
        } finally {
            dir.deleteRecursively()
        }
    }
}
