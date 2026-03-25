package com.locksync.app

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
}
