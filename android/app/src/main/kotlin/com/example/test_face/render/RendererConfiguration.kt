package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3

/**
 * Parámetros del motor de render optimizados para LATENCIA MÍNIMA.
 *
 * Filosofía: el One Euro Filter SOLO debe eliminar el micro-jitter de
 * MediaPipe, sin agregar lag perceptible. La predicción forward en
 * PoseInterpolator se encarga del resto de la compensación.
 *
 * El minCutoff alto (3.0Hz) hace que el filtro sea casi transparente:
 * señales que cambian más lento que 3Hz (movimiento lento de cabeza)
 * pasan sin casi ningún suavizado → CERO lag perceptible.
 */
object RendererConfiguration {

    // ── One Euro Filter: MÍNIMO suavizado, MÁXIMA velocidad ─────────────
    //
    // Con predicción forward adaptativa, el filtro ya NO necesita compensar
    // la latencia — solo necesita limpiar el ruido de MediaPipe.
    //
    // minCutoff = 3.0Hz → τ ≈ 53ms en reposo (solo limpia jitter)
    // Target rápido = 25Hz → τ ≈ 6.4ms (sub-frame, invisible)
    //
    // Comparación con antes:
    // - Antes: minCutoff=1.0, target=12Hz → lag de ~100ms visible
    // - Ahora: minCutoff=3.0, target=25Hz → lag de ~6ms invisible
    const val ONE_EURO_D_CUTOFF = 1.0f

    private const val FAST_MOTION_TARGET_CUTOFF_HZ = 25f

