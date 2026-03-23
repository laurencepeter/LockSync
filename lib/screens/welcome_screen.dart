import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import '../widgets/pulse_ring.dart';
import 'pairing_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _buttonFadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _buttonFadeAnim = CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _navigateToPairing(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PairingScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final isConnecting = ws.status == ConnectionStatus.connecting;
    final isConnected = ws.status == ConnectionStatus.connected ||
        ws.status == ConnectionStatus.paired;

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Animated logo
                FadeTransition(
                  opacity: _fadeAnim,
                  child: PulseRing(
                    size: 180,
                    color: LockSyncTheme.primaryColor,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            LockSyncTheme.primaryColor,
                            LockSyncTheme.accentColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: LockSyncTheme.primaryColor
                                .withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      children: [
                        Text(
                          'LockSync',
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Share your lock screen in real-time\nwith the person who matters most',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    height: 1.5,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Connection status indicator
                FadeTransition(
                  opacity: _buttonFadeAnim,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: isConnected
                          ? LockSyncTheme.accentColor.withValues(alpha: 0.15)
                          : isConnecting
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected
                                ? LockSyncTheme.accentColor
                                : isConnecting
                                    ? Colors.amber
                                    : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConnected
                              ? 'Connected to server'
                              : isConnecting
                                  ? 'Connecting...'
                                  : 'Disconnected',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: isConnected
                                        ? LockSyncTheme.accentColor
                                        : isConnecting
                                            ? Colors.amber
                                            : Colors.red,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Pair button
                FadeTransition(
                  opacity: _buttonFadeAnim,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed:
                          isConnected ? () => _navigateToPairing(context) : null,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_rounded, size: 22),
                          SizedBox(width: 10),
                          Text('Pair Your Devices'),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Reconnect button when disconnected
                if (!isConnected && !isConnecting)
                  FadeTransition(
                    opacity: _buttonFadeAnim,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () => ws.connect(),
                        child: const Text('Retry Connection'),
                      ),
                    ),
                  ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
