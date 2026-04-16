package com.locksync.app

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.locksync.locksync.R

/**
 * Receives [Intent.ACTION_SCREEN_ON] broadcasts (registered dynamically in
 * [MainApplication]) and brings LockSync over the lock screen whenever the
 * display wakes up while the device is locked and the user has an active
 * pair session.
 *
 * WHY: [MainActivity] declares showWhenLocked="true" and turnScreenOn="true",
 * but those flags only work when the activity is already at the top of the
 * task stack.  If the user switched to another app before locking, LockSync
 * is buried in the back-stack and those flags never fire.  Sending a
 * full-screen intent notification on every screen-on event is the only
 * Android-supported mechanism that reliably brings an activity to the front
 * from a background context on API 29+.
 *
 * FLOW:
 *  1. Screen turns on  →  ACTION_SCREEN_ON fires
 *  2. Check: device is locked  (KeyguardManager.isKeyguardLocked)
 *  3. Check: user is paired    (SharedPreferences key set by Flutter)
 *  4. Post a fullScreenIntent notification  →  Android launches MainActivity
 *     over the keyguard because showWhenLocked="true" is set on the activity.
 *
 * The notification is auto-cancelled once the user taps / dismisses it so no
 * persistent badge or shade entry remains.
 */
class ScreenOnReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_SCREEN_ON) return

        // Only trigger when the lock screen is actually active.
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!km.isKeyguardLocked) return

        // Only trigger when the user has an active pair session.
        // Flutter shared_preferences stores all keys with a "flutter." prefix.
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val accessToken = prefs.getString("flutter.locksync_access_token", null)
        if (accessToken.isNullOrEmpty()) return

        ensureNotificationChannel(context)
        postWakeNotification(context)
    }

    // ── Notification channel ─────────────────────────────────────────────────

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "LockSync Lock Screen",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Wakes LockSync on the lock screen when the display turns on"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    // ── Full-screen intent notification ──────────────────────────────────────

    private fun postWakeNotification(context: Context) {
        // Bring the existing MainActivity to the front if it exists, or start a
        // new one.  FLAG_ACTIVITY_REORDER_TO_FRONT moves it from the back-stack
        // to the foreground without creating a second instance.
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }

        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        val pendingIntent = PendingIntent.getActivity(
            context, REQ_CODE, launchIntent, piFlags
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("LockSync")
            .setContentText("Your shared space is ready")
            // fullScreenIntent with highPriority=true causes Android to launch
            // the activity immediately over the lock screen rather than showing
            // a notification card.
            .setFullScreenIntent(pendingIntent, /* highPriority= */ true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Auto-cancel so no persistent notification remains after the user
            // interacts with or dismisses the lock screen.
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, notif)
    }

    companion object {
        const val CHANNEL_ID = "locksync_wake"
        private const val NOTIF_ID   = 1002
        private const val REQ_CODE   = 1001
    }
}
