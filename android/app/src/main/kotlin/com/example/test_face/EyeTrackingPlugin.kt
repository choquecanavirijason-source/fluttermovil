package com.example.test_face

import android.app.Activity
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
                cameraXManager?.switchCamera()
                result.success(null)
            }
            "refreshPreviewBind" -> {
                cameraXManager?.refreshPreviewBind()
                result.success(null)
            }
            else -> result.notImplemented()
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