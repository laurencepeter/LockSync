package com.locksync.app

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

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
 */
class MainApplication : FlutterApplication()
