import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'providers/app_providers.dart';
import 'services/local_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait for consistent canvas dimensions.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0D1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize local storage before the widget tree is built.
  final storage = LocalStorageService();
  await storage.initialize();

  runApp(
    ProviderScope(
      overrides: [
        // Provide the initialized storage instance to the widget tree.
        localStorageProvider.overrideWithValue(storage),
      ],
      child: const LockSyncApp(),
    ),
  );
}
