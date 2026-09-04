package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Decide si la pestaña se DIBUJA o no en función de cuánto se está moviendo
 * el ojo — una por [EyeModelSlot].
 *
 * ## Qué problema resuelve
 *
 * El modelo se coloca a partir de landmarks que MediaPipe entrega con
 * latencia (~35 ms de pipeline + ~16 ms de composición, ver
 * [PoseInterpolator]). Con la cabeza quieta esa latencia no se nota; con la
 * cabeza en movimiento la predicción forward tapa una parte pero NO toda —
 * el resto es un desfase real entre dónde está el ojo y dónde se dibuja la
 * pestaña. En dispositivo eso se lee exactamente como lo describió la
 * usuaria: la pestaña "flota" al lado del ojo mientras la persona se mueve.
 *
 * Predecir mejor no elimina ese desfase (la aceleración de una cabeza no es
 * predecible más allá de unas decenas de ms — ver
 * `PoseInterpolator.MAX_EXTRAPOLATION_NANOS`). Así que en vez de mostrar una
 * pestaña mal colocada no se muestra ninguna: mientras la cara se mueve
 * rápido el nodo se oculta, y vuelve SOLO cuando el movimiento se calmó lo
 * suficiente como para que la posición sea de nuevo confiable. Es el mismo
 * criterio que ya aplica [LashRenderer.onFaceLost] cuando se pierde el
 * rostro ("mejor nada que algo flotando"), extendido al caso de movimiento.
 *
 * Efecto secundario buscado: al aparecer un rostro nuevo el gate arranca
 * CERRADO y exige [RendererConfiguration.MOTION_GATE_CALM_DWELL_NANOS] de
 * calma antes del primer dibujado, así que la pestaña ya no aparece de golpe
 * en una posición a medio converger — aparece cuando está puesta.
 *
 * ## Cómo mide "moverse"
 *
 * Tres velocidades, todas adimensionales o en unidades físicas reales, para
 * que los umbrales no dependan de la distancia a la cámara ni de la
 * resolución (mismo criterio que el freno relativo de [PoseInterpolator]):
 *
 *  - **posición**: desplazamiento por segundo medido en ANCHOS DE MODELO
 *    (`|Δpos| / (scale.x·naturalSpan)`). El ancho del modelo en mundo es
 *    proporcional al ancho real del ojo (ver [MeshEyeTransformCalculator]:
 *    `scale = anchoOjo·WIDTH_MULTIPLIER / naturalSpan`), así que la métrica
 *    vale lo mismo con la cara cerca o lejos.
 *  - **rotación**: grados por segundo entre cuaterniones consecutivos.
 *  - **escala**: fracción de cambio por segundo — es el eje que se mueve
 *    cuando la persona se acerca o se aleja de la cámara, que produce el
 *    mismo tipo de desfase que un desplazamiento lateral.
 *
 * Las tres se normalizan contra su umbral y se toma la PEOR: `score = 1`
 * significa "justo en el límite de lo mostrable" por el eje que peor esté.
 *
 * ## Por qué histéresis + permanencia (dwell)
 *
 * Con un único umbral, un movimiento sostenido cerca del límite haría
 * parpadear la pestaña varias veces por segundo — peor que el problema
 * original. Por eso oculta en `score > 1` pero solo vuelve a mostrar por
 * debajo de [RendererConfiguration.MOTION_GATE_SHOW_SCORE_RATIO], y encima
 * exige que esa calma se sostenga durante el dwell. El `score` además se
 * suaviza con ataque rápido y caída lenta
 * ([RendererConfiguration.MOTION_GATE_ATTACK] /
 * [RendererConfiguration.MOTION_GATE_RELEASE]): ocultar tarde se ve
 * (pestaña flotando), mostrar tarde no.
 *
 * [update] corre SOLO en el hilo de MediaPipe ([LashRenderer.applyTransform]);
 * [reset] puede llegar además desde el hilo principal (`CameraXManager.stop`
 * → [LashRenderer.onFaceLost]). Es el mismo reparto de hilos que
 * [EyeTrackingFilter] y se resuelve igual: sin `@Volatile`, porque lo peor
 * que puede pasar es que el hilo de MediaPipe vea el reset un frame tarde —
 * y ese frame ya no se dibuja de todos modos, la cámara se está apagando.
 */
class MotionGate {

    private var visible = false
    private var hasSample = false
    private var lastPosX = 0f
    private var lastPosY = 0f
    private var lastPosZ = 0f
    private var lastRot = Quaternion()
    private var lastScaleX = 0f
    private var lastNanos = 0L
    private var score = 0f

    /** Instante en que el `score` bajó del umbral de reaparición, o `0L` si
     * ahora mismo no está en calma. */
    private var calmSinceNanos = 0L

