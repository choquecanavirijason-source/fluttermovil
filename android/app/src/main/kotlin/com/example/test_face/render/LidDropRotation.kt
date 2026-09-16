package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Hace que la pestaña GIRE HACIA ABAJO cuando el ojo se cierra, en vez de
 * quedarse apuntando hacia la ceja como si el párpado siguiera abierto.
 *
 * ## Qué imita
 *
 * La pestaña no se mueve por su cuenta: va montada en el borde del párpado
 * superior, y ese borde rota alrededor del eje canto-a-canto del ojo (el
 * mismo eje `right` de [EyePlane]) a medida que el párpado baja sobre el
 * globo ocular.
 *
 *  - Ojo ABIERTO: el borde está arriba, replegado, y las fibras salen hacia
 *    arriba y un poco hacia adelante.
 *  - Ojo CERRADO: el borde bajó hasta el fondo de la abertura y la
 *    superficie del párpado quedó mirando al frente; las fibras salen hacia
 *    ABAJO y hacia adelante, que es la foto clásica de "ojos cerrados" en la
 *    que se luce una extensión.
 *
 * El recorrido de la dirección de la fibra entre esos dos extremos pasa por
 * "adelante" — de ahí que el ángulo por defecto sea bastante mayor que 90°
 * (ver [RendererConfiguration.LASH_CLOSED_DROP_DEGREES]): con menos, la
 * pestaña se queda apuntando a la cámara en vez de terminar de caer.
 *
 * Hasta ahora el parpadeo no movía la pestaña en absoluto: el ancla la
 * seguía bajando con el párpado (eso ya lo daban los landmarks), pero la
 * ORIENTACIÓN se quedaba fija, así que con el ojo cerrado la pestaña
 * apuntaba hacia arriba atravesando el párpado.
 *
 * ## Por qué se aplica acá y no en el cálculo de la transformación
 *
 * Podría haberse metido en [EyeTransformCalculator], pero entonces el giro
 * pasaría por [PoseInterpolator], que EXTRAPOLA hacia adelante. Un parpadeo
 * es el movimiento más rápido y menos predecible de toda la cara: extrapolar
 * ~100 ms de un giro de ~110° manda la pestaña muy por delante del párpado y
 * después la trae de vuelta. La pose rígida sí se predice (la cabeza tiene
 * inercia); el parpadeo NO — se aplica al final, sobre la pose ya resuelta,
 * suavizado por [PoseFollower] pero nunca extrapolado.
 *
 * ## El pivote es la RAÍZ, no el origen del modelo
 *
 * El origen del `.glb` no coincide con la raíz visual del abanico: por eso
 * [EyeTransformCalculator] desplaza la posición final `−up·(scaleY·rootLocalY)`,
 * para que sea la RAÍZ la que caiga sobre el ancla. Si se rotara el nodo sin
 * más, ese desplazamiento quedaría calculado con el `up` viejo y la raíz se
 * despegaría del párpado — la pestaña giraría bien pero "volando". Por eso
 * [apply] devuelve TAMBIÉN la corrección de posición que mantiene la raíz
 * clavada donde estaba.
 */
object LidDropRotation {

    /** Rotación y corrección de posición para un frame. [positionDelta] hay
     * que SUMARLO a la posición que venía de la pose. */
    data class Result(val rotation: Quaternion, val positionDelta: Float3)

    /**
     * @param closedAmount 0 = ojo abierto (sin giro), 1 = cerrado (giro
     *   completo). Ya suavizado — ver [PoseFollower.closedAmount].
     * @param rootLocalY [EyeModelSlot.rootLocalY], en unidades locales del
     *   `.glb`.
     * @param scaleY escala Y aplicada al nodo, la misma con la que
     *   [EyeTransformCalculator] calculó el desplazamiento de raíz.
     * @param q orientación de la pose, ya resuelta y suavizada.
     */
    fun apply(closedAmount: Float, rootLocalY: Float, scaleY: Float, q: Quaternion): Result? {
        if (!RendererConfiguration.LASH_CLOSED_DROP_ENABLED) return null
        val drop = dropAmount(closedAmount)
        if (drop <= 1e-3f) return null

        // SENTIDO DEL GIRO. Rotar alrededor del eje X local (= `right`, el
        // eje canto-a-canto) por un ángulo POSITIVO lleva el +Y local (la
        // dirección en la que salen las fibras) hacia el +Z local (la normal
        // del párpado). Pero la normal de MediaPipe puede apuntar hacia la
        // cámara o hacia adentro de la cabeza según la pose, así que un signo
        // fijo haría que la pestaña cayera hacia adelante en una pose y se
        // hundiera en la cara en la otra.
        //
        // Se elige el sentido que la lleva hacia la CÁMARA — que en el mundo
        // de Filament, con la cámara mirando por −Z, es +Z de mundo. Es
        // exactamente el mismo criterio (y el mismo test) que usa
        // [EyePlaneCalculator] para `signedTilt`, solo que resuelto desde el
        // cuaternión en vez de desde `headPose`: la componente Z del +Z local
        // llevado a mundo es `1 − 2(x² + y²)`.
        val localZTowardCameraness = 1f - 2f * (q.x * q.x + q.y * q.y)
        val sign = if (localZTowardCameraness >= 0f) 1f else -1f

        val degrees = RendererConfiguration.LASH_CLOSED_DROP_DEGREES * drop * sign
        val theta = Math.toRadians(degrees.toDouble()).toFloat()
        val half = theta * 0.5f
        val dropQuat = Quaternion(sin(half), 0f, 0f, cos(half))

        // La rotación de caída va a la DERECHA: es una rotación en el espacio
        // LOCAL del modelo (alrededor de su propio eje X), no del mundo.
        // Invertir el orden rotaría alrededor del eje X del MUNDO y la
        // pestaña se iría de lado en cuanto la cabeza se inclinara.
        val rotation = q * dropQuat

        // Corrección de pivote — ver el KDoc de la clase. La raíz está a
        // `up·(scaleY·rootLocalY)` del origen, así que al cambiar `up` por
        // `up'` el origen tiene que moverse `(up − up')·(scaleY·rootLocalY)`
        // para que la raíz no se mueva. Con `up  = R(q)·(0,1,0)` y
        // `up' = R(q)·(0,cosθ,sinθ)`, la diferencia es
        // `R(q)·(0, 1−cosθ, −sinθ)` — un solo giro de vector, sin
        // reconstruir ninguna base.
        val s = scaleY * rootLocalY
        val delta = if (s == 0f) {
            Float3(0f, 0f, 0f)
        } else {
            rotateVector(q, 0f, 1f - cos(theta), -sin(theta)) * s
        }
        return Result(rotation, delta)
    }

