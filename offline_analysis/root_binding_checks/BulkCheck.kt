package com.example.test_face.render

import dev.romainguy.kotlin.math.*
import io.github.sceneview.geometries.Geometry
import java.io.File
import java.nio.*

fun main(args: Array<String>) {
    var checked = 0L
    for (file in File(args[0]).listFiles()!!.filter { it.extension == "bin" }) {
        val bytes = ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        val vertices = List(bytes.remaining() / 12) { Geometry.Vertex(Float3(bytes.float, bytes.float, bytes.float)) }
        val raw = RawMesh(vertices, vertices.minOf { it.position.x }, vertices.maxOf { it.position.x }, vertices.minOf { it.position.y })
        val depths = LashRootDepth.perVertex(raw)
        val n = vertices.size
        fun buffer(size: Int) = ByteBuffer.allocateDirect(size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        val direct = buffer(n * 3)
        val bulk = buffer(n * 3)
        val directTan = buffer(n * 4)
        val bulkTan = buffer(n * 4)
        val previous = buffer(n * 3)
        for (i in 0 until n * 3) previous.put(i, (i % 101 - 50) * 0.01f)
        val rest = FloatArray(n * 4) { if (it % 4 == 3) 1f else (it % 7) * 0.01f }
        val scratch = LashMeshScratch()
        for (closure in listOf(0f, 0.4f, 1f)) for (smoothing in listOf(1f, 0.3f)) for (bind in listOf(false, true)) {
            val q = Quaternion(0f, 0f, 0f, 1f)
            val scale = Float3(0.1f, 0.155f, 0.1f)
            val pos = Float3(0f, 0f, -2f)
            val drop = LidDropRotation.apply(closure, raw.minY, scale.y, q)
            val world = (0..7).map {
                val x = it / 7f * 2 - 1
                Float3(-0.15f + 0.3f * it / 7, 0.02f + (if (closure == 0f) -0.04f else 0.02f) * (1 - x * x), -2f)
            }
            val binding = if (bind) LashRootBinding.fromWorld(world, pos + (drop?.positionDelta ?: Float3()), drop?.rotation ?: q, scale, raw.minX, raw.maxX) else null
            val curve = LashLineCurve.fit(listOf(ImagePoint(-50f, 0f), ImagePoint(0f, -8f), ImagePoint(50f, 0f)), ImagePoint(0f, 0f), ImagePoint(1f, 0f))!!
            val angle = LidDropRotation.angleRadians(closure, q)
            fun bend(target: FloatBuffer, tangent: FloatBuffer, staging: LashMeshScratch?) =
                LashMeshBender.bendInPlace(raw, target, previous, rest, tangent, smoothing, curve, LashStyleConfig(foxyLiftMultiplier = 1f), 100f,
                    rootDepths = depths, dropRadians = angle, rootBinding = binding, scratch = staging)
            direct.position(2)
            bulk.position(2)
            directTan.position(3)
            bulkTan.position(3)
            check(bend(direct, directTan, null))
            check(bend(bulk, bulkTan, scratch))
            check(direct.position() == bulk.position() && directTan.position() == bulkTan.position())
            for (i in 0 until n * 3) check(direct.get(i).toRawBits() == bulk.get(i).toRawBits()) { "Position changed: ${file.name} $i" }
            for (i in 0 until n * 4) check(directTan.get(i).toRawBits() == bulkTan.get(i).toRawBits()) { "Tangent changed: ${file.name} $i" }
            val oldPositions = scratch.positions
            val oldTangents = scratch.tangents
            scratch.prepare(n)
            check(scratch.positions === oldPositions && scratch.tangents === oldTangents)
            checked += n * 7L
        }
        scratch.clear()
        check(scratch.positions.isEmpty() && scratch.tangents.isEmpty())
    }
    println("PASS: $checked position/tangent floats bit-identical on all 12 GLBs, open/closed, root binding and smoothing on/off; buffer cursors and scratch reuse preserved")
}
