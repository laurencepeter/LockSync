import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/websocket_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/sync_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  runApp(LockSyncApp(storage: storage));
}

class LockSyncApp extends StatelessWidget {
  final StorageService storage;
  const LockSyncApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final ws = WebSocketService(storage: storage);
        ws.connect();
        return ws;
      },
      child: MaterialApp(
        title: 'LockSync',
        debugShowCheckedModeBanner: false,
        theme: LockSyncTheme.darkTheme,
        home: _InitialRoute(storage: storage),
      ),
    );
  }
}

/// Decides the initial screen based on saved session state.
class _InitialRoute extends StatelessWidget {
  final StorageService storage;
  const _InitialRoute({required this.storage});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();

    // If already paired from a previous session, go straight to sync
    if (ws.status == ConnectionStatus.paired) {
      return const SyncScreen();
    }

    return const WelcomeScreen();
  }
}