    const val POSITION_MIN_CUTOFF = 3.0f
    private const val FAST_MOTION_POSITION_VELOCITY_MPS = 1.0f
    const val POSITION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - POSITION_MIN_CUTOFF) / FAST_MOTION_POSITION_VELOCITY_MPS

    const val ROTATION_MIN_CUTOFF = 2.0f
    private const val FAST_MOTION_ROTATION_VELOCITY = 1.8f
    const val ROTATION_BETA =
        (FAST_MOTION_TARGET_CUTOFF_HZ - ROTATION_MIN_CUTOFF) / FAST_MOTION_ROTATION_VELOCITY

    const val SCALE_MIN_CUTOFF = 2.0f
    private const val SCALE_TO_POSITION_BETA_RATIO = 0.05f / 0.3f
    const val SCALE_BETA = POSITION_BETA * SCALE_TO_POSITION_BETA_RATIO

    // ── Profundidad ─────────────────────────────────────────────────────
    const val MIN_DEPTH = -2.2f
    const val MAX_DEPTH = -0.35f
    const val FACE_DISTANCE_MULTIPLIER = 1.0f

    // ── Escala del modelo ───────────────────────────────────────────────
    const val WIDTH_MULTIPLIER = 1.65f
    // HEIGHT_OFFSET controla dónde queda la RAÍZ real de la pestaña 3D
    // (EyeModelSlot.rootLocalY, ver EyeTransformCalculator) respecto al
    // BORDE del párpado superior (la línea donde nace la pestaña real).
    //
    // 0.0 = raíz exactamente en el borde del párpado (valor por defecto —
    //       anatómicamente correcto: una extensión de pestañas se pega justo
    //       sobre la línea de pestañas real, sin margen)
    // >0  = raíz desplazada hacia ARRIBA esa fracción de la altura del ojo
    //       (margen de "flote"/glue visible, si hiciera falta por estética)
    //
    // IMPORTANTE (corrección 2026-07-24): antes este offset se aplicaba
    // sobre el CENTRO GEOMÉTRICO del bounding box del modelo (asumiendo que
    // el .glb estaba centrado en su raíz visual), en 0.30 — pero se verificó
    // con los 10 modelos reales de assets/modelos/ (histograma de densidad
    // de vértices en Y) que la raíz visual de cada pestaña está muy por
    // debajo del centro geométrico del bounding box, cerca de su Y mínimo.
    // Ancorar el centro (en vez de la raíz real) + este offset extra
    // empujaba la pestaña sistemáticamente hacia la ceja, en cualquier
    // ángulo de cabeza — justo el síntoma reportado con capturas reales.
    // Ahora EyeTransformCalculator ancla EyeModelSlot.rootLocalY (la raíz
    // real, medida del mesh) directamente al punto de anclaje del ojo, así
    // que este offset vuelve a tener el significado simple y literal de su
    // nombre. 0.0f es el punto de partida teóricamente correcto — falta
    // confirmar visualmente en dispositivo real (no disponible en este
    // entorno) y ajustar solo si hace falta un pequeño margen estético.
    const val HEIGHT_OFFSET = 0.0f
    const val HEAD_TILT_MULTIPLIER = 1.0f
    // Multiplicador SOLO sobre el eje Y local del modelo (además del
    // scaleFactor isotrópico que ya iguala el ancho al ojo real) — le da
    // más volumen/grosor vertical a la pestaña sin estirarla más allá de
    // las esquinas del ojo en X (que es lo que pasaría si en cambio se
    // subiera WIDTH_MULTIPLIER, porque ese escala X/Y/Z por igual). 1.0 =
    // sin cambio. Ver EyeTransformCalculator: también se usa (no solo
    // WIDTH_MULTIPLIER×scaleFactor) para el desplazamiento de rootLocalY,
    // porque ese desplazamiento es a lo largo del mismo eje Y que ahora
    // tiene esta escala extra.
    const val HEIGHT_VOLUME_MULTIPLIER = 1.4f

    // ── Corrección por ojo ──────────────────────────────────────────────
    const val RIGHT_EYE_X_NUDGE = 0.0f
    const val LEFT_EYE_X_NUDGE = 0.0f

    // Con WIDTH_MULTIPLIER=1.65 el modelo se agranda simétricamente desde
    // el centro del ojo — pero el lado interno (hacia la nariz/lagrimal)
    // tiene mucho menos espacio anatómico libre que el lado externo (hacia
    // la sien), así que esa misma expansión simétrica invade la nariz de
    // un lado y se ve bien del otro (reportado en dispositivo real,
    // 2026-07-24). NOSE_AVOID_SHIFT desplaza el ancla X, como fracción del
    // ancho del ojo, hacia el corner EXTERNO (el más lejano al centro
    // horizontal de la imagen — ver EyeAnchorCalculator) para reducir el
    // invasión del lado interno sin tocar la escala. 0.0 = sin desplazar.
    const val NOSE_AVOID_SHIFT = 0.68f

    // ── Parpadeo ────────────────────────────────────────────────────────
    const val EYE_CLOSED_OPENNESS_THRESHOLD = 0.12f
    const val EYE_OPEN_OPENNESS_THRESHOLD = 0.22f

    // ── Iluminación ─────────────────────────────────────────────────────
    const val INDIRECT_LIGHT_INTENSITY = 15000f
    const val KEY_LIGHT_INTENSITY = 100000f
    val KEY_LIGHT_COLOR = Float3(1f, 0.97f, 0.90f)
    val KEY_LIGHT_DIRECTION = Float3(-0.35f, -0.7f, -0.6f)

    // ── Calidad de render ───────────────────────────────────────────────
    const val MSAA_SAMPLE_COUNT = 4

    // ── Doblado de pestaña según curva del párpado (LashMeshBender) ──────
    // Reconstruir la malla (List<Geometry.Vertex>, 17k-85k objetos según el
    // diseño) y subirla a GPU vía geometry.setVertices() es caro: hacerlo en
    // CADA resultado de MediaPipe (~30Hz+) causó un OutOfMemoryError real en
    // dispositivo (GC bloqueando 600-850ms seguidos — ver ESTADO_ACTUAL.md
    // sección 3.4). Este intervalo limita a cuántas veces por segundo como
    // MÁXIMO se permite recalcular el doblado, independiente de la
    // frecuencia real de MediaPipe — reduce la basura generada por segundo
    // en la misma proporción. 120ms ≈ 8.3 Hz: la curva del párpado cambia
    // lento respecto al movimiento de cabeza (que ya tiene su propio
    // suavizado/predicción vía PoseInterpolator, no depende de esto), así
    // que a esta tasa no debería notarse como "atrasado", solo menos fluido
    // que 60Hz. Si en dispositivo real esto SIGUE generando presión de GC
    // visible, subir este valor (menos Hz) antes de tocar el resto —
    // primera palanca de ajuste, no hace falta tocar LashMeshBender.
    // Subido de 120ms a 220ms (2026-07-29): con el doblado REACTIVADO en
    // dispositivo real (no solo el diagnóstico) apareció lag notorio — cada
    // recalculo reconstruye una List<Geometry.Vertex> de miles de objetos y
    // la sube a GPU vía setVertices() en el hilo principal; a 8.3Hz por CADA
    // ojo (hasta ~16.6 subidas/seg combinadas) eso satura el hilo principal.
    // ~4.5Hz por ojo sigue siendo imperceptible como "atraso" (la curva del
    // párpado cambia lento respecto al movimiento de cabeza, que tiene su
    // propio suavizado vía PoseInterpolator) pero reduce el trabajo de GPU
    // upload/GC a poco más de la mitad. Ver también EyeModelSlot.bendPending,
    // que evita que se seguya encolando trabajo si el hilo principal ya va
    // atrasado.
    const val LASH_BEND_MIN_INTERVAL_NANOS = 220_000_000L

    // Multiplicador de intensidad del doblado (0 = recto, 1 = la curva
    // calculada tal cual). El ajuste de LashLineCurve, aunque matemáticamente
    // correcto (mínimos cuadrados, verificado con y sin centrado numérico —
    // el resultado no cambió), produce una desviación de magnitud mayor a
    // la que se ve bien en pantalla (confirmado en dispositivo real,
    // BEND_DIAG 2026-07-29: hasta ~1 unidad de malla de desviación sobre un
    // span de ~3, es decir hasta ~30% del ancho total del modelo). En vez
    // de seguir cazando la causa exacta de esa sobre-estimación bajo
    // presión de tiempo de entrega, se amortigua la salida a un nivel que
    // se ve bien — subir/bajar ESTE número es la primera palanca de ajuste
    // visual, no hace falta tocar LashMeshBender ni LashLineCurve para
    // afinar cuánto se curva.
    const val LASH_BEND_STRENGTH = 0.25f
}