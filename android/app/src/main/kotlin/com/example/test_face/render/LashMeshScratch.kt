package com.example.test_face.render

/** Reusable heap staging for two bulk writes into the existing GPU buffers.
 * No vertex arithmetic, pose, upload ownership or presentation timing changes. */
class LashMeshScratch {
    var positions = FloatArray(0)
        private set
    var tangents = FloatArray(0)
        private set

    fun prepare(vertexCount: Int) {
        if (positions.size != vertexCount * 3) positions = FloatArray(vertexCount * 3)
        if (tangents.size != vertexCount * 4) tangents = FloatArray(vertexCount * 4)
    }

    fun clear() {
        positions = FloatArray(0)
        tangents = FloatArray(0)
    }
}
