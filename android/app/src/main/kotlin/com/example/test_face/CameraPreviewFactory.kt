package com.example.test_face

import android.app.Activity
import android.content.Context
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

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
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

        val root = FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
            addView(previewView)   // Z=0: fondo — feed de cámara
            addView(sceneView)     // Z=1: encima — modelos 3D
        }

        val manager = managerProvider()
        manager.attachPreview(previewView)
        manager.attachSceneView(sceneView)

        return object : PlatformView {
            override fun getView(): View = root

            override fun dispose() {
                manager.detachPreview()
                manager.detachSceneView()
            }
        }
    }
}
