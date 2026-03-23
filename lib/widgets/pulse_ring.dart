import 'package:flutter/material.dart';

class PulseRing extends StatefulWidget {
  final double size;
  final Color color;
  final Widget child;

  const PulseRing({
    super.key,
    this.size = 200,
    this.color = const Color(0xFF6C5CE7),
    required this.child,
  });

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _PulseRingPainter(
              progress: _controller.value,
              color: widget.color,
            ),
            child: Center(child: widget.child),
          );
        },
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulseRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final p = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * 0.4 + maxRadius * 0.6 * p;
      final opacity = (1.0 - p) * 0.3;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.progress != progress;
}
