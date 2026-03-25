package com.locksync.app

import android.app.WallpaperManager
import android.graphics.BitmapFactory
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Handles the com.locksync/wallpaper platform channel.
 *
 * Registered as a proper FlutterPlugin so it is available in BOTH the
 * main (Activity) Flutter engine and the flutter_background_service engine.
 *
 * setLockScreenWallpaper  — uses applicationContext; works from background service.
 * setShowOnLockScreen     — requires an Activity; silently ignored from background.
 */
class WallpaperPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var appContext: android.content.Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
    }

    // ── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setLockScreenWallpaper" -> handleSetWallpaper(call, result)
            "setShowOnLockScreen"   -> handleShowOnLockScreen(call, result)
            else                    -> result.notImplemented()
        }
    }

    private fun handleSetWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INVALID_PATH", "Path is required", null)
            return
        }
        val ctx = appContext ?: run {
            result.error("NO_CONTEXT", "Application context unavailable", null)
            return
        }
        try {
            val file = File(path)
            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
            if (bitmap == null) {
                result.error("DECODE_ERROR", "Failed to decode image at $path", null)
                return
            }
            val wm = WallpaperManager.getInstance(ctx)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                wm.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
            } else {
                @Suppress("DEPRECATION")
                wm.setBitmap(bitmap)
            }
            bitmap.recycle()
            result.success(true)
        } catch (e: Exception) {
            result.error("WALLPAPER_ERROR", e.message, null)
        }
    }

    private fun handleShowOnLockScreen(call: MethodCall, result: MethodChannel.Result) {
        val show = call.argument<Boolean>("show") ?: false
        val activity = activityBinding?.activity
        if (activity == null) {
            // Called from background service — no activity to configure; safe no-op.
            result.success(false)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                activity.setShowWhenLocked(show)
                activity.setTurnScreenOn(show)
            } else {
                @Suppress("DEPRECATION")
                if (show) {
                    activity.window.addFlags(
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    )
                } else {
                    activity.window.clearFlags(
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

    companion object {
        const val CHANNEL = "com.locksync/wallpaper"
    }
}
