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
}
