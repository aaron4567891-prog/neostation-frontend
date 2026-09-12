package com.neogamelab.neostation

import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import com.hcoderlee.subscreen.sub_screen.FlutterPresentation
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A [FlutterPresentation] that additionally registers a MethodChannel on the
 * secondary display's Flutter engine, so the bottom-screen app dock can list,
 * icon-load and launch Android apps directly (the secondary engine cannot reach
 * the main app's "/game" channel — that's why other secondary features signal
 * the main engine through shared state instead).
 *
 * The base class creates and owns the engine in a private field and its
 * show()/dismiss() rely on it, so we let [onCreate] run normally and then reach
 * that engine via reflection to attach our channel. The field name is pinned by
 * the locked `sub_screen` dependency version.
 */
class SecondaryAppsPresentation(
    private val activity: MainActivity,
    display: Display,
    entryPointFun: String
) : FlutterPresentation(activity, display, entryPointFun) {

    companion object {
        private const val TAG = "SecondaryApps"
        private const val CHANNEL = "com.neogamelab.neostation/secondary_apps"
    }

    private var appsChannel: MethodChannel? = null
    private var inputFocused = false
    private var lastHatX = 0
    private var lastHatY = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hardenAgainstDismissal()
        registerAppsChannel()
    }

    /**
     * Keeps the bottom screen alive when the user interacts with it.
     *
     * A [android.app.Presentation] is a [android.app.Dialog], so out of the box
     * it is cancelable: tapping the bottom screen moves input focus to this
     * window, and the next BACK press runs Dialog's default handling —
     * cancel() then [dismiss] — which tears the secondary FlutterView off its
     * engine and destroys it. The bottom half of the launcher then disappears
     * for good (the system launcher shows through) while the top half keeps
     * running, and nothing recreates it because the activity still holds the
     * dismissed Presentation. MainActivity already swallows BACK, but that only
     * covers its own window — this one is separate and never saw the key.
     *
     * Keep the Presentation focusable when it is first shown. Some dual-screen
     * Android builds do not route touch to a non-focusable Presentation, which
     * means it can never receive the touch that would make it focusable again.
     * Tapping the main window still calls [releaseInputFocus], so controller
     * focus returns to the top display normally.
     */
    private fun hardenAgainstDismissal() {
        setCancelable(false)
        setCanceledOnTouchOutside(false)
        try {
            window?.clearFlags(
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not make secondary window non-focusable: ${e.message}")
        }
    }

    /** Temporarily gives the bottom display controller focus after a touch. */
    private fun acquireInputFocus() {
        if (inputFocused) return
        inputFocused = true
        window?.clearFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM
        )
        window?.decorView?.requestFocus()
        appsChannel?.invokeMethod("onSecondaryInputFocusChanged", true)
    }

    /** Returns controller input to the main display without dismissing us. */
    fun releaseInputFocus() {
        if (!inputFocused) return
        inputFocused = false
        window?.addFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM
        )
        activity.requestMainInputFocus()
        appsChannel?.invokeMethod("onSecondaryInputFocusChanged", false)
    }

    /** Whether controller events received by the main Activity belong here. */
    fun wantsControllerInput(): Boolean = inputFocused

    /** Delivers a controller key that Android routed to the main display. */
    fun forwardControllerKey(event: KeyEvent) {
        appsChannel?.invokeMethod(
            "onSecondaryControllerKey",
            mapOf(
                "keyCode" to event.keyCode,
                "action" to event.action,
                "repeatCount" to event.repeatCount
            )
        )
    }

    /** Delivers controller axis/hat motion routed to the main display. */
    fun forwardControllerMotion(event: MotionEvent) {
        if (!handleControllerMotion(event)) {
            super.dispatchGenericMotionEvent(event)
        }
    }

    private fun sendControllerKeyDown(keyCode: Int) {
        appsChannel?.invokeMethod(
            "onSecondaryControllerKey",
            mapOf("keyCode" to keyCode, "action" to KeyEvent.ACTION_DOWN, "repeatCount" to 0)
        )
    }

    private fun handleControllerMotion(event: MotionEvent): Boolean {
        if (!inputFocused ||
            !isControllerSource(event.source) ||
            event.actionMasked != MotionEvent.ACTION_MOVE
        ) return false

        val hatXValue = event.getAxisValue(MotionEvent.AXIS_HAT_X)
        val hatYValue = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
        val hatX = when {
            hatXValue < -0.5f -> -1
            hatXValue > 0.5f -> 1
            else -> 0
        }
        val hatY = when {
            hatYValue < -0.5f -> -1
            hatYValue > 0.5f -> 1
            else -> 0
        }

        if (hatX != 0 && hatX != lastHatX) {
            sendControllerKeyDown(
                if (hatX < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT
            )
        }
        if (hatY != 0 && hatY != lastHatY) {
            sendControllerKeyDown(
                if (hatY < 0) KeyEvent.KEYCODE_DPAD_UP else KeyEvent.KEYCODE_DPAD_DOWN
            )
        }
        lastHatX = hatX
        lastHatY = hatY
        return hatX != 0 || hatY != 0
    }

    private fun isControllerSource(source: Int): Boolean {
        return source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
            source and InputDevice.SOURCE_DPAD == InputDevice.SOURCE_DPAD ||
            source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        return if (handleControllerMotion(event)) true else super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Acquire focus before Flutter receives ACTION_DOWN so the complete
        // gesture is delivered to the secondary engine on affected devices.
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            acquireInputFocus()
        }
        return super.dispatchTouchEvent(event)
    }

    /** Never let BACK reach Dialog's cancel path, focused or not. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Once the bottom Presentation owns Android focus, controller events
        // arrive here instead of MainActivity. Forward them explicitly to the
        // secondary Flutter engine through its MethodChannel.
        if (inputFocused && isControllerSource(event.source)) {
            if (event.keyCode == KeyEvent.KEYCODE_BACK ||
                event.keyCode == KeyEvent.KEYCODE_BUTTON_B
            ) {
                appsChannel?.invokeMethod("onSecondaryBack", null)
            } else {
                forwardControllerKey(event)
            }
            return true
        }
        if (event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_BACK ||
                event.keyCode == KeyEvent.KEYCODE_BUTTON_B)
        ) {
            appsChannel?.invokeMethod("onSecondaryBack", null)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // Deprecated since API 33, but Dialog still routes BACK through it and the
    // override must stay for the platforms that do.
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Deliberately empty: BACK must never dismiss the bottom screen.
    }

    private fun registerAppsChannel() {
        val engine = resolveEngine()
        if (engine == null) {
            Log.e(TAG, "Could not resolve secondary FlutterEngine; dock channel unavailable")
            return
        }
        appsChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        val includeSystem = call.argument<Boolean>("includeSystemApps") ?: false
                        activity.getInstalledApps(includeSystem, result)
                    }
                    "getAppIcon" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            activity.getAppIcon(pkg, result)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Package name is required", null)
                        }
                    }
                    "launchAppOnSecondary" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg != null) {
                            activity.launchPackageOnSecondaryDisplay(pkg, result)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Package name is required", null)
                        }
                    }
                    "openAccessibilitySettings" -> {
                        activity.openScreenshotAccessSettings()
                        result.success(null)
                    }
                    "isDisplayOn" -> result.success(isDisplayOn())
                    "releaseInputFocus" -> {
                        releaseInputFocus()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Live power state of the display this presentation renders on — the ground
     * truth for "is the bottom screen actually lit". The secondary engine gets
     * no Android lifecycle callbacks and its shared-state mirror of the screen
     * flag travels on a transport that ships full snapshots with no ordering
     * guarantee, so a stale snapshot can resurrect a `true` after the device has
     * gone to sleep. Asking the display itself can't go stale.
     *
     * Fails open (true): a display we cannot read must not silently disable the
     * preview while the device is awake.
     */
    private fun isDisplayOn(): Boolean {
        return try {
            getDisplay().state == Display.STATE_ON
        } catch (e: Exception) {
            Log.w(TAG, "Could not read secondary display state: ${e.message}")
            true
        }
    }

    /**
     * Pushes a device screen on/off edge straight to the secondary engine.
     * Direct and ordered, unlike the shared-state snapshot mirror, so the engine
     * can tear its preview video down on sleep and know the teardown sticks.
     * Must be called on the main thread.
     */
    fun notifyScreenState(on: Boolean) {
        try {
            appsChannel?.invokeMethod(
                if (on) "onDeviceScreenOn" else "onDeviceScreenOff",
                null
            )
        } catch (e: Exception) {
            Log.e(TAG, "notifyScreenState failed: ${e.message}")
        }
    }

    /** Reads the base class's private engine field created during onCreate. */
    private fun resolveEngine(): FlutterEngine? {
        return try {
            val field = FlutterPresentation::class.java.getDeclaredField("flutterEngine")
            field.isAccessible = true
            field.get(this) as? FlutterEngine
        } catch (e: Exception) {
            Log.e(TAG, "Reflection for secondary engine failed: ${e.message}")
            null
        }
    }

    override fun dismiss() {
        appsChannel?.setMethodCallHandler(null)
        appsChannel = null
        super.dismiss()
    }
}
