import 'package:flutter/material.dart';

class AnimatedGradientBg extends StatefulWidget {
  final Widget child;

  const AnimatedGradientBg({super.key, required this.child});

  @override
  State<AnimatedGradientBg> createState() => _AnimatedGradientBgState();
}

class _AnimatedGradientBgState extends State<AnimatedGradientBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment(
                0.5 + _controller.value * 0.5,
                1.0 - _controller.value * 0.3,
              ),
              colors: const [
                Color(0xFF0F0F1A),
                Color(0xFF1A1A3E),
                Color(0xFF0F0F1A),
              ],
              stops: [
                0.0,
                0.3 + _controller.value * 0.4,
                1.0,
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}
