package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.sin

private fun buffer(count: Int) = ByteBuffer.allocateDirect(count * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

fun main() {
    val n = 2500
    val vertices = (0 until n).map { i ->
        val x = -1.5f + 3f * i / (n - 1)
        Geometry.Vertex(Float3(x, sin(i.toFloat()) * 0.2f, 0.1f))
    }
    val raw = RawMesh(vertices, -1.5f, 1.5f)
    val rest = FloatArray(n * 4) { i -> if (i % 4 == 3) 1f else 0f }
    val exact = buffer(n * 3)
    val fast = buffer(n * 3)
    val exactTangent = buffer(n * 4)
    val fastTangent = buffer(n * 4)
    val lookup = LashDeformationLookup()
    var worstPixelError = 0f
    var worstTangentError = 0f
    for (width in listOf(20f, 46f, 100f, 200f)) {
        for (amplitude in listOf(-10f, -3f, 0f, 3f, 10f)) {
            for (band in listOf(-2.5f, -0.8f, 0f, 1f, 2.5f)) {
                val points = (0..6).map { i ->
                    val x = (i / 6f - 0.5f) * width * 0.85f
                    ImagePoint(x, amplitude * (1f - (x / (width * 0.425f)) * (x / (width * 0.425f))))
                }
                val curve = LashLineCurve.fit(points, ImagePoint(0f, 0f), ImagePoint(1f, 0f))!!.withDeviationScale(band)
                val style = LashStyleConfig(foxyLiftMultiplier = 0.5f)
                check(LashMeshBender.bendInPlace(raw, exact, null, rest, exactTangent, 1f, curve, style, width))
                check(LashMeshBender.bendInPlace(raw, fast, null, rest, fastTangent, 1f, curve, style, width, lookup = lookup))
                val units = 3f / width / (RendererConfiguration.WIDTH_MULTIPLIER * RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER)
                for (i in 0 until n * 3) worstPixelError = maxOf(worstPixelError, abs(exact[i] - fast[i]) / units)
                for (i in 0 until n * 4) worstTangentError = maxOf(worstTangentError, abs(exactTangent[i] - fastTangent[i]))
            }
        }
    }
    check(worstPixelError < 0.05f) { "Position error $worstPixelError px" }
    check(worstTangentError < 0.001f) { "Tangent error $worstTangentError" }
    lookup.clear()
    check(lookup.indices.isEmpty())
    println("PASS: 100 deformation cases x 2500 vertices; worst position error=$worstPixelError px; tangent error=$worstTangentError; cache reset")
}
