package com.example.test_face

import android.app.Activity
import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewFactory(
    private val activity: Activity,
    private val managerProvider: () -> CameraXManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val previewView =
            PreviewView(activity).apply {
                layoutParams =
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                scaleType = PreviewView.ScaleType.FILL_CENTER
                // TextureView: mejor composición con Flutter encima del vídeo.
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            }
        val root =
            FrameLayout(activity).apply {
                layoutParams =
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                addView(previewView)
            }
        managerProvider().attachPreview(previewView)
        return object : PlatformView {
            override fun getView(): View = root

            override fun dispose() {
                managerProvider().detachPreview()
            }
        }
    }
}
