package com.example.chimemeeting.chime

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Owns Flutter channel registration and delegates validated commands to Chime.
 *
 * No SDK object crosses this boundary. Errors use stable codes and safe messages;
 * raw exceptions, bridge arguments, and attendee credentials are never returned.
 */
internal class ChimePlatformBridge(
    messenger: BinaryMessenger,
    private val controller: ChimeSessionController,
    private val logger: SafeChimeLogger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, ChimeBridgeContract.METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, ChimeBridgeContract.EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /** Routes validated Flutter commands into the single native session controller. */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                ChimeBridgeContract.Method.START_SESSION -> {
                    controller.startSession(ChimeSessionBootstrap.from(call.arguments))
                    result.success(null)
                }
                ChimeBridgeContract.Method.SET_MICROPHONE_ENABLED -> {
                    result.success(
                        controller.setMicrophoneEnabled(call.arguments.requiredBoolean("enabled")),
                    )
                }
                ChimeBridgeContract.Method.SET_CAMERA_ENABLED -> {
                    result.success(
                        controller.setCameraEnabled(call.arguments.requiredBoolean("enabled")),
                    )
                }
                ChimeBridgeContract.Method.SWITCH_CAMERA -> {
                    // switchCamera may throw ChimeBridgeFailure on unsupported SDKs
                    result.success(controller.switchCamera())
                }
                ChimeBridgeContract.Method.LEAVE_SESSION -> {
                    controller.leaveSession()
                    result.success(null)
                }
                ChimeBridgeContract.Method.DISPOSE_SESSION -> {
                    controller.disposeSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (failure: ChimeBridgeFailure) {
            result.error(failure.code, failure.message, null)
        } catch (error: LinkageError) {
            logger.error(
                TAG,
                "Native media linkage failed: ${error.javaClass.simpleName}.",
            )
            result.error(
                ChimeBridgeContract.Error.NATIVE_INITIALIZATION,
                "Amazon Chime native media could not be loaded.",
                null,
            )
        } catch (error: Exception) {
            logger.error(TAG, "Bridge command failed: ${error.javaClass.simpleName}.")
            result.error(
                ChimeBridgeContract.Error.PLATFORM_BRIDGE,
                "The Android media bridge could not complete the command.",
                null,
            )
        }
    }

    /** Attaches the single Flutter event consumer for normalized Chime callbacks. */
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    /** Releases the current event sink when Flutter cancels the subscription. */
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** Publishes a normalized event on Android's main thread. */
    fun publish(event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver(event)
        } else {
            mainHandler.post { deliver(event) }
        }
    }

    /** Detaches channels before releasing the native session. */
    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        controller.disposeSession()
    }

    /** Delivers one credential-free event while isolating EventChannel failures. */
    private fun deliver(event: Map<String, Any?>) {
        try {
            eventSink?.success(event)
        } catch (error: Exception) {
            logger.warn(TAG, "Native event delivery failed: ${error.javaClass.simpleName}.")
        }
    }

    /** Native log tag used for bridge-only diagnostic messages. */
    private companion object {
        const val TAG = "ChimePlatformBridge"
    }
}
