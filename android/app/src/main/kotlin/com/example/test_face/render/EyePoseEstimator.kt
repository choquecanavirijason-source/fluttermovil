package com.example.test_face.render

import android.util.Log
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import dev.romainguy.kotlin.math.Mat4
import dev.romainguy.kotlin.math.Quaternion
import dev.romainguy.kotlin.math.normalize

/**
 * Pose 3D completa de la cabeza, ya convertida al espacio de mundo que usa
 * Filament/SceneView en este proyecto.
 *
 * [position] hoy solo se usa en Z (profundidad dinámica, ver
 * [EyeTransformCalculator]) — X/Y quedan calculados y disponibles para
 * features futuras ancladas a la cabeza completa (gafas, máscara facial),
 * ya que la posición de cada ojo se deriva de sus propios landmarks 2D, no
 * de la posición global de la cabeza.
 */
data class HeadPose(
    val position: Float3,
    val rotation: Quaternion,
    val right: Float3,
    val up: Float3,
    val forward: Float3,
)

/**
 * Convierte la matriz de transformación facial que entrega MediaPipe
 * (`FaceLandmarkerResult.facialTransformationMatrixes()`) — pose 3D completa
 * de la cabeza, resuelta por MediaPipe ajustando su modelo facial canónico —
 * al espacio de mundo de Filament. Esto reemplaza cualquier cálculo manual
 * de yaw/pitch/roll a partir de dos landmarks: la rotación completa (3 ejes)
 * y la profundidad ya vienen resueltas por el propio MediaPipe.
 *
 * MediaPipe documenta esta matriz en orden **row-major**. La cámara frontal
 * se usa espejada (ver `CameraXManager.processFrame`, `postScale(-1f, ...)`),
 * así que aquí también se invierte el eje X para quedar consistente con los
 * landmarks 2D que ya consume el resto del pipeline.
 *
 * NOTA DE CALIBRACIÓN (ver plan): los signos de esta conversión están
 * implementados según la convención documentada de MediaPipe Face Geometry,
 * pero la convención row/column-major de `facialTransformationMatrixes()` no
 * se puede verificar sin correr en un dispositivo real. Con [DEBUG_LOG_POSE]
 * activo, mover la cabeza en yaw/pitch/roll por separado y comparar el signo
 * logueado contra el movimiento real: si no coincide, la lectura es
 * column-major y hay que transponer `m(r,c)` a `matrix[c*4+r]`.
 */
object EyePoseEstimator {

    /** Activo por defecto hasta la primera verificación en dispositivo (Fase 0 del plan). */
    const val DEBUG_LOG_POSE = true

    private const val TAG = "EyePoseEstimator"

    fun fromMediaPipeMatrix(matrix: FloatArray): HeadPose? {
        if (matrix.size != 16) return null

        // Lectura row-major: fila r, columna c → matrix[r * 4 + c].
        fun m(r: Int, c: Int) = matrix[r * 4 + c]

        val mpPosition = Float3(m(0, 3), m(1, 3), m(2, 3))
        val mpRight = Float3(m(0, 0), m(1, 0), m(2, 0))
        val mpUp = Float3(m(0, 1), m(1, 1), m(2, 1))
        val mpForward = Float3(m(0, 2), m(1, 2), m(2, 2))

        // Espejado correcto de una ROTACIÓN (a diferencia de un punto) es una
        // CONJUGACIÓN por el espejo F=diag(-1,1,1): R' = F·R·F, no solo negar
        // la componente X de cada columna. Para una columna cuyo índice es el
        // propio eje X ("right"), la conjugación mantiene su componente X y
        // niega Y/Z; para columnas que NO son el eje X ("up"/"forward"),
        // niega solo su componente X. La versión anterior negaba la X de las
        // 3 columnas por igual — matemáticamente eso es F·R (no F·R·F): una
        // reflexión (determinante -1), no una rotación propia, lo que hacía
        // que `toQuaternion()` devolviera una orientación con el yaw
        // invertido (ver auditoría, Hallazgo #2). Verificado a mano con
        // R=RotY(θ): F·R·F da RotY(-θ) (correcto, un giro se ve invertido en
        // el espejo); la fórmula anterior daba -RotY(-θ), una matriz sin
        // determinante +1.
        val position = Float3(
            -mpPosition.x * RendererConfiguration.FACE_DISTANCE_MULTIPLIER,
            mpPosition.y * RendererConfiguration.FACE_DISTANCE_MULTIPLIER,
            mpPosition.z * RendererConfiguration.FACE_DISTANCE_MULTIPLIER,
        )
        val right = normalize(Float3(mpRight.x, -mpRight.y, -mpRight.z))
        val up = normalize(Float3(-mpUp.x, mpUp.y, mpUp.z))
        val forward = normalize(Float3(-mpForward.x, mpForward.y, mpForward.z))

        val rotationMatrix = Mat4(
            Float4(right, 0f),
            Float4(up, 0f),
            Float4(forward, 0f),
            Float4(0f, 0f, 0f, 1f),
        )
        val rotation = rotationMatrix.toQuaternion()

        if (DEBUG_LOG_POSE) {
            Log.d(TAG, "headPose pos=$position euler(deg)=${rotation.toEulerAngles()}")
        }

        return HeadPose(position = position, rotation = rotation, right = right, up = up, forward = forward)
    }

    /**
     * Pose neutra (sin rotación, profundidad por defecto) para cuando
     * `facialTransformationMatrixes()` no está disponible — evita que todo el
     * anclaje de pestañas dependa de una única capacidad de MediaPipe: con
     * esto, [EyeAnchorCalculator]/[EyePlaneCalculator] siguen posicionando y
     * orientando el modelo a partir de los landmarks 2D (siempre disponibles
     * cuando hay rostro detectado), igual que antes de activar la pose 3D
     * completa — solo se pierde la profundidad dinámica y la corrección de
     * escorzo por rotación real de cabeza, no el anclaje en sí.
     */
    fun fallback(): HeadPose = HeadPose(
        position = Float3(0f, 0f, -1f),
        rotation = Quaternion(0f, 0f, 0f, 1f),
        right = Float3(1f, 0f, 0f),
        up = Float3(0f, 1f, 0f),
        forward = Float3(0f, 0f, 1f),
    )
}
