package com.example.test_face

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.SystemClock
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

/**
 * Recorta la foto del asistente a la franja de ojos con el decodificador y
 * el codificador NATIVOS de Android, en vez del paquete `image` de Dart.
 *
 * ## Por qué existe
 *
 * Es el mismo trabajo que `EyeTrackingPhotoPipeline.compositeAndCrop`
 * (Dart) cuando el overlay está vacío: decodificar el JPEG, aplicar la
 * orientación EXIF, espejar (frontal), recortar a la proporción de la
 * pantalla, quedarse con la franja de ojos y agrandar a las medidas del
 * overlay. En Dart puro eso recorre la foto píxel por píxel y tomaba la
 * mayor parte de la demora al capturar (más aún en debug); acá son
 * llamadas nativas de ~100 ms.
 *
 * Las fórmulas de recorte y redondeo son LAS MISMAS que las de Dart, así que
 * las medidas y el encuadre de la foto final coinciden — que es de lo que
 * depende la alineación de la grilla. Los píxeles no son idénticos byte a
 * byte (otro decodificador/escalador/codificador JPEG), pero se ven igual.
 * Los porcentajes de la franja llegan desde Dart (única fuente de verdad).
 */
object PhotoBandCropper {

    /** Calidad JPEG: la misma que `_encode` en Dart. */
    private const val JPEG_QUALITY = 92

    /**
     * @param bandStart fracción del alto donde empieza la franja (ya
     *   reflejada si la clienta está echada, ver `_bandStart` en Dart).
     * @param bandHeight fracción del alto que ocupa la franja.
     * @param overlayWidth/overlayHeight medidas en píxeles del overlay que
     *   se habría capturado: fijan la proporción del recorte y el tamaño final.
     * @return el JPEG recortado, o `null` si algo falla (Dart cae entonces
     *   a su camino de siempre).
     */
    fun crop(
        jpeg: ByteArray,
        mirror: Boolean,
        rotate180: Boolean,
        bandStart: Double,
        bandHeight: Double,
        overlayWidth: Int,
        overlayHeight: Int,
    ): ByteArray? {
        if (overlayWidth <= 0 || overlayHeight <= 0) return null
        val t0 = SystemClock.uptimeMillis() // TEMPORAL — CaptureTiming.
        val decoded = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
        val tDecode = SystemClock.uptimeMillis()

        // 1. Orientación EXIF + espejo (equivale a `bakeOrientation` y
        //    `flipHorizontal` de Dart). El espejo va DESPUÉS de orientar.
        val orientation = ExifInterface(ByteArrayInputStream(jpeg))
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        val orient = exifMatrix(orientation)
        if (mirror) orient.postScale(-1f, 1f)
        val canvas = if (orient.isIdentity) {
            decoded
        } else {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, orient, false)
                .also { if (it !== decoded) decoded.recycle() }
        }
        val tOrient = SystemClock.uptimeMillis()

        // 2. Recorte a la proporción de la pantalla (BoxFit.cover), mismas
        //    fórmulas que Dart.
        val overlayAspect = overlayWidth.toDouble() / overlayHeight
        val faceAspect = canvas.width.toDouble() / canvas.height
        var cw = canvas.width
        var ch = canvas.height
        var cx = 0
        var cy = 0
        if (faceAspect > overlayAspect) {
            cw = (canvas.height * overlayAspect).roundToInt()
            cx = ((canvas.width - cw) / 2.0).roundToInt()
        } else if (faceAspect < overlayAspect) {
            ch = (canvas.width / overlayAspect).roundToInt()
            cy = ((canvas.height - ch) / 2.0).roundToInt()
        }

        // 3. Franja de ojos sobre el recorte (= `_bandRows` de Dart).
        val (bandY, bandH) = bandRows(ch, bandStart, bandHeight)
        var band = Bitmap.createBitmap(canvas, cx, cy + bandY, cw, bandH)
        if (band !== canvas) canvas.recycle()

        // 4. Giro 180° opcional, después del recorte (igual que Dart).
        if (rotate180) {
            val rotated = Bitmap.createBitmap(
                band, 0, 0, band.width, band.height,
                Matrix().apply { setRotate(180f) }, false,
            )
            if (rotated !== band) band.recycle()
            band = rotated
        }

        // 5. Mismo tamaño final que Dart: si la franja del overlay es más
        //    ancha, la foto se agranda (lineal) a sus medidas.
        val overlayBandW = overlayWidth
        val overlayBandH = bandRows(overlayHeight, bandStart, bandHeight).second
        if (overlayBandW > band.width) {
            val scaled = Bitmap.createScaledBitmap(band, overlayBandW, overlayBandH, true)
            if (scaled !== band) band.recycle()
            band = scaled
        }

        val tCrop = SystemClock.uptimeMillis()
        val outW = band.width
        val outH = band.height
        val result = ByteArrayOutputStream().use { out ->
            band.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
            band.recycle()
            out.toByteArray()
        }
        // TEMPORAL — CaptureTiming: tiempo de cada paso del recorte nativo.
        Log.i(
            "CaptureTiming",
            "nativo recorte: decodificar=${tDecode - t0}ms orientar=${tOrient - tDecode}ms " +
                "recortar+escalar=${tCrop - tOrient}ms codificar=${SystemClock.uptimeMillis() - tCrop}ms " +
                "salida=${outW}x$outH",
        )
        return result
    }

    /** `(y, alto)` de la franja para una imagen de [height] filas — mismas
     * fórmulas y redondeo que `_bandRows` en Dart. */
    private fun bandRows(height: Int, bandStart: Double, bandHeight: Double): Pair<Int, Int> {
        val y = (height * bandStart).roundToInt().coerceIn(0, height - 1)
        val h = (height * bandHeight).roundToInt().coerceIn(1, height - y)
        return y to h
    }

    /** Matriz que lleva la foto a su orientación real según el tag EXIF (los
     * 8 casos, como `bakeOrientation`). */
    private fun exifMatrix(orientation: Int): Matrix = Matrix().apply {
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> { setRotate(180f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
        }
    }
}
