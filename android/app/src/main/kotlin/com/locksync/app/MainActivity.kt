package com.locksync.app

import android.app.WallpaperManager
import android.graphics.BitmapFactory
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.locksync/wallpaper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLockScreenWallpaper" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_PATH", "Path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        val wallpaperManager = WallpaperManager.getInstance(applicationContext)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                        } else {
                            wallpaperManager.setBitmap(bitmap)
                        }
                        bitmap.recycle()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WALLPAPER_ERROR", e.message, null)
                    }
                }
                "setShowOnLockScreen" -> {
                    val show = call.argument<Boolean>("show") ?: false
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            setShowWhenLocked(show)
                            setTurnScreenOn(show)
                        } else {
                            @Suppress("DEPRECATION")
                            if (show) {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                                )
                            } else {
                                window.clearFlags(
                                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                                )
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LOCK_SCREEN_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
