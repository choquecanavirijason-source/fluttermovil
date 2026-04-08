package com.example.test_face

import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

object EyeTrackingResultMapper {

    private val leftEyeIdx = listOf(33, 133, 160, 159, 158, 144, 145, 153)
    private val rightEyeIdx = listOf(362, 263, 387, 386, 385, 373, 374, 380)

    private val leftIrisIdx = listOf(468, 469, 470, 471, 472)
    private val rightIrisIdx = listOf(473, 474, 475, 476, 477)

    /** Contorno facial (óvalo), índices alineados con Face Landmarker. */
    private val faceOvalIdx =
        listOf(
            10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
            152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109
        )

    fun map(result: FaceLandmarkerResult, width: Int, height: Int): Map<String, Any?> {
        if (result.faceLandmarks().isEmpty()) {
            return mapOf(
                "faceDetected" to false,
                "imageWidth" to width,
                "imageHeight" to height,
                "leftEye" to emptyList<Map<String, Double>>(),
                "rightEye" to emptyList<Map<String, Double>>(),
                "leftIris" to null,
                "rightIris" to null,
                "faceContour" to emptyList<Map<String, Double>>()
            )
        }

        val landmarks = result.faceLandmarks()[0]

        fun point(index: Int): Map<String, Double> {
            val p = landmarks[index]
            return mapOf(
                "x" to (p.x() * width).toDouble(),
                "y" to (p.y() * height).toDouble()
            )
        }

        fun maybeCenter(indices: List<Int>): Map<String, Double>? {
            val valid = indices.filter { it < landmarks.size }
            if (valid.isEmpty()) return null

            val xs = valid.map { landmarks[it].x() * width }
            val ys = valid.map { landmarks[it].y() * height }

            return mapOf(
                "x" to xs.average(),
                "y" to ys.average()
            )
        }

        return mapOf(
            "faceDetected" to true,
            "imageWidth" to width,
            "imageHeight" to height,
            "leftEye" to leftEyeIdx.filter { it < landmarks.size }.map { point(it) },
            "rightEye" to rightEyeIdx.filter { it < landmarks.size }.map { point(it) },
            "leftIris" to maybeCenter(leftIrisIdx),
            "rightIris" to maybeCenter(rightIrisIdx),
            "faceContour" to faceOvalIdx.filter { it < landmarks.size }.map { point(it) }
        )
    }
}