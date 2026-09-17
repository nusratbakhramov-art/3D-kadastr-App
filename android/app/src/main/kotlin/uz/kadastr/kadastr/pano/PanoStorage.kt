package uz.kadastr.kadastr.pano

import java.io.File
import org.json.JSONArray

/** Acquisition order is index; targetId identifies grid coverage, never an array offset. */
object PanoStorage {
    fun writeMetadata(dir: File, frames: List<PanoFrameMeta>) {
        val tmp = File(dir, "meta.json.tmp")
        val bytes =
            JSONArray().apply { frames.forEach { put(it.toJson()) } }.toString().toByteArray()
        tmp.outputStream().use {
            it.write(bytes)
            it.fd.sync()
        }
        check(tmp.renameTo(File(dir, "meta.json"))) { "Cannot persist capture metadata" }
    }

    fun readMetadata(dir: File): List<PanoFrameMeta> {
        val array = JSONArray(File(dir, "meta.json").readText())
        val frames =
            List(array.length()) { PanoFrameMeta.fromJson(array.getJSONObject(it)) }
                .sortedBy { it.index }
        require(frames.size >= 4 && frames.size <= 64) { "Need 4–64 frames" }
        require(frames.map { it.index }.toSet().size == frames.size) { "Duplicate frame index" }
        require(frames.map { it.file }.toSet().size == frames.size) { "Duplicate frame file" }
        frames.forEach {
            require(
                it.file == File(it.file).name &&
                    File(dir, it.file).canonicalFile.parentFile == dir.canonicalFile
            ) {
                "Invalid frame path"
            }
            require(File(dir, it.file).length() > 0) { "Missing frame" }
            require(
                it.imageWidth > 0 && it.imageHeight > 0 && it.intrinsics.take(2).all { f -> f > 0 }
            ) {
                "Invalid intrinsics"
            }
        }
        sensorPoses(frames) // Reject mixed/unknown provenance, never infer from shot count.
        return frames
    }

    fun sensorPoses(frames: List<PanoFrameMeta>): Boolean {
        require(frames.isNotEmpty())
        val sensor =
            frames
                .map { f ->
                    when {
                        f.poseSource == null ||
                            f.poseSource == "arcore" ||
                            f.poseSource!!.startsWith("arcore:") -> false
                        f.poseSource == "sensors" || f.poseSource!!.startsWith("sensors:") -> true
                        else -> error("Unknown pose source: ${f.poseSource}")
                    }
                }
                .toSet()
        require(sensor.size == 1) { "Mixed pose sources" }
        if (sensor.single())
            frames.forEach {
                require(it.transform.sliceArray(12..14).all { x -> x == 0f }) {
                    "Sensor input must not fabricate translation"
                }
            }
        return sensor.single()
    }
}
