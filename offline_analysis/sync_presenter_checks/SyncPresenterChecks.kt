package com.example.test_face.render

import android.media.Image
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.abs

private fun eye(x: Float, width: Float = 40f, closed: Float = 0f, generation: Long = 1) = SyncPresenter.EyePose(
    EyeTransform(Float3(x, 0f, 0f), Quaternion(0f, 0f, 0f, 1f), Float3(1f),
        eyeWidthPx = width, worldPerImagePx = width / 100f,
        lashLineCurve = LashLineCurve.fit(listOf(ImagePoint(-width / 2, 0f), ImagePoint(0f, -width / 10), ImagePoint(width / 2, 0f)), ImagePoint(0f, 0f), ImagePoint(1f, 0f))),
    closed, generation, LashStyleConfig(),
)

private fun item(image: Image, left: SyncPresenter.EyePose? = null) = SyncPresenter.Item(
    image, image.timestamp, 0, true, CameraProjection(), -10f, left, null, left != null,
)

fun main() {
    val a = eye(0f, 40f, 0f)
    val b = eye(10f, 80f, 1f)
    val start = 1_000_000_000L
    val end = start + 100_000_000L
    val mid = SyncPresenter.forTimestamp(a, b, start, end, start + 50_000_000L, 200_000_000L)!!
    check(mid.pose.position.x == 5f && mid.closedAmount == 0.5f)
    check(mid.pose.eyeWidthPx == 60f)
    check(abs(mid.pose.lashLineCurve!!.deviationAt(0f) + 6f) < 1e-5f)
    check(SyncPresenter.forTimestamp(null, b, 0, end, end - 33_000_000, 200_000_000) == null)
    check(SyncPresenter.forTimestamp(null, b, 0, end, end, 200_000_000) === b)
    check(SyncPresenter.forTimestamp(a, b, start, start + 300_000_000, end, 200_000_000) == null)
    check(SyncPresenter.forTimestamp(a, b, start, end, start - 10_000_000, 200_000_000) == null)
    check(SyncPresenter.interpolate(a, eye(10f, generation = 2), 0.5f) == null)

    // A root fixed on the eyelid must stay fixed while the asset rotates.
    val qa = Quaternion(0f, 0f, 0f, 1f)
    val qb = Quaternion(0f, 0f, 1f, 0f)
    val root = -0.36f
    val anchor = Float3(1f, 2f, 3f)
    fun anchored(q: Quaternion): SyncPresenter.EyePose {
        val pose = a.pose.copy(rotation = q, position = anchor - SyncPresenter.rootOffset(q, a.pose.scale.y, root))
        return SyncPresenter.EyePose(pose, 0f, 1, LashStyleConfig(), root)
    }
    val pivotMid = SyncPresenter.interpolate(anchored(qa), anchored(qb), 0.5f)!!
    val actualRoot = pivotMid.pose.position + SyncPresenter.rootOffset(pivotMid.pose.rotation, pivotMid.pose.scale.y, root)
    check(abs(actualRoot.x - anchor.x) < 1e-5f && abs(actualRoot.y - anchor.y) < 1e-5f && abs(actualRoot.z - anchor.z) < 1e-5f)

    // 30 camera frames/s, 20 analysis results/s, 80ms processing, 60Hz display.
    // Every displayed image must carry the pose for its own timestamp.
    var now = start
    val presenter = SyncPresenter({ now }, { now })
    val images = (0 until 90).map { Image(start + it * 33_333_333L) }
    val samples = images.indices.filter { it % 3 != 1 }
    var sampleIndex = 0
    var nextImage = 0
    var previousTimestamp = 0L
    var previousEye: SyncPresenter.EyePose? = null
    var nextVsync = start
    val shown = mutableListOf<Pair<Int, Long>>()
    while (now < start + 3_500_000_000L) {
        while (sampleIndex < samples.size && now >= images[samples[sampleIndex]].timestamp + 80_000_000L) {
            val index = samples[sampleIndex++]
            val current = eye(index.toFloat())
            val timestamp = images[index].timestamp
            val batch = (nextImage..index).map { frame ->
                item(images[frame], SyncPresenter.forTimestamp(previousEye, current, previousTimestamp, timestamp, images[frame].timestamp, 200_000_000L))
            }
            presenter.enqueue(batch)
            nextImage = index + 1
            previousEye = current
            previousTimestamp = timestamp
        }
        if (now >= nextVsync) {
            nextVsync += 16_666_667L
            presenter.poll(now)?.let { frame ->
                val index = images.indexOf(frame.image)
                check(abs(frame.left!!.pose.position.x - index) < 1e-4f) { "Pose/image timestamp mismatch at $index" }
                check(frame.image.closed == 0)
                frame.image.close()
                presenter.presented(1_000_000)
                shown.add(index to now)
            }
        }
        now += 1_000_000L
    }
    presenter.clear()
    check(shown.size >= 88) { "Only ${shown.size}/90 frames shown" }
    check(shown.map { it.first }.zipWithNext().all { (x, y) -> y > x })
    val steady = shown.count { it.second in (start + 500_000_000)..(start + 2_500_000_000) }
    check(steady in 58..62) { "Not camera-rate playback: $steady frames in 2s" }
    check(images.all { it.closed == 1 })

    val overflow = (0 until 20).map { Image(now + it * 33_000_000L) }
    presenter.enqueue(overflow.map(::item))
    check(overflow.count { it.closed == 1 } == 12)
    presenter.clear()
    check(overflow.all { it.closed == 1 })
    val duplicate = listOf(Image(now), Image(now))
    presenter.enqueue(duplicate.map(::item))
    presenter.clear()
    check(duplicate.all { it.closed == 1 })

    // Sensor clocks with a different origin must still advance and reset.
    val foreign = listOf(Image(1_000L), Image(33_001_000L))
    presenter.enqueue(foreign.map(::item))
    now += 500_000_000L
    presenter.poll(now)?.image?.close()
    presenter.clear()
    check(foreign.all { it.closed == 1 })
    println("PASS: ${shown.size}/90 camera frames; $steady frames/2s steady playback; timestamp pairing, curve/width/blink interpolation, gaps, model boundaries, bounded resources, duplicate rejection, clock reset")
}
