package com.locksync.app

import android.content.Intent
import android.os.IBinder
import id.flutter.flutter_background_service.BackgroundService

/**
 * Extends [BackgroundService] to register [WallpaperPlugin] in the
 * background engine. Without this, the background Dart isolate cannot
 * invoke `setLockScreenWallpaper` because the MethodChannel is missing.
 *
 * The default BackgroundService only calls GeneratedPluginRegistrant
 * which does not include local (non-pub) plugins like WallpaperPlugin.
 *
 * We override [onStartCommand] so we can register [WallpaperPlugin]
 * after the parent has created and initialized its FlutterEngine.
 */
class LockSyncBackgroundService : BackgroundService() {

    private var pluginRegistered = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val result = super.onStartCommand(intent, flags, startId)
        // Register WallpaperPlugin after the parent has created the FlutterEngine
        // and registered all GeneratedPluginRegistrant plugins.
        if (!pluginRegistered) {
            try {
                // Access the engine created by the parent BackgroundService.
                // The parent stores it as a private field, but we can access it
                // via the FlutterEngine field that BackgroundService exposes.
                val engineField = BackgroundService::class.java.getDeclaredField("flutterEngine")
                engineField.isAccessible = true
                val engine = engineField.get(this) as? io.flutter.embedding.engine.FlutterEngine
                engine?.plugins?.add(WallpaperPlugin())
                pluginRegistered = true
            } catch (e: Exception) {
                // If we can't access the engine via reflection, the plugin won't
                // be available in the background — fallback to file-based approach.
                android.util.Log.w("LockSync", "Could not register WallpaperPlugin in background: ${e.message}")
            }
        }
        return result
    }
}
