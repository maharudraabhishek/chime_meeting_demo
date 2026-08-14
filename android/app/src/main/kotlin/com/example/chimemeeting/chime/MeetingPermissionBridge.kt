package com.example.chimemeeting.chime

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Android runtime-permission request required before meeting bootstrap.
 *
 * The bridge requests camera and microphone together and returns only a stable
 * permission-status string to Dart. It never owns Chime state or exposes Android
 * permission objects outside the native infrastructure boundary.
 */
internal class MeetingPermissionBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var pendingResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    /** Validates the requested command and starts one Android permission request. */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            REQUEST_PERMISSIONS_METHOD -> handleRequestPermissions(result)
            GET_STATUS_METHOD -> handleGetStatus(result)
            OPEN_SETTINGS_METHOD -> handleOpenSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun handleRequestPermissions(result: MethodChannel.Result) {
        if (hasRequiredPermissions()) {
            result.success("granted")
            return
        }

        if (pendingResult != null) {
            result.error(
                ERROR_REQUEST_IN_PROGRESS,
                "A meeting permission request is already in progress.",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success("granted")
            return
        }

        // Mark that the app has requested permissions at least once so that
        // shouldShowRequestPermissionRationale() can be interpreted correctly.
        try {
            val prefs = activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE)
            prefs.edit().putBoolean(PREF_KEY_REQUESTED_ONCE, true).apply()
        } catch (_: Exception) {
            // Best-effort; failure to persist should not block the permission flow.
        }

        pendingResult = result
        activity.requestPermissions(REQUIRED_PERMISSIONS, REQUEST_CODE)
    }

    private fun handleGetStatus(result: MethodChannel.Result) {
        if (hasRequiredPermissions()) {
            result.success("granted")
            return
        }

        // If a previously-requested permission now reports shouldShowRequestPermissionRationale==false
        // treat it as permanentlyDenied. Never classify first-time never-asked state as permanent.
        var anyPermanentlyDenied = false
        try {
            val prefs = activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE)
            val requestedOnce = prefs.getBoolean(PREF_KEY_REQUESTED_ONCE, false)

            if (requestedOnce) {
                anyPermanentlyDenied = REQUIRED_PERMISSIONS.any { permission ->
                    activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED &&
                        !activity.shouldShowRequestPermissionRationale(permission)
                }
            }
        } catch (_: Exception) {
            // If prefs are unavailable, fall back to conservative classification
            anyPermanentlyDenied = REQUIRED_PERMISSIONS.any { permission ->
                activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED &&
                    !activity.shouldShowRequestPermissionRationale(permission)
            }
        }

        if (anyPermanentlyDenied) {
            result.success("permanentlyDenied")
            return
        }

        result.success("denied")
    }

    private fun handleOpenSettings(result: MethodChannel.Result) {
        try {
            val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            val uri = android.net.Uri.fromParts("package", activity.packageName, null)
            intent.data = uri
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.success(false)
        }
    }

    /**
     * Completes the pending Flutter request when Android reports permission state.
     *
     * Returns `true` when this bridge owns [requestCode], allowing MainActivity
     * to delegate unrelated permission results to Flutter's normal lifecycle.
     */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) {
            return false
        }

        val result = pendingResult
        pendingResult = null

        if (grantResults.size == REQUIRED_PERMISSIONS.size &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            result?.success("granted")
            return true
        }

        // Determine whether any denied permission should be considered permanently
        // denied. Only treat it as permanent if we previously requested permissions.
        var anyPermanentlyDenied = false
        try {
            val prefs = activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE)
            val requestedOnce = prefs.getBoolean(PREF_KEY_REQUESTED_ONCE, false)
            if (requestedOnce) {
                for (i in REQUIRED_PERMISSIONS.indices) {
                    val permission = REQUIRED_PERMISSIONS[i]
                    val res = grantResults.getOrNull(i)
                    if (res != PackageManager.PERMISSION_GRANTED && !activity.shouldShowRequestPermissionRationale(permission)) {
                        anyPermanentlyDenied = true
                        break
                    }
                }
            }
        } catch (_: Exception) {
            // Fallback to original logic if prefs are unavailable
            for (i in REQUIRED_PERMISSIONS.indices) {
                val permission = REQUIRED_PERMISSIONS[i]
                val res = grantResults.getOrNull(i)
                if (res != PackageManager.PERMISSION_GRANTED && !activity.shouldShowRequestPermissionRationale(permission)) {
                    anyPermanentlyDenied = true
                    break
                }
            }
        }

        if (anyPermanentlyDenied) {
            result?.success("permanentlyDenied")
        } else {
            result?.success("denied")
        }
        return true
    }

    /** Detaches the method channel when the Flutter engine leaves activity scope. */
    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingResult = null
    }

    /** Returns whether both required media permissions are already granted. */
    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return REQUIRED_PERMISSIONS.all {
            activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    /** Contains the permission bridge wire contract and request identity. */
    private companion object {
        const val CHANNEL_NAME = "com.example.chimemeeting/permissions/methods"
        const val REQUEST_PERMISSIONS_METHOD = "requestMeetingPermissions"
        const val GET_STATUS_METHOD = "getMeetingPermissionStatus"
        const val OPEN_SETTINGS_METHOD = "openAppSettings"
        const val ERROR_REQUEST_IN_PROGRESS = "permission_request_in_progress"
        const val REQUEST_CODE = 4701

        val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CAMERA,
        )

        // SharedPreferences keys used to record whether permissions were ever requested
        // so that shouldShowRequestPermissionRationale() can be interpreted correctly
        // (it returns false both for 'never asked' and 'don't ask again').
        const val PREFS_NAME = "com.example.chimemeeting.permissions"
        const val PREF_KEY_REQUESTED_ONCE = "requested_once"
    }
}
