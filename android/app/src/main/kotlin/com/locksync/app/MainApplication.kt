package com.locksync.app

import android.app.Application

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
 * platform channel is unavailable the Dart side already catches the error and
 * falls back to persisting the image for the next cold start.
 *
 * NOTE: FlutterApplication (io.flutter.app.FlutterApplication) was removed in
 * Flutter's v2 embedding — extending it causes a ClassNotFoundException crash
 * at startup.  We extend plain [Application] instead, which is sufficient for
 * the v2 / v3 embedding used here.
 */
class MainApplication : Application()
