package com.example.test_face

import android.graphics.ImageFormat
import android.hardware.HardwareBuffer
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import java.util.concurrent.Executor
import kotlin.math.abs

/**
 * Destino del caso de uso `Preview` en el modo sincronizado
 * ([com.example.test_face.render.RendererConfiguration.FRAME_SYNC_MODE]): en
 * vez de ir al `PreviewView` (que la muestra en vivo), la cámara llega acá
 * como buffers de GPU (`ImageReader` PRIVATE, sin copias) y se guardan los
 * últimos [KEEP] fotogramas con su marca de tiempo del SENSOR.
 *
 * Cuando MediaPipe termina un fotograma de análisis, [takeClosest] entrega el
 * fotograma de preview capturado en ese mismo instante (análisis y preview
 * salen de la misma captura, con el mismo timestamp de sensor), que se dibuja
 * junto con la pose de las pestañas calculada para él — ver
 * [com.example.test_face.render.CameraBackground].
 *
 * Los fotogramas más viejos que el entregado se cierran: nunca se van a
 * mostrar (la imagen solo avanza).
 */
@RequiresApi(Build.VERSION_CODES.Q)
class PreviewFrameRing(private val handler: Handler) : Preview.SurfaceProvider {

    private val executor = Executor { handler.post(it) }
    private val lock = Any()
    private val ring = ArrayDeque<Image>()

    /** Giro horario que deja derecho el buffer del sensor (de CameraX). */
    @Volatile var rotationDegrees: Int = 0
        private set

    /** Último fotograma recibido (diagnóstico). */
    @Volatile var framesReceived: Long = 0
        private set

    override fun onSurfaceRequested(request: SurfaceRequest) {
        val size = request.resolution
        val reader = ImageReader.newInstance(
            size.width,
            size.height,
            ImageFormat.PRIVATE,
            MAX_IMAGES,
            HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE,
        )
        reader.setOnImageAvailableListener({ r ->
            val image = try {
                r.acquireNextImage()
            } catch (e: Throwable) {
                // Todos los buffers en uso (no debería pasar con KEEP < MAX):
                // se saltea este fotograma en vez de romper la cámara.
                null
            } ?: return@setOnImageAvailableListener
            framesReceived++
            synchronized(lock) {
                ring.addLast(image)
                while (ring.size > KEEP) ring.removeFirst().close()
                (lock as Object).notifyAll()
            }
        }, handler)
        request.setTransformationInfoListener(executor) { info ->
            rotationDegrees = info.rotationDegrees
        }
        Log.i(TAG, "preview -> ImageReader ${size.width}x${size.height} (PRIVATE, GPU)")
        request.provideSurface(reader.surface, executor) {
            // CameraX ya no usa esta superficie (rebind o cámara detenida).
            clear()
            reader.close()
        }
    }

    /**
     * El fotograma de preview más cercano a [sensorTimestampNanos] (el
     * timestamp del fotograma de análisis). Lo saca del anillo y cierra los
     * anteriores; quien lo recibe tiene que cerrarlo. `null` si no hay.
     */
    fun takeClosest(sensorTimestampNanos: Long): Image? = synchronized(lock) {
        // El fotograma de preview suele llegar ~1 fotograma DESPUÉS que el
        // resultado de MediaPipe: se lo espera un momento en vez de mostrar
        // el anterior (que despega las pestañas de la imagen).
        val deadline = System.nanoTime() + WAIT_FOR_MATCH_NANOS
        while ((ring.lastOrNull()?.timestamp ?: Long.MIN_VALUE) < sensorTimestampNanos - MATCH_TOLERANCE_NANOS) {
            val left = deadline - System.nanoTime()
            if (left <= 0) break
            (lock as Object).wait(left / 1_000_000, (left % 1_000_000).toInt())
        }
        if (ring.isEmpty()) return null
        var best = 0
        var bestDiff = Long.MAX_VALUE
        for (i in ring.indices) {
            val diff = abs(ring[i].timestamp - sensorTimestampNanos)
            if (diff < bestDiff) {
                bestDiff = diff
                best = i
            }
        }
        repeat(best) { ring.removeFirst().close() }
        val image = ring.removeFirst()
        if (bestDiff > LOG_MISMATCH_NANOS && ++mismatchLogs <= MAX_MISMATCH_LOGS) {
            Log.w(TAG, "takeClosest: fotograma a ${bestDiff / 1_000_000} ms del analizado " +
                "objetivo=$sensorTimestampNanos elegido=${image.timestamp} idx=$best " +
                "anillo=[${ring.joinToString { ((it.timestamp - sensorTimestampNanos) / 1_000_000).toString() }}]")
        }
        image
    }

    /** El más nuevo (sin timestamp de análisis conocido). */
    fun takeLatest(): Image? = synchronized(lock) {
        if (ring.isEmpty()) return null
        while (ring.size > 1) ring.removeFirst().close()
        ring.removeFirst()
    }

    fun clear() = synchronized(lock) {
        while (ring.isNotEmpty()) ring.removeFirst().close()
    }

    private var mismatchLogs = 0

    companion object {
        private const val TAG = "PreviewFrameRing"

        /** Fotogramas guardados: ~260 ms a 30 fps, más que la latencia de
         * MediaPipe + la espera previa al envío (~60-120 ms medidos). */
        const val KEEP = 8

        /** [KEEP] + los que tiene Filament en pantalla y el que llega. */
        private const val MAX_IMAGES = KEEP + 5

        private const val LOG_MISMATCH_NANOS = 20_000_000L

        /** Espera máxima al fotograma de preview del mismo instante. */
        private const val WAIT_FOR_MATCH_NANOS = 50_000_000L

        /** Diferencia de timestamp que se considera "el mismo fotograma". */
        private const val MATCH_TOLERANCE_NANOS = 2_000_000L
        private const val MAX_MISMATCH_LOGS = 20
    }
}
