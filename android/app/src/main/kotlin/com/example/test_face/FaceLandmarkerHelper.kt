package com.example.test_face

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import java.util.concurrent.atomic.AtomicBoolean

class FaceLandmarkerHelper(
    private val context: Context,
    /** [Map] con el contrato 2D que ya consume Flutter, el [FaceLandmarkerResult]
     * crudo (landmarks + matriz de transformación facial) para el motor de
     * render 3D nativo (ver paquete `render`), y el [Bitmap] EXACTO que
     * MediaPipe analizó para este resultado (vía [BitmapExtractor], no un
     * bitmap guardado aparte que podría no corresponder al mismo frame) —
     * lo usa [com.example.test_face.render.LashEdgeDetector] para anclar el
     * modelo 3D sobre la pestaña real visible, no solo sobre el landmark
     * estimado. `null` si el image no envuelve un Bitmap (no debería pasar
     * con [com.google.mediapipe.framework.image.BitmapImageBuilder], que es
     * como se construye en [com.example.test_face.CameraXManager]). */
    private val onResult: (Map<String, Any?>, FaceLandmarkerResult, Bitmap?) -> Unit,
    private val onError: (String) -> Unit
) {
    private var faceLandmarker: FaceLandmarker? = null

    /**
     * `true` mientras hay un frame entregado a `detectAsync` cuyo resultado
     * (o error) todavía no volvió. Ver [detectAsync] para por qué existe.
     */
    private val inferenceInFlight = AtomicBoolean(false)

    /** `uptimeMillis` en que se tomó [inferenceInFlight], para el
     * vencimiento de seguridad de [detectAsync]. */
    @Volatile private var inFlightSinceMs = 0L

    // Instancia propia del mapper para que pueda mantener estado EMA
    // entre llamadas (ver EyeTrackingResultMapper — ahora es class, no object).
    private val mapper = EyeTrackingResultMapper()

    /**
     * Intenta GPU primero: la inferencia de FaceLandmarker con
     * `outputFacialTransformationMatrixes(true)` en CPU agrega decenas de ms
     * de latencia por frame antes de que el resultado llegue al motor de
     * render — eso es retraso que ningún filtro de suavizado puede
     * compensar (ver `RendererConfiguration`, sección de suavizado
     * temporal: el filtro solo puede suavizar datos que ya llegaron). Si el
     * delegado GPU falla al inicializar en este dispositivo (poco común,
     * pero MediaPipe no lo garantiza en todo el parque Android), se cae a
     * CPU — igual que el comportamiento anterior, así que nunca se pierde
     * la capacidad de arrancar por esto.
     */
    fun setup() {
        try {
            context.assets.open(MODEL_ASSET).use { /* ensure packaged */ }
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker init failed (modelo no empaquetado)", e)
            onError(e.message ?: "No se pudo inicializar FaceLandmarker")
            return
        }

        faceLandmarker = try {
            buildLandmarker(Delegate.GPU).also { Log.i(TAG, "Delegado GPU activo (diagnóstico flote)") }
        } catch (e: Exception) {
            Log.w(TAG, "Delegado GPU no disponible en este dispositivo, fallback a CPU", e)
            try {
                buildLandmarker(Delegate.CPU)
            } catch (e2: Exception) {
                Log.e(TAG, "FaceLandmarker init failed (CPU fallback)", e2)
                onError(e2.message ?: "No se pudo inicializar FaceLandmarker")
                null
            }
        }
    }

    private fun buildLandmarker(delegate: Delegate): FaceLandmarker {
        val baseOptions = BaseOptions.builder()
            .setDelegate(delegate)
            .setModelAssetPath(MODEL_ASSET)
            .build()

        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setRunningMode(RunningMode.LIVE_STREAM)
            // Necesario para el motor de render 3D (paquete `render`): MediaPipe
            // resuelve la pose 3D completa de la cabeza (rotación + profundidad)
            // ajustando su modelo facial canónico — mucho más robusto que derivar
            // yaw/pitch/roll a mano desde dos landmarks.
            .setOutputFacialTransformationMatrixes(true)
            // Blendshapes: `eyeBlinkLeft`/`eyeBlinkRight` son la señal de
            // cierre de párpado que usa el motor de render para decidir si
            // congelar la forma de la pestaña (ver
            // [com.example.test_face.render.EyeBlinkBlendshapes]).
            //
            // POR QUÉ, y no la geometría: la alternativa era alto/ancho del
            // anillo del ojo MEDIDO EN LA IMAGEN, que depende del ÁNGULO DE
            // CÁMARA tanto como de cuánto abriste el ojo — mirando el
            // teléfono desde abajo el ojo se escorza vertical y esa relación
            // se desploma con un ojo perfectamente abierto. MediaPipe calcula
            // estos coeficientes sobre su ajuste 3D del rostro, así que ya
            // vienen sin ese escorzo.
            //
            // Cuesta una pasada extra de un modelo chico por frame (unos
            // pocos ms); a cambio saca el ángulo de cabeza de una decisión
            // que no tiene nada que ver con el ángulo de cabeza. El camino
            // geométrico sigue existiendo como respaldo si por lo que sea el
            // resultado no trae blendshapes.
            .setOutputFaceBlendshapes(true)
            .setResultListener { result, image ->
                try {
                    // BitmapExtractor.extract() sobre el MISMO `image` que
                    // MediaPipe acaba de analizar para `result` — garantiza
                    // que el bitmap corresponde EXACTO a este resultado, sin
                    // depender de un bitmap guardado aparte que podría
                    // pertenecer a un frame distinto (ver CameraXManager).
                    // Extraído ANTES de EyeTrackingResultMapper.map() porque
                    // ese mapper también lo usa (para exponer a Flutter
                    // dónde detecta LashEdgeDetector la pestaña real).
                    val bitmap = try {
                        BitmapExtractor.extract(image)
                    } catch (e: Exception) {
                        Log.w(TAG, "BitmapExtractor.extract falló — detección de pestaña real desactivada para este frame", e)
                        null
                    }
                    val mapped = mapper.map(
                        result,
                        image.width,
                        image.height,
                        bitmap,
                    )
                    onResult(mapped, result, bitmap)
                } catch (e: Exception) {
                    Log.e(TAG, "Exception in result listener", e)
                    onError(e.message ?: "Error processing FaceLandmarker result")
                } finally {
                    // En `finally`, NO al final del `try`: si algo corriente
                    // abajo (mapper, render) lanza, el flag tiene que
                    // liberarse igual. Si no, [detectAsync] rechazaría todos
                    // los frames siguientes y el tracking se congelaría para
                    // siempre por una única excepción.
                    inferenceInFlight.set(false)
                }
            }
            .setErrorListener { error ->
                // Mismo motivo que el `finally` de arriba: un error de
                // inferencia no debe dejar el pipeline trancado.
                inferenceInFlight.set(false)
                onError(error.message ?: "Unknown error")
            }
            .build()

        return FaceLandmarker.createFromOptions(context, options)
    }

    /**
     * Entrega [image] a MediaPipe, PERO SÓLO si el frame anterior ya
     * terminó. Devuelve `false` (sin hacer nada) si hay uno en vuelo.
     *
     * ## Por qué (fix del retraso de varios segundos, 2026-09-04)
     *
     * `detectAsync` es ASÍNCRONO: retorna apenas encola el frame en el grafo
     * de MediaPipe. El analyzer de CameraX está en
     * `STRATEGY_KEEP_ONLY_LATEST`, pero esa estrategia solo descarta frames
     * mientras el callback del analyzer sigue ejecutándose — y como el
     * callback terminaba enseguida (justo porque `detectAsync` no bloquea),
     * CameraX seguía entregando frames al ritmo completo de la cámara.
     *
     * Si la inferencia tarda más que el intervalo entre frames (p.ej. 40 ms
     * de inferencia contra 33 ms de intervalo a 30 fps), la cola INTERNA de
     * MediaPipe crece sin límite: cada frame sale ~7 ms más viejo que el
     * anterior, y después de un minuto el resultado que llega corresponde a
     * lo que la persona hizo hace varios SEGUNDOS. Encolar más no da más
     * throughput — el dispositivo procesa lo que puede igual — solo agrega
     * retraso.
     *
     * Con este cerrojo se procesa como máximo un frame a la vez: el retraso
     * queda acotado a UNA inferencia y la tasa se autorregula a lo que el
     * dispositivo realmente aguanta. Además el llamador puede saltear el
     * trabajo de conversión del bitmap cuando esto devuelve `false`, que es
     * el otro gasto grande por frame.
     */
    fun detectAsync(image: com.google.mediapipe.framework.image.MPImage, timestampMs: Long): Boolean {
        val landmarker = faceLandmarker ?: return false
        val now = SystemClock.uptimeMillis()
        if (!inferenceInFlight.compareAndSet(false, true)) {
            // VENCIMIENTO DE SEGURIDAD. El cerrojo se libera en el `finally`
            // del result listener y en el error listener, o sea en todos los
            // caminos que MediaPipe documenta. Pero si alguna vez no llamara a
            // NINGUNO de los dos, el cerrojo quedaría tomado y el tracking se
            // congelaría para siempre — un modo de falla bastante peor que el
            // retraso que este cerrojo viene a arreglar. Pasado
            // [IN_FLIGHT_TIMEOUT_MS] se da por perdido ese frame y se sigue.
            // El umbral es holgado a propósito: muchísimo más que cualquier
            // inferencia real (~20-60 ms), así que no puede dispararse solo
            // porque el dispositivo vaya lento.
            if (now - inFlightSinceMs < IN_FLIGHT_TIMEOUT_MS) return false
            Log.w(
                TAG,
                "detectAsync: el frame en vuelo lleva ${now - inFlightSinceMs}ms sin resultado " +
                    "ni error — se da por perdido y se continúa",
            )
        }
        inFlightSinceMs = now
        return try {
            landmarker.detectAsync(image, timestampMs)
            true
        } catch (e: Throwable) {
            inferenceInFlight.set(false)
            throw e
        }
    }

    /**
     * Chequeo BARATO y sin efectos, para que el llamador pueda saltear el
     * trabajo de conversión del bitmap cuando [detectAsync] iba a rechazar el
     * frame igual. Es aproximado a propósito (el estado puede cambiar entre
     * este chequeo y la entrega): el único que decide sigue siendo
     * [detectAsync], con un `compareAndSet` atómico.
     */
    fun isInferenceInFlight(): Boolean = inferenceInFlight.get()

    fun close() {
        faceLandmarker?.close()
        faceLandmarker = null
        // Que un ciclo de vida nuevo (volver a entrar a la pantalla) no
        // herede un cerrojo tomado por el anterior.
        inferenceInFlight.set(false)
    }

    fun getLandmarker(): FaceLandmarker? = faceLandmarker

    private companion object {
        /** Ver el vencimiento de seguridad en [detectAsync]. */
        private const val IN_FLIGHT_TIMEOUT_MS = 1_000L

        private const val TAG = "FaceLandmarkerHelper"
        private const val MODEL_ASSET = "face_landmarker.task"
    }
}