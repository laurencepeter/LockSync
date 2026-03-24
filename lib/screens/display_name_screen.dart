import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'sync_screen.dart';

class DisplayNameScreen extends StatefulWidget {
  final bool isInitialSetup;

  const DisplayNameScreen({super.key, this.isInitialSetup = false});

  @override
  State<DisplayNameScreen> createState() => _DisplayNameScreenState();
}

class _DisplayNameScreenState extends State<DisplayNameScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  late AnimationController _enterAnim;

  @override
  void initState() {
    super.initState();
    _enterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    final storage = context.read<WebSocketService>().storage;
    final existing = storage.displayName;
    if (existing != null) {
      _nameController.text = existing;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _enterAnim.dispose();
    super.dispose();
  }

  void _saveName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final ws = context.read<WebSocketService>();
    ws.sendDisplayName(name);

    if (widget.isInitialSetup) {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SyncScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                  CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic),
                ),
                child: child,
              ),
            );
          },
        ),
        (route) => false,
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterAnim,
              curve: Curves.easeOut,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  if (!widget.isInitialSetup)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),

                  const Spacer(flex: 2),

                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          LockSyncTheme.primaryColor,
                          LockSyncTheme.accentColor,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              LockSyncTheme.primaryColor.withValues(alpha: 0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    widget.isInitialSetup
                        ? 'What should your partner call you?'
                        : 'Edit Display Name',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This name will be visible to your partner',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  TextField(
                    controller: _nameController,
                    textAlign: TextAlign.center,
                    maxLength: 20,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Your name',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 20,
                      ),
                      counterStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    onSubmitted: (_) => _saveName(),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveName,
                      child: Text(
                        widget.isInitialSetup ? 'Continue' : 'Save',
                      ),
                    ),
                  ),

                  if (widget.isInitialSetup) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // Skip and go to sync screen
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const SyncScreen()),
                          (route) => false,
                        );
                      },
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
