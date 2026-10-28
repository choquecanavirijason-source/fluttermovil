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

    /**
     * [tNanos] es el instante de CAPTURA del frame, no el de llegada del
     * resultado. El One Euro deriva la velocidad como `Δx/Δt` y con ella
     * abre o cierra el corte; con la hora de llegada, `Δt` arrastra el
     * jitter de la inferencia (20-60 ms según el frame) y una cabeza que se
     * mueve a velocidad constante parecía acelerar y frenar — el corte
     * oscilaba y la pestaña temblaba justo en movimiento. Entre capturas el
     * intervalo es el real de la cámara.
     *
     * [naturalSpan] es el ancho del modelo en su espacio local (ver
     * [EyeModelSlot.naturalSpan]); con él, `scale.x·naturalSpan` es el ancho
     * del modelo en MUNDO, proporcional al ancho real del ojo. La velocidad
     * de posición se mide en esa unidad — anchos de ojo por segundo — y la
     * de escala en fracción de sí misma por segundo. Antes se medía en
     * unidades crudas de mundo y `beta` estaba calibrado para "1 m/s": las
     * unidades de Filament acá no son metros fiables (la profundidad sale
     * acotada de la matriz de MediaPipe), y un giro de cabeza normal quedaba
     * muy por debajo de esa referencia. El corte casi no se abría al ARRANCAR
     * el movimiento, la pestaña se quedaba atrás y después alcanzaba de
     * golpe. `0f` o un valor no válido = velocidad cruda (comportamiento
     * anterior).
     */
    fun apply(target: EyeTransform, tNanos: Long = System.nanoTime(), naturalSpan: Float = 0f): EyeTransform {
        val now = tNanos

        // `euro_pos_ref`/`euro_rot_ref` (perf_flags, en caliente): β se
        // calculó para la referencia de RendererConfiguration; con otra
        // referencia `r` el β equivalente es β·(ref_default/r). Se aplica
        // como factor sobre la velocidad — `beta·|v|·speedScale` — que es
        // exactamente lo mismo sin rehacer los filtros. Con los defaults el
        // factor es 1.
        val flags = com.example.test_face.PerfFlags.config
        val positionRefRatio = RendererConfiguration.FAST_MOTION_POSITION_SPANS_PER_SEC / flags.euroPosRef
        val rotationRefRatio = RendererConfiguration.FAST_MOTION_ROTATION_VELOCITY / flags.euroRotRef

        val widthWorld = target.scale.x * naturalSpan
        val positionSpeedScale =
            (if (widthWorld > 1e-6f && widthWorld.isFinite()) 1f / widthWorld else 1f) * positionRefRatio
        val position = Float3(
            posX.filter(target.position.x, now, positionSpeedScale),
            posY.filter(target.position.y, now, positionSpeedScale),
            posZ.filter(target.position.z, now, positionSpeedScale),
        )

        // Alineación antipodal: q y -q son la misma rotación.
        // Sin alinear, un flip de signo de MediaPipe hace que el filtro
        // interpole "a través de cero" → glitch violento.
        val raw = target.rotation
        val aligned = alignQuaternion(raw)

        val qx = rotX.filter(aligned.x, now, rotationRefRatio)
        val qy = rotY.filter(aligned.y, now, rotationRefRatio)
        val qz = rotZ.filter(aligned.z, now, rotationRefRatio)
        val qw = rotW.filter(aligned.w, now, rotationRefRatio)
        val rotation = normalizedQuaternion(qx, qy, qz, qw)
        lastAlignedQ = rotation

        val sx = target.scale.x
        val scaleSpeedScale = if (naturalSpan > 0f && sx > 1e-6f && sx.isFinite()) 1f / sx else 1f
        val scale = Float3(
            scaleX.filter(target.scale.x, now, scaleSpeedScale),
            scaleY.filter(target.scale.y, now, scaleSpeedScale),
            scaleZ.filter(target.scale.z, now, scaleSpeedScale),
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
            normalizedOpenness = target.normalizedOpenness,
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
