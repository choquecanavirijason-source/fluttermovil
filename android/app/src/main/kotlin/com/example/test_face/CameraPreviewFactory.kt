package com.example.test_face

import android.app.Activity
import android.content.Context
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.github.sceneview.SceneView

class CameraPreviewFactory(
    private val activity: Activity,
    private val managerProvider: () -> CameraXManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    /**
     * Las rutas de los .glb viajan como `creationParams` (no por una llamada
     * separada al MethodChannel) para que la carga del modelo ocurra en la
     * MISMA invocación nativa que crea el [SceneView] nuevo — sin depender de
     * que Flutter dispare `loadEyeModels()` dentro de una ventana de tiempo
     * adivinada. Esa carrera Dart↔nativo (attach del SceneView vs. timers de
     * reintento en Dart) era la causa raíz de que el GLB no reapareciera al
     * volver a la pantalla: aquí queda estructuralmente imposible, porque el
     * `create()` es una única llamada síncrona.
     */
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val leftModelPath = params?.get("leftModelPath") as? String
        val rightModelPath = params?.get("rightModelPath") as? String

        val previewView = PreviewView(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
            // TextureView: mejor composición con Flutter encima del vídeo.
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }

        val sceneView = SceneView(
            context = activity,
            sharedLifecycle = (activity as? LifecycleOwner)?.lifecycle,
            // isOpaque=false configura a la vez: formato de superficie TRANSLUCENT,
            // Z-order y el color de limpieza de Filament (alpha 0). Sin esto, Filament
            // sigue limpiando cada frame con fondo opaco y tapa la cámara por completo
            // aunque el holder ya esté en modo translúcido. Es parámetro de constructor
            // (val), no se puede reasignar tras crear la instancia.
            isOpaque = false,
        ).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val manager = managerProvider()
        Log.i(
            TAG,
            "create() viewId=$viewId previewView=${System.identityHashCode(previewView)} " +
                "sceneView=${System.identityHashCode(sceneView)} manager=${System.identityHashCode(manager)} " +
                "leftModelPath=$leftModelPath rightModelPath=$rightModelPath",
        )

        val root = FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            addView(previewView)   // Z=0: fondo — feed de cámara
            addView(sceneView)     // Z=1: encima — modelos 3D
        }

        manager.attachPreview(previewView)
        manager.attachSceneView(sceneView)
        // Síncrono y determinista: corre antes de que este create() retorne,
        // así que jamás compite contra el SceneView todavía no adjuntado.
        manager.loadEyeModels(leftModelPath, rightModelPath)

        return object : PlatformView {
            override fun getView(): View = root

            override fun dispose() {
                Log.i(
                    TAG,
                    "dispose() viewId=$viewId previewView=${System.identityHashCode(previewView)} " +
                        "sceneView=${System.identityHashCode(sceneView)}",
                )
                manager.detachPreview(previewView)
                manager.detachSceneView(sceneView)
            }
        }
    }

    private companion object {
        private const val TAG = "CameraPreviewFactory"
    }
}
