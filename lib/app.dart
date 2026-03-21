import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/splash/splash_screen.dart';
import 'features/connect/connect_devices_screen.dart';
import 'features/space/create_space_screen.dart';
import 'features/space/join_space_screen.dart';
import 'features/editor/homescreen_editor.dart';
import 'features/members/members_status_screen.dart';
import 'features/settings/settings_screen.dart';

// ── Router ────────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/connect',
      builder: (_, __) => const ConnectDevicesScreen(),
    ),
    GoRoute(
      path: '/create-space',
      builder: (_, __) => const CreateSpaceScreen(),
    ),
    GoRoute(
      path: '/join-space',
      builder: (_, __) => const JoinSpaceScreen(),
    ),
    GoRoute(
      path: '/editor',
      builder: (_, __) => const HomescreenEditor(),
    ),
    GoRoute(
      path: '/members',
      builder: (_, __) => const MembersStatusScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: const Color(0xFF0D0D1A),
    body: Center(
      child: Text(
        'Page not found: ${state.uri}',
        style: const TextStyle(color: Colors.white),
      ),
    ),
  ),
);

// ── App ───────────────────────────────────────────────────────────────────────

class LockSyncApp extends ConsumerWidget {
  const LockSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'LockSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFFFF6584),
          surface: Color(0xFF1A1A2E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1A1A2E),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1A1A2E),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
          contentTextStyle: TextStyle(color: Colors.white70),
        ),
      ),
      routerConfig: _router,
    );
  }
}
