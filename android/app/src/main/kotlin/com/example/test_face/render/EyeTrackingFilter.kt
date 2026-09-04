package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.PI
import kotlin.math.sqrt

private const val TWO_PI = 2f * PI.toFloat()

/**
 * Suavizado temporal de UN ojo: un [OneEuroFilter] independiente por
 * componente de posición/rotación/escala.
 *
 * **Optimizado para latencia mínima (nivel TikTok)**:
 * - `minCutoff` alto en posición para que el filtro apenas suavice en reposo
 *   (preferimos velocidad sobre estabilidad — el jitter residual es menor
 *   que el lag que un filtro más agresivo introduciría).
 * - Alineación antipodal de quaterniones para evitar glitches de rotación.
 */
class EyeTrackingFilter {
    private val posX = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val posY = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val posZ = OneEuroFilter(RendererConfiguration.POSITION_MIN_CUTOFF, RendererConfiguration.POSITION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    private val rotX = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotY = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotZ = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val rotW = OneEuroFilter(RendererConfiguration.ROTATION_MIN_CUTOFF, RendererConfiguration.ROTATION_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    private val scaleX = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val scaleY = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)
    private val scaleZ = OneEuroFilter(RendererConfiguration.SCALE_MIN_CUTOFF, RendererConfiguration.SCALE_BETA, RendererConfiguration.ONE_EURO_D_CUTOFF)

    /** Último quaternion alineado, referencia para el próximo frame. */
    private var lastAlignedQ = Quaternion(0f, 0f, 0f, 1f)

    /**
     * Retardo que este filtro está introduciendo AHORA en la posición, en
     * nanosegundos — `τ = 1/(2π·fc)` promediado sobre los tres ejes, con el
     * corte efectivo del último frame (ver [OneEuroFilter.lastCutoffHz]).
     *
     * ## Por qué se expone
     *
     * Era el tramo FALTANTE del presupuesto de latencia. `measuredLatencyNanos`
     * cubre captura→resultado de MediaPipe (+16 ms de composición), y
     * [PoseFollower] declara su propio τ — pero entre esos dos la pose pasa
     * por ESTE filtro, y su retardo no lo compensaba nadie. Con el corte de
     * reposo (1.8 Hz) son ~88 ms; moviéndose, con el corte ya abierto, bajan
     * a ~10-25 ms. Ese tramo sin compensar es exactamente el "todavía se
     * atrasa cuando me muevo".
     *
     * Es ADAPTATIVO por construcción, y eso lo hace seguro: el retardo es
     * grande justo cuando la velocidad es casi cero (donde predecir de más no
     * mueve nada) y chico cuando la persona se mueve de verdad (donde
     * predecir de más sí tendría costo). Aun así [LashRenderer] lo acota con
     * [RendererConfiguration.FILTER_DELAY_COMPENSATION_MAX_NANOS], porque el
     * horizonte de predicción también amplifica el ruido residual.
     *
     * @Volatile: se escribe en el hilo de MediaPipe ([apply]) y se lee en el
     * hilo principal (el frame loop de [LashRenderer]).
     */
    @Volatile var groupDelayNanos = 0L
        private set

    fun apply(target: EyeTransform): EyeTransform {
        val now = System.nanoTime()

        val position = Float3(
            posX.filter(target.position.x, now),
            posY.filter(target.position.y, now),
            posZ.filter(target.position.z, now),
        )

        // Alineación antipodal: q y -q son la misma rotación.
        // Sin alinear, un flip de signo de MediaPipe hace que el filtro
        // interpole "a través de cero" → glitch violento.
        val raw = target.rotation
        val aligned = alignQuaternion(raw)

        val qx = rotX.filter(aligned.x, now)
        val qy = rotY.filter(aligned.y, now)
        val qz = rotZ.filter(aligned.z, now)
        val qw = rotW.filter(aligned.w, now)
        val rotation = normalizedQuaternion(qx, qy, qz, qw)
        lastAlignedQ = rotation

        val scale = Float3(
            scaleX.filter(target.scale.x, now),
            scaleY.filter(target.scale.y, now),
            scaleZ.filter(target.scale.z, now),
        )

        // Retardo introducido por los tres filtros de posición en ESTE frame
        // — se promedia el corte, no el τ, porque el corte es la magnitud que
        // el filtro realmente ajusta (y τ es convexo en 1/fc: promediar τ le
        // daría un peso desmedido al eje más suavizado).
        val cutoffHz = (posX.lastCutoffHz + posY.lastCutoffHz + posZ.lastCutoffHz) / 3f
        groupDelayNanos = if (cutoffHz > 0.01f && cutoffHz.isFinite()) {
            (1_000_000_000f / (TWO_PI * cutoffHz)).toLong()
        } else {
            0L
        }

        // opennessRatio/lidShapeTrusted se COPIAN, no se filtran: son
        // decisiones del frame, no señales continuas de pose. Antes
        // `opennessRatio` se perdía acá (caía al default 1f = "abierto"),
        // así que todo lo que leyera la apertura aguas abajo del filtro veía
        // siempre un ojo abierto.
        return EyeTransform(
            position = position,
            rotation = rotation,
            scale = scale,
            opennessRatio = target.opennessRatio,
            lashLineCurve = target.lashLineCurve,
            eyeWidthPx = target.eyeWidthPx,
            lidShapeTrusted = target.lidShapeTrusted,
        )
    }

    fun reset() {
        posX.reset(); posY.reset(); posZ.reset()
        rotX.reset(); rotY.reset(); rotZ.reset(); rotW.reset()
        scaleX.reset(); scaleY.reset(); scaleZ.reset()
        lastAlignedQ = Quaternion(0f, 0f, 0f, 1f)
        groupDelayNanos = 0L
    }

    private fun alignQuaternion(q: Quaternion): Quaternion {
        val dot = q.x * lastAlignedQ.x + q.y * lastAlignedQ.y +
                  q.z * lastAlignedQ.z + q.w * lastAlignedQ.w
        return if (dot < 0f) Quaternion(-q.x, -q.y, -q.z, -q.w) else q
    }

    private fun normalizedQuaternion(x: Float, y: Float, z: Float, w: Float): Quaternion {
        val lengthSq = x * x + y * y + z * z + w * w
        if (lengthSq <= 0f || !lengthSq.isFinite()) return Quaternion(0f, 0f, 0f, 1f)
        val invLength = 1f / sqrt(lengthSq)
        return Quaternion(x * invLength, y * invLength, z * invLength, w * invLength)
    }
}
