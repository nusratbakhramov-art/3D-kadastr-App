package uz.kadastr.kadastr.pano

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Private real captures are supplied explicitly; completion is not a visual-quality assertion. */
@RunWith(AndroidJUnit4::class)
class SavedCaptureReplayTest {
    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it) }
    }

    @Test
    fun replayPrivateCapturesWithoutChangingSources() {
        val paths = InstrumentationRegistry.getArguments().getString("qualityCapturePaths")
        assumeTrue("Supply semicolon-separated private capture paths", !paths.isNullOrBlank())
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        for (path in paths!!.split(';')) {
            val source = File(path).canonicalFile
            val frames = PanoStorage.readMetadata(source)
            val files = listOf(File(source, "meta.json")) + frames.map { File(source, it.file) }
            val before = files.associateWith { digest(it) }
            val output = File(context.cacheDir, "quality-replay-${source.name}").canonicalFile
            assertNotEquals(source, output)
            assertTrue(output.mkdirs() || output.isDirectory)
            try {
                files.forEach { it.copyTo(File(output, it.name), overwrite = true) }
                PanoProcessor.stitch(output, 6144, "auto", null) { _, _ -> }
                val result = NativeStitcher.Result.fromJson(File(output, "processing.json").readText())
                assertTrue(result.ok)
                assertEquals(frames.size, result.frames)
                assertEquals(6144 to 3072, PanoProcessor.validateJpeg(File(output, "pano.jpg")))
                assertTrue(result.coverage >= .90)
                if (result.depthFrames > 0) {
                    assertEquals(frames.size, result.depthFrames)
                    assertEquals(frames.size, result.diagnostics.getInt("baConstrainedCameras"))
                    assertTrue(result.align.startsWith("depth-reprojection"))
                } else {
                    assertTrue(result.align.startsWith("rotation-fallback"))
                    assertTrue(result.diagnostics.getString("fallbackReason").isNotBlank())
                }
                assertEquals(
                    if (PanoStorage.hasLockedPhotometry(frames)) "locked-capture" else "overlap",
                    result.diagnostics.getString("gainCompensation"),
                )
                Log.i("QualityReplay", "${source.name}: ${result.diagnostics}")
            } finally {
                before.forEach { (file, hash) -> assertEquals(file.path, hash, digest(file)) }
            }
        }
    }
}