    fun reset() {
        visible = false
        hasSample = false
        score = 0f
        calmSinceNanos = 0L
        lastNanos = 0L
        lastScaleX = 0f
    }

    /**
     * @param transform pose YA suavizada de este resultado de MediaPipe (la
     *   misma que se empuja al [PoseInterpolator]) — se mide sobre la
     *   suavizada y no sobre la cruda para que el jitter de landmarks no
     *   cuente como movimiento de cabeza.
     * @param naturalSpan [EyeModelSlot.naturalSpan], para convertir el
     *   desplazamiento a anchos de modelo.
     * @return `true` si la pestaña debe estar visible en este frame.
     */
    fun update(transform: EyeTransform, naturalSpan: Float, nowNanos: Long): Boolean {
        val pos = transform.position
        val rot = transform.rotation
        val scaleX = transform.scale.x
        val refWidth = scaleX * naturalSpan

        // Sin referencia de tamaño no hay métrica normalizada posible: se
        // conserva el estado actual en vez de inventar un score. Solo puede
        // pasar si el .glb todavía no terminó de parsear o si la escala vino
        // degenerada — un par de frames como mucho.
        if (!refWidth.isFinite() || refWidth <= 1e-6f ||
            !pos.x.isFinite() || !pos.y.isFinite() || !pos.z.isFinite()
        ) {
            return visible
        }

        val dtNanos = nowNanos - lastNanos
        val stale = !hasSample ||
            dtNanos <= 0L ||
            dtNanos > RendererConfiguration.MOTION_GATE_MAX_SAMPLE_GAP_NANOS
        if (stale) {
            // Primera muestra, o hueco tan grande (app en background, rostro
            // perdido y redetectado) que la diferencia contra la muestra vieja
            // no describe una velocidad real. Se re-arranca CERRADO, mismo
            // criterio que al aparecer un rostro nuevo.
            remember(pos, rot, scaleX, nowNanos)
            visible = false
            score = 0f
            calmSinceNanos = 0L
            return false
        }

        val dtSeconds = dtNanos / 1_000_000_000f
        val dx = pos.x - lastPosX
        val dy = pos.y - lastPosY
        val dz = pos.z - lastPosZ
        val positionSpeed = sqrt(dx * dx + dy * dy + dz * dz) / refWidth / dtSeconds
        val rotationSpeed = angleDegrees(lastRot, rot) / dtSeconds
        val scaleSpeed = if (lastScaleX > 1e-9f) {
            abs(scaleX - lastScaleX) / lastScaleX / dtSeconds
        } else {
            0f
        }

        remember(pos, rot, scaleX, nowNanos)

        val raw = max(
            positionSpeed / RendererConfiguration.MOTION_GATE_POSITION_HIDE_SPANS_PER_SEC,
            max(
                rotationSpeed / RendererConfiguration.MOTION_GATE_ROTATION_HIDE_DEG_PER_SEC,
                scaleSpeed / RendererConfiguration.MOTION_GATE_SCALE_HIDE_FRACTION_PER_SEC,
            ),
        )
        if (!raw.isFinite()) return visible

        val alpha = if (raw > score) {
            RendererConfiguration.MOTION_GATE_ATTACK
        } else {
            RendererConfiguration.MOTION_GATE_RELEASE
        }
        score += (raw - score) * alpha

        if (visible) {
            if (score > 1f) {
                visible = false
                calmSinceNanos = 0L
            }
        } else if (score < RendererConfiguration.MOTION_GATE_SHOW_SCORE_RATIO) {
            if (calmSinceNanos == 0L) {
                calmSinceNanos = nowNanos
            } else if (nowNanos - calmSinceNanos >= RendererConfiguration.MOTION_GATE_CALM_DWELL_NANOS) {
                visible = true
            }
        } else {
            calmSinceNanos = 0L
        }
        return visible
    }

    private fun remember(pos: Float3, rot: Quaternion, scaleX: Float, nowNanos: Long) {
        lastPosX = pos.x
        lastPosY = pos.y
        lastPosZ = pos.z
        lastRot = rot
        lastScaleX = scaleX
        lastNanos = nowNanos
        hasSample = true
    }

    /** Ángulo mínimo entre dos orientaciones, en grados. `|dot|` y no `dot`
     * porque `q` y `-q` son LA MISMA rotación: sin el valor absoluto, un
     * cambio de signo del cuaternión — que el suavizado puede producir sin
     * que la cabeza se haya movido — daría 180° y ocultaría la pestaña. */
    private fun angleDegrees(a: Quaternion, b: Quaternion): Float {
        val dot = abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
        if (!dot.isFinite()) return 0f
        return Math.toDegrees((2f * acos(dot.coerceIn(0f, 1f))).toDouble()).toFloat()
    }
}
