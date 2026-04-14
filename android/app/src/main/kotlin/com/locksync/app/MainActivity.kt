package com.locksync.app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // WallpaperPlugin registers the com.locksync/wallpaper MethodChannel.
        // Adding it here ensures it is also available in the main (Activity)
        // engine, so setShowOnLockScreen() works (it requires an Activity
        // reference that the background-service engine doesn't have).
        flutterEngine.plugins.add(WallpaperPlugin())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
    }

    override fun onResume() {
        super.onResume()
        // Re-apply on every resume so the flags survive config changes and
        // activity recreation (e.g. rotation, theme change).
        applyLockScreenFlags()
    }

    /**
     * Allow the activity to show over the lock screen and turn the screen on
     * when a full-screen intent wakes the device.
     *
     * setShowWhenLocked / setTurnScreenOn are the modern replacements for the
     * deprecated FLAG_SHOW_WHEN_LOCKED / FLAG_TURN_SCREEN_ON window flags
     * (deprecated in API 27). The flag fallback is kept for devices still on
     * Android 8.0 (API 26) or below.
     */
    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }
}
