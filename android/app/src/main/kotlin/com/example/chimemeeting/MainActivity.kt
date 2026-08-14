package com.example.chimemeeting

import com.example.chimemeeting.chime.ChimeBridgeContract
import com.example.chimemeeting.chime.ChimePlatformBridge
import com.example.chimemeeting.chime.ChimeSessionController
import com.example.chimemeeting.chime.ChimeVideoViewFactory
import com.example.chimemeeting.chime.MeetingPermissionBridge
import com.example.chimemeeting.chime.SafeChimeLogger
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers Android platform bridges while delegating media/session ownership.
 *
 * The activity is intentionally limited to Flutter-engine wiring. Chime state,
 * permission policy, video binding, and event mapping live in dedicated native
 * infrastructure classes.
 */
class MainActivity : FlutterActivity() {
    private var chimeBridge: ChimePlatformBridge? = null
    private var chimeVideoViewFactory: ChimeVideoViewFactory? = null
    private var meetingPermissionBridge: MeetingPermissionBridge? = null

    /** Registers the permission, Chime channel, and native video-view bridges. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val logger = SafeChimeLogger()
        lateinit var bridge: ChimePlatformBridge
        val controller = ChimeSessionController(applicationContext, logger) { event ->
            bridge.publish(event)
        }
        bridge = ChimePlatformBridge(
            flutterEngine.dartExecutor.binaryMessenger,
            controller,
            logger,
        )
        val viewFactory = ChimeVideoViewFactory(controller)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            ChimeBridgeContract.VIDEO_VIEW_TYPE,
            viewFactory,
        )
        chimeBridge = bridge
        chimeVideoViewFactory = viewFactory
        meetingPermissionBridge = MeetingPermissionBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    /** Delegates meeting permission results while preserving unrelated handlers. */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val handled = meetingPermissionBridge?.onRequestPermissionsResult(
            requestCode,
            grantResults,
        ) == true
        if (handled) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    /** Detaches platform bridges and native views before Flutter engine teardown. */
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        meetingPermissionBridge?.dispose()
        meetingPermissionBridge = null
        chimeBridge?.dispose()
        chimeBridge = null
        chimeVideoViewFactory?.disposeAll()
        chimeVideoViewFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
