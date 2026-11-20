package com.example.test_face

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var eyeTrackingPlugin: EyeTrackingPlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Con la pantalla completa de la cámara (barras ocultas), Android
        // dejaba en negro la franja de la cámara frontal (notch/agujero) y la
        // ventana empezaba debajo: los botones de arriba bajaban ~88 px. Así
        // la app dibuja también ahí, como cuando la barra de estado se ve.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        eyeTrackingPlugin = EyeTrackingPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.platformViewsController.registry
        )
    }
}