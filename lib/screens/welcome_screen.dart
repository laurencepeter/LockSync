import 'dart:math' as math;
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
  late AnimationController _spinController;
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
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

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
    _spinController.dispose();
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
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Spinning sync ring
                          AnimatedBuilder(
                            animation: _spinController,
                            builder: (_, __) => Transform.rotate(
                              angle: _spinController.value * 2 * math.pi,
                              child: CustomPaint(
                                size: const Size(104, 104),
                                painter: _SyncRingPainter(
                                  color: LockSyncTheme.accentColor,
                                ),
                              ),
                            ),
                          ),
                          // Lock circle
                          Container(
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
                              size: 34,
                            ),
                          ),
                        ],
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

class _SyncRingPainter extends CustomPainter {
  final Color color;
  _SyncRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final arrowLen = radius * 0.28;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    const gapRad = 0.38;

    // Two arcs each sweeping ~(π - gap), placed 180° apart
    // Arc 1: starts just past top, goes clockwise ~160°
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 + gapRad / 2,
      math.pi - gapRad,
      false,
      paint,
    );

    // Arc 2: starts just past bottom, goes clockwise ~160°
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi / 2 + gapRad / 2,
      math.pi - gapRad,
      false,
      paint,
    );

    // Arrowhead at end of arc 1 (angle = π/2 - gapRad/2)
    _drawArrowhead(canvas, center, radius, math.pi / 2 - gapRad / 2, arrowLen, paint);

    // Arrowhead at end of arc 2 (angle = -π/2 - gapRad/2)
    _drawArrowhead(canvas, center, radius, -math.pi / 2 - gapRad / 2, arrowLen, paint);
  }

  void _drawArrowhead(Canvas canvas, Offset center, double radius, double angle,
      double arrowLen, Paint basePaint) {
    final tip = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    // Clockwise tangent direction at this angle
    final tangent = angle + math.pi / 2;
    const spread = 0.45; // ~26°

    final wing1 = Offset(
      tip.dx - arrowLen * math.cos(tangent - spread),
      tip.dy - arrowLen * math.sin(tangent - spread),
    );
    final wing2 = Offset(
      tip.dx - arrowLen * math.cos(tangent + spread),
      tip.dy - arrowLen * math.sin(tangent + spread),
    );

    final arrowPaint = Paint()
      ..color = basePaint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = basePaint.strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(wing1.dx, wing1.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(wing2.dx, wing2.dy);

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(_SyncRingPainter old) => old.color != color;
}
