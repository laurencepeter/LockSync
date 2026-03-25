package com.locksync.app

import android.app.Application
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin

/**
 * Custom Application class that registers the WallpaperPlugin with the
 * flutter_background_service engine.
 *
 * This is what makes WallpaperManager.setBitmap() callable from the background
 * service isolate (i.e. when the phone is locked and the main activity is not
 * running), so the lock screen wallpaper is updated in real-time without the
 * user needing to open the app first.
 */
class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FlutterBackgroundServicePlugin.setPluginRegistrant { engine ->
            engine.plugins.add(WallpaperPlugin())
        }
    }
}
