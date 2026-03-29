package com.locksync.app

import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Build
import android.util.DisplayMetrics
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
 * getScreenDimensions     — returns device screen width/height for canvas rendering.
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
            "getScreenDimensions"   -> handleGetScreenDimensions(result)
            else                    -> result.notImplemented()
        }
    }

    /**
     * Scale the source bitmap to fill [targetW] x [targetH], cropping to
     * maintain aspect ratio (center-crop), then set as lock screen wallpaper.
     */
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
            val srcBitmap = BitmapFactory.decodeFile(file.absolutePath)
            if (srcBitmap == null) {
                result.error("DECODE_ERROR", "Failed to decode image at $path", null)
                return
            }

            val wm = WallpaperManager.getInstance(ctx)

            // Get the actual device lock screen dimensions
            val targetW: Int
            val targetH: Int
            val desiredW = wm.desiredMinimumWidth
            val desiredH = wm.desiredMinimumHeight
            if (desiredW > 0 && desiredH > 0) {
                targetW = desiredW
                targetH = desiredH
            } else {
                // Fallback: use actual screen metrics
                val windowManager = ctx.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
                val metrics = DisplayMetrics()
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay.getRealMetrics(metrics)
                targetW = metrics.widthPixels
                targetH = metrics.heightPixels
            }

            // Scale-to-fill (center crop) the rendered canvas to the device screen
            val bitmap = scaleCenterCrop(srcBitmap, targetW, targetH)
            srcBitmap.recycle()

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

    /**
     * Scale [src] to fill [targetW] x [targetH] exactly, center-cropping
     * if the aspect ratios differ, so the wallpaper always covers the
     * entire lock screen without black bars or corner-only rendering.
     */
    private fun scaleCenterCrop(src: Bitmap, targetW: Int, targetH: Int): Bitmap {
        if (src.width == targetW && src.height == targetH) return src

        val scaleX = targetW.toFloat() / src.width
        val scaleY = targetH.toFloat() / src.height
        val scale = maxOf(scaleX, scaleY) // fill — use max to cover fully

        val scaledW = (src.width * scale).toInt()
        val scaledH = (src.height * scale).toInt()

        val output = Bitmap.createBitmap(targetW, targetH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

        // Center the scaled image so any crop is symmetrical
        val offsetX = (targetW - scaledW) / 2f
        val offsetY = (targetH - scaledH) / 2f

        val matrix = Matrix()
        matrix.setScale(scale, scale)
        matrix.postTranslate(offsetX, offsetY)

        canvas.drawBitmap(src, matrix, paint)
        return output
    }

    private fun handleGetScreenDimensions(result: MethodChannel.Result) {
        val ctx = appContext ?: run {
            result.error("NO_CONTEXT", "Application context unavailable", null)
            return
        }
        val windowManager = ctx.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        result.success(mapOf(
            "width" to metrics.widthPixels,
            "height" to metrics.heightPixels
        ))
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
            // Keep screen on while the app is visible over the lock screen
            if (show) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
