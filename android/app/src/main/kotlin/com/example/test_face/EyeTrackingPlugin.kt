package com.example.test_face

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.Executors
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewRegistry

class EyeTrackingPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
    registry: PlatformViewRegistry
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "eye_tracking/methods")
    private val eventChannel = EventChannel(messenger, "eye_tracking/events")

    private var eventSink: EventChannel.EventSink? = null
    private var cameraXManager: CameraXManager? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registry.registerViewFactory(
            "eye_tracking/camera_preview",
            CameraPreviewFactory(activity) { ensureCameraXManager() }
        )
    }

    private fun ensureCameraXManager(): CameraXManager {
        if (cameraXManager == null) {
            cameraXManager = CameraXManager(
                activity = activity,
                onTrackingResult = { data ->
                    activity.runOnUiThread { eventSink?.success(data) }
                },
                onError = { error ->
                    activity.runOnUiThread {
                        eventSink?.error("TRACKING_ERROR", error, null)
                    }
                }
            )
        }
        return cameraXManager!!
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTracking" -> {
                startTracking()
                result.success(null)
            }
            "stopTracking" -> {
                stopTracking(result)
            }
            "switchCamera" -> {
                // Devuelve el estado resultante para que Flutter no tenga que
                // llevar su propia copia (se desincronizaba: este manager
                // sobrevive a la recreación de las pantallas y hay dos que
                // ofrecen cambiar de cámara).
                result.success(cameraXManager?.switchCamera())
            }
            "isUsingFrontCamera" -> {
                result.success(cameraXManager?.isUsingFrontCamera())
            }
            "setInvertedFaceMode" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val photoMode = call.argument<Boolean>("photoMode") ?: enabled
                cameraXManager?.setInvertedFaceMode(enabled, photoMode)
                result.success(null)
            }
            "takePhoto" -> {
                val mgr = cameraXManager
                if (mgr == null) {
                    result.success(null)
                } else {
                    mgr.takePhoto(result)
                }
            }
            "cropPhotoBand" -> cropPhotoBand(call, result)
            "refreshPreviewBind" -> {
                cameraXManager?.refreshPreviewBind()
                result.success(null)
            }
            "captureFrame" -> {
                val mgr = cameraXManager
                if (mgr == null) {
                    result.success(null)
                } else {
                    mgr.captureFrame(result)
                }
            }
            "startRecording" -> {
                val mgr = cameraXManager
                if (mgr == null) {
                    result.error("NO_CAMERA", "La cámara no está inicializada", null)
                } else {
                    mgr.startRecording(result)
                }
            }
            "stopRecording" -> {
                val mgr = cameraXManager
                if (mgr == null) {
                    result.success(null)
                } else {
                    mgr.stopRecording(result)
                }
            }
            "loadEyeModels" -> {
                val leftPath = call.argument<String>("leftPath")
                val rightPath = call.argument<String>("rightPath")
                cameraXManager?.loadEyeModels(leftPath, rightPath)
                result.success(null)
            }
            "setLashStyle" -> {
                val styleId = call.argument<String>("styleId")
                cameraXManager?.setLashStyle(styleId)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Hilo propio para [PhotoBandCropper]: decodificar y codificar en el
     * hilo principal trabaría la UI justo mientras se abre el asistente. */
    private val photoExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Ver [PhotoBandCropper]. Responde `null` si falla, y Dart usa entonces
     * su camino de siempre. */
    private fun cropPhotoBand(call: MethodCall, result: MethodChannel.Result) {
        val jpeg = call.argument<ByteArray>("jpeg")
        val mirror = call.argument<Boolean>("mirror") ?: false
        val rotate180 = call.argument<Boolean>("rotate180") ?: false
        val bandStart = call.argument<Double>("bandStart")
        val bandHeight = call.argument<Double>("bandHeight")
        val overlayWidth = call.argument<Int>("overlayWidth")
        val overlayHeight = call.argument<Int>("overlayHeight")
        if (jpeg == null || bandStart == null || bandHeight == null ||
            overlayWidth == null || overlayHeight == null
        ) {
            result.success(null)
            return
        }
        val queuedAt = SystemClock.uptimeMillis() // TEMPORAL — CaptureTiming.
        photoExecutor.execute {
            val startedAt = SystemClock.uptimeMillis()
            val cropped = try {
                PhotoBandCropper.crop(
                    jpeg, mirror, rotate180, bandStart, bandHeight, overlayWidth, overlayHeight,
                )
            } catch (e: Throwable) {
                Log.e("EyeTrackingPlugin", "cropPhotoBand falló", e)
                null
            }
            val doneAt = SystemClock.uptimeMillis()
            mainHandler.post {
                // TEMPORAL — CaptureTiming: espera en cola, recorte y espera
                // del hilo principal para devolver el resultado a Flutter.
                Log.i(
                    "CaptureTiming",
                    "nativo cropPhotoBand cola=${startedAt - queuedAt}ms " +
                        "recorte=${doneAt - startedAt}ms " +
                        "esperaHiloPrincipal=${SystemClock.uptimeMillis() - doneAt}ms",
                )
                result.success(cropped)
            }
        }
    }

    private fun startTracking() {
        ensureCameraXManager().start()
    }

    private fun stopTracking(result: MethodChannel.Result) {
        val mgr = cameraXManager
        if (mgr == null) {
            result.success(null)
            return
        }
        mgr.stop(result)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}