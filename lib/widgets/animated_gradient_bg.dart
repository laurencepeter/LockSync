import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';

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
    String themeId = 'default';
    try {
      themeId = context
          .read<WebSocketService>()
          .storage
          .activeTheme;
    } catch (_) {
      // Provider not available; fall back to default theme
    }
    final colors = LockSyncTheme.gradientColors(themeId);

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
              colors: colors,
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
