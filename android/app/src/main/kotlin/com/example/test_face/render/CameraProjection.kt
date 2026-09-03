package com.example.test_face.render

import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import dev.romainguy.kotlin.math.Mat4
import kotlin.math.sqrt

/**
 * Snapshot mínimo de la cámara real de Filament necesario para des-proyectar
 * un punto de pantalla a una posición 3D verdadera a una profundidad
 * conocida. Se extrae una vez por frame desde `SceneView.cameraNode` (ver
 * [FaceRenderPipeline.compute]/[LashRenderer.onFaceResult]) para que
 * [EyeTransformCalculator] siga siendo matemática pura (`Mat4`/`Float3` de
 * kotlin-math), sin acoplarse directamente al tipo `Camera` de Filament.
 *
 * Reemplaza el mapeo lineal `(nx-0.5)*WORLD_SCALE_X` que existía antes: ese
 * mapeo era una proyección ortográfica encubierta, válida solo a la
 * distancia exacta a la que se calibraron las constantes — con esto, la
 * posición es correcta a cualquier distancia de cámara porque usa la
 * proyección de perspectiva real (ver auditoría, Hallazgo #1).
 */
data class CameraProjection(
    /** `camera.projectionTransform` — column-major, frustum simétrico (sin shift/lens offset). */
    val projection: Mat4,
    /** `camera.modelTransform` — transforma de espacio de cámara a espacio de mundo. */
    val cameraToWorld: Mat4,
    /**
     * Factor de cobertura `FILL_CENTER` en X (ver [fillCenter]). Convierte
     * un NDC derivado de coordenadas NORMALIZADAS DE IMAGEN (`2*nx-1`) al
     * NDC real del viewport.
     *
     * ## Por qué existe
     *
     * Todos los que des-proyectan en este motor parten de landmarks de
     * MediaPipe, que vienen normalizados contra la IMAGEN DE ANÁLISIS
     * (480x640 en dispositivo, aspecto 0.75). Pero el `SceneView` sobre el
     * que se renderiza cubre la pantalla completa (1440x3088, aspecto
     * 0.466), y el `PreviewView` de abajo muestra la cámara con
     * `ScaleType.FILL_CENTER`, o sea RECORTADA (cover), no estirada.
     *
     * Hacer `ndcX = 2*nx - 1` estira la imagen para llenar el viewport, que
     * es justo lo que el preview NO hace: con esos números el modelo 3D se
     * coloca a solo `viewportAspect/imageAspect` = 62% de la distancia
     * horizontal correcta respecto al centro (y el ancho del ojo medido en
     * mundo sale igual de angosto, ver
     * [EyeTransformCalculator]/`worldDistanceAtDepth`). El error crece con
     * la distancia del ojo al centro de la pantalla, así que se nota como
     * "las pestañas quedan lejos de donde deberían" — y no lo compensa
     * ninguna constante de calibración, porque depende de dónde esté la
     * cara en el cuadro.
     *
     * El overlay de debug en Flutter (`LidLandmarkDebugPainter`) siempre
     * hizo bien este mapeo (`scale = max(sx, sy)` + centrado), de ahí que
     * los puntos verdes sí cayeran sobre la línea de pestañas mientras el
     * `.glb` caía lejos.
     */
    val coverScaleX: Float = 1f,
    /** Ver [coverScaleX] — en cover uno de los dos factores es exactamente
     * 1 (el eje que llena el viewport) y el otro es > 1 (el recortado). */
    val coverScaleY: Float = 1f,
) {
    companion object {
        /**
         * Construye la proyección aplicando el mismo encuadre que usa el
         * `PreviewView` (`ScaleType.FILL_CENTER`): la imagen se escala por
         * `max(viewportW/imgW, viewportH/imgH)` y se centra, recortando el
         * excedente. Ver [coverScaleX] para por qué hace falta.
         *
         * Si alguna dimensión viene en 0 (el `SceneView` todavía no midió,
         * puede pasar en los primeros frames tras adjuntarlo) cae a factores
         * 1/1 — el comportamiento anterior, en vez de dividir por cero.
         */
        fun fillCenter(
            projection: Mat4,
            cameraToWorld: Mat4,
            imageWidth: Int,
            imageHeight: Int,
            viewportWidth: Int,
            viewportHeight: Int,
        ): CameraProjection {
            if (imageWidth <= 0 || imageHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0) {
                return CameraProjection(projection, cameraToWorld)
            }
            val iw = imageWidth.toFloat()
            val ih = imageHeight.toFloat()
            val vw = viewportWidth.toFloat()
            val vh = viewportHeight.toFloat()
            val scale = maxOf(vw / iw, vh / ih)
            // Fracción del viewport que abarca la imagen escalada: 1 en el
            // eje que llena, > 1 en el que se recorta.
            return CameraProjection(
                projection = projection,
                cameraToWorld = cameraToWorld,
                coverScaleX = iw * scale / vw,
                coverScaleY = ih * scale / vh,
            )
        }
    }
    /**
     * Des-proyecta un punto en coordenadas NDC (`[-1,1]`, convención OpenGL:
     * +Y hacia arriba) a la posición 3D real en espacio de mundo, a la
     * profundidad de vista [viewDepthZ] (unidades de mundo Filament, cámara
     * mirando hacia -Z — igual convención que `HeadPose.position.z`).
     *
     * Deriva `viewX`/`viewY` a partir de los términos diagonales de la
     * matriz de proyección en vez de invertir la matriz 4x4 completa: válido
     * exactamente cuando el frustum es simétrico (`setShift`/lens-shift no
     * usados), que es el caso de la cámara por defecto de `SceneView` en
     * este proyecto — `LashRenderer` nunca la reconfigura.
     */
    fun unproject(ndcX: Float, ndcY: Float, viewDepthZ: Float): Float3 {
        val px = projection.x.x
        val py = projection.y.y
        // [ndcX]/[ndcY] llegan derivados de coordenadas normalizadas de
        // IMAGEN; pasarlos por el factor de cover los lleva al NDC real del
        // viewport, que es lo que la matriz de proyección espera. Ver
        // [coverScaleX].
        val viewportNdcX = ndcX * coverScaleX
        val viewportNdcY = ndcY * coverScaleY
        // clipW = -viewZ: convención de cámara mirando hacia -Z (OpenGL/Filament).
        val viewX = viewportNdcX * (-viewDepthZ) / px
        val viewY = viewportNdcY * (-viewDepthZ) / py
        val viewPoint = Float4(viewX, viewY, viewDepthZ, 1f)
        val worldPoint = cameraToWorld * viewPoint
        return Float3(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    /**
     * Distancia real en espacio de mundo entre dos puntos de pantalla (NDC)
     * a la MISMA profundidad de vista — la forma físicamente correcta de
     * convertir un ancho en píxeles a un ancho en unidades de mundo,
     * respetando la perspectiva real (un mismo ancho en píxeles corresponde
     * a un ancho real mayor cuanto más lejos está el rostro de la cámara).
     */
    fun worldDistanceAtDepth(ndcX1: Float, ndcX2: Float, ndcY: Float, viewDepthZ: Float): Float {
        val a = unproject(ndcX1, ndcY, viewDepthZ)
        val b = unproject(ndcX2, ndcY, viewDepthZ)
        val dx = b.x - a.x
        val dy = b.y - a.y
        val dz = b.z - a.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
