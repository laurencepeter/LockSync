package com.locksync.app

import android.app.Application
import android.content.IntentFilter

/**
 * Custom Application class.
 *
 * In flutter_background_service 6.x the V1-era `setPluginRegistrant` API was
 * removed.  The background service now creates its own [FlutterEngine] and
 * automatically registers all plugins listed in `GeneratedPluginRegistrant`.
 *
 * [WallpaperPlugin] is a local (non-pub) plugin, so it is NOT included in the
 * generated registrant.  It is still registered in the **main** engine by
 * [MainActivity.configureFlutterEngine].  From the background isolate, if the
 * platform channel is unavailable the Dart side catches the error and falls
 * back to persisting the image for the next foreground resume.
 *
 * NOTE: FlutterApplication (io.flutter.app.FlutterApplication) was removed in
 * Flutter's v2 embedding — extending it causes a ClassNotFoundException crash
 * at startup.  We extend plain [Application] instead.
 *
 * ── Lock-screen wake ────────────────────────────────────────────────────────
 * [ScreenOnReceiver] is registered here for [android.content.Intent.ACTION_SCREEN_ON].
 * That broadcast can NOT be declared in the AndroidManifest — it must be
 * registered dynamically at runtime.  Registering it in Application.onCreate
 * ensures it is active for the entire lifetime of this process, which includes
 * both the main UI isolate and the foreground-service isolate.  As long as
 * the foreground service is running the OS keeps the process alive, so the
 * receiver will fire on every screen-on event.
 */
class MainApplication : Application() {

    private val screenOnReceiver = ScreenOnReceiver()

    override fun onCreate() {
        super.onCreate()
        // Register dynamically — ACTION_SCREEN_ON is not receivable via manifest.
        registerReceiver(
            screenOnReceiver,
            android.content.IntentFilter(android.content.Intent.ACTION_SCREEN_ON)
        )
    }

    override fun onTerminate() {
        super.onTerminate()
        // onTerminate is not guaranteed to be called in production, but clean up
        // here for completeness (e.g. Robolectric tests, emulator shutdown).
        try {
            unregisterReceiver(screenOnReceiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered — safe to ignore.
        }
    }
}