    /**
     * Curva de respuesta del giro: del cierre MEDIDO (`0..1`) a la fracción
     * del volcado que se aplica. La usan [apply] y [bandCompensation], así
     * que las dos ven siempre el mismo θ — si divergieran, la malla se
     * compensaría por un giro distinto del que se aplica y la banda dejaría
     * de seguir el párpado.
     *
     * Es una recta con ganancia y tope, no una identidad, porque el cierre
     * medido rara vez llega a 1 con el ojo ya cerrado — ver
     * [RendererConfiguration.LASH_CLOSED_DROP_GAIN].
     */
    fun dropAmount(closedAmount: Float): Float {
        if (!closedAmount.isFinite()) return 0f
        return (closedAmount * RendererConfiguration.LASH_CLOSED_DROP_GAIN).coerceIn(0f, 1f)
    }

    /**
     * Factor por el que hay que multiplicar el desvío de [LashLineCurve]
     * ANTES de doblar la malla, para que la BANDA DE RAÍCES siga apoyada en
     * el borde del párpado mientras [apply] vuelca el abanico entero.
     *
     * ## El problema que resuelve
     *
     * [apply] rota el NODO COMPLETO. Eso vuelca las fibras, que es lo que se
     * busca, pero arrastra también el arco de la línea donde nacen: un punto
     * de la banda que estaba a `h` por encima de la cuerda canto-a-canto
     * queda, tras girar θ, a `h·cos θ`. Con θ > 90° eso es NEGATIVO, así que
     * la banda se abomba para el lado contrario y deja de seguir el párpado:
     * la pestaña cae bien, pero su raíz dibuja una curva que el ojo no tiene.
     *
     * ## La compensación
     *
     * Si la malla se dobla con el desvío multiplicado por `1/cos θ`, tras la
     * rotación la banda vuelve a mostrar el desvío ORIGINAL
     * (`h·(1/cos θ)·cos θ = h`): sigue el párpado igual que con el ojo
     * abierto, y lo único que queda volcado son las fibras. Cerca de θ=90°
     * el factor se dispara (la banda queda de canto a la cámara y su arco no
     * se ve), de ahí el tope
     * [RendererConfiguration.LASH_CLOSED_BAND_COMPENSATION_MAX].
     *
     * El signo del giro no entra: `cos` es par, así que da igual hacia qué
     * lado haya resuelto la caída [apply] en este frame.
     *
     * @param closedAmount el mismo `0..1` que recibe [apply].
     */
    fun bandCompensation(closedAmount: Float): Float {
        if (!RendererConfiguration.LASH_CLOSED_DROP_ENABLED) return 1f
        if (!RendererConfiguration.LASH_CLOSED_BAND_COMPENSATION_ENABLED) return 1f
        val drop = dropAmount(closedAmount)
        if (drop <= 1e-3f) return 1f

        val degrees = RendererConfiguration.LASH_CLOSED_DROP_DEGREES * drop
        val c = cos(Math.toRadians(degrees.toDouble()).toFloat())
        // El párpado cerrado es más recto que el abierto, y la curva con la
        // que se dobla es la CONGELADA de ojo abierto: se aplana aparte.
        val flatten = 1f + (RendererConfiguration.LASH_CLOSED_BAND_FLATTEN - 1f) * drop
        val max = RendererConfiguration.LASH_CLOSED_BAND_COMPENSATION_MAX
        val raw = if (abs(c) < 1e-4f) max else (flatten / c)
        return raw.coerceIn(-max, max)
    }

    /** `R(q) · v` — fórmula estándar `v + 2w(u×v) + 2u×(u×v)` con `u` la
     * parte vectorial de [q]. */
    private fun rotateVector(q: Quaternion, vx: Float, vy: Float, vz: Float): Float3 {
        val tx = 2f * (q.y * vz - q.z * vy)
        val ty = 2f * (q.z * vx - q.x * vz)
        val tz = 2f * (q.x * vy - q.y * vx)
        return Float3(
            vx + q.w * tx + (q.y * tz - q.z * ty),
            vy + q.w * ty + (q.z * tx - q.x * tz),
            vz + q.w * tz + (q.x * ty - q.y * tx),
        )
    }
}
