package com.example.test_face.render

import kotlin.math.exp
import kotlin.math.sqrt

/**
 * Suavizado de la pose A TASA DE PANTALLA (una instancia por [EyeModelSlot]),
 * intercalado entre [PoseInterpolator] y el `ModelNode`: en cada vsync
 * persigue la pose que predice el interpolador en vez de escribirla tal cual.
 *
 * ## Qué arregla
 *
 * El interpolador extrapola desde las 3 últimas muestras de MediaPipe. Entre
 * muestra y muestra el resultado es continuo y suave, pero cuando llega una
 * muestra nueva la BASE de la predicción cambia de golpe: la pose salta de
 * "donde la predicción anterior creía que iba a estar la cara" a "donde la
 * medición nueva dice que está". Ese salto es exactamente el error de
 * predicción del intervalo anterior, y ocurre a la tasa de MediaPipe
 * (~20-30 Hz).
 *
 * Con la cabeza quieta el error es diminuto y no se ve. Con la cabeza en
 * movimiento el error crece con la aceleración, y el resultado es una pestaña
 * que avanza suave y da un tironcito ~25 veces por segundo — se percibe como
 * que "no sigue fluido" al ojo, aunque la posición promedio sea correcta.
 * Ninguna mejora del predictor lo elimina: el salto ES la corrección del
 * predictor, y solo desaparece si esa corrección se reparte en el tiempo en
 * vez de aplicarse en un frame.
 *
 * Eso hace esta clase: un pasabajos exponencial de primer orden por
 * componente, evaluado en cada vsync, que reparte cada corrección a lo largo
 * de [RendererConfiguration.POSE_FOLLOW_TAU_NANOS]. La pose que llega al nodo
 * pasa a ser continua (sin escalones) a costa de un retardo de grupo de
 * ≈ tau.
 *
 * ## Por qué el retardo no se paga
 *
 * Ese retardo de ≈ tau es CONOCIDO y constante, así que se compensa por
 * adelantado: [LashRenderer] le pide al interpolador la pose de
 * `ahora + latencia + tau` en vez de `ahora + latencia` (ver
 * [RendererConfiguration.POSE_FOLLOW_TAU_NANOS]). El seguidor la retrasa tau
 * y las dos cosas se cancelan — la pose que se dibuja sigue siendo la de
 * "ahora", pero llega por un camino continuo en vez de a escalones.
 *
 * ## Por qué exponencial y no One Euro
 *
 * [EyeTrackingFilter] ya limpia el ruido de MediaPipe aguas arriba, a la tasa
 * de MediaPipe; acá no queda ruido que quitar. Lo único que hay que hacer es
 * repartir escalones, y para eso un pasabajos de tau FIJO es lo correcto:
 * justamente porque su retardo es constante y predecible se lo puede
 * cancelar con el lead de arriba. Un corte adaptativo (One Euro) tendría un
 * retardo que cambia con la velocidad, o sea imposible de compensar sin
 * reintroducir el error que se quiere quitar.
 *
 * `alpha = 1 − e^(−dt/tau)` y no una constante: los vsync no son
 * perfectamente regulares (60/90/120 Hz, jank) y un alpha fijo daría un tau
 * efectivo distinto según el dispositivo y el momento.
 *
 * Se usa SOLO desde el hilo principal (el `Choreographer` de
 * [LashRenderer.writeInterpolatedPose] y el `post` de `showSlot`), así que no
 * necesita `@Volatile` ni sincronización.
 */
class PoseFollower {

    private var initialized = false
    private var lastNanos = 0L

    var posX = 0f; private set
    var posY = 0f; private set
    var posZ = 0f; private set

    var rotX = 0f; private set
    var rotY = 0f; private set
    var rotZ = 0f; private set
    var rotW = 1f; private set

    var scaleX = 1f; private set
    var scaleY = 1f; private set
    var scaleZ = 1f; private set

    /** Descarta el estado: el próximo [advance] salta directo a la pose
     * objetivo en vez de acercarse a ella. Se llama al mostrar la pestaña
     * tras haber estado oculta y al perder el rostro — en los dos casos, ir
     * "deslizándose" desde la pose vieja sería justo lo que no se quiere. */
    fun reset() {
        initialized = false
        lastNanos = 0L
    }

    /**
     * Acerca la pose actual a [target] lo que corresponda al tiempo
     * transcurrido desde el vsync anterior. [target] tiene que venir ya
     * validada como finita (ver [LashRenderer.writeInterpolatedPose]): un
     * NaN acá se quedaría en el estado del filtro para siempre.
     */
    fun advance(target: EyeTransform, nowNanos: Long) {
        val dtNanos = nowNanos - lastNanos
        // Hueco grande = pestaña oculta un rato, app en background o primer
        // frame: perseguir desde la pose vieja no tiene sentido, se salta.
        if (!initialized || dtNanos <= 0L ||
            dtNanos > RendererConfiguration.POSE_FOLLOW_MAX_GAP_NANOS
        ) {
            snapTo(target, nowNanos)
            return
        }

        val tau = RendererConfiguration.POSE_FOLLOW_TAU_NANOS.toFloat()
        val a = if (tau <= 0f) 1f else 1f - exp(-dtNanos.toFloat() / tau)
        lastNanos = nowNanos

        val t = target.position
        posX += (t.x - posX) * a
        posY += (t.y - posY) * a
        posZ += (t.z - posZ) * a

        val s = target.scale
        scaleX += (s.x - scaleX) * a
        scaleY += (s.y - scaleY) * a
        scaleZ += (s.z - scaleZ) * a

        // Alineación antipodal antes de mezclar: `q` y `−q` son la misma
        // rotación, pero interpolar entre ellas pasa "por el otro lado" y da
        // un giro completo espurio (mismo cuidado que [EyeTrackingFilter] y
        // [PoseInterpolator] tienen aguas arriba).
        val r = target.rotation
        val dot = rotX * r.x + rotY * r.y + rotZ * r.z + rotW * r.w
        val sign = if (dot < 0f) -1f else 1f
        rotX += (r.x * sign - rotX) * a
        rotY += (r.y * sign - rotY) * a
        rotZ += (r.z * sign - rotZ) * a
        rotW += (r.w * sign - rotW) * a

        // Mezclar componente a componente acorta el cuaternión (nlerp): sin
        // renormalizar, el error se acumula frame a frame y termina
        // deformando el modelo, no solo rotándolo.
        val lenSq = rotX * rotX + rotY * rotY + rotZ * rotZ + rotW * rotW
        if (lenSq > 1e-12f && lenSq.isFinite()) {
            val inv = 1f / sqrt(lenSq)
            rotX *= inv; rotY *= inv; rotZ *= inv; rotW *= inv
        } else {
            snapTo(target, nowNanos)
        }
    }

    private fun snapTo(target: EyeTransform, nowNanos: Long) {
        val t = target.position
        posX = t.x; posY = t.y; posZ = t.z
        val r = target.rotation
        rotX = r.x; rotY = r.y; rotZ = r.z; rotW = r.w
        val s = target.scale
        scaleX = s.x; scaleY = s.y; scaleZ = s.z
        lastNanos = nowNanos
        initialized = true
    }
}
