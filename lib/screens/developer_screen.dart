/// Developer Screen — accessible via Settings hidden menu with PIN 1793.
///
/// Exposes the full pairing UI so a developer / power user can pair with a
/// different device without going through the welcome flow.  Pairing from
/// here replaces the existing pair session (same as joining on first launch).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/websocket_service.dart';
import '../widgets/animated_gradient_bg.dart';
import 'pairing_screen.dart';

class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        const Text(
                          'Developer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'DEV MODE',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Status chip
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: ws.status == ConnectionStatus.paired
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ws.status == ConnectionStatus.paired
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ws.status == ConnectionStatus.paired
                          ? Icons.link_rounded
                          : Icons.link_off_rounded,
                      size: 16,
                      color: ws.status == ConnectionStatus.paired
                          ? Colors.green
                          : Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ws.status == ConnectionStatus.paired
                          ? 'Currently paired — new pair will replace this session'
                          : 'Not paired',
                      style: TextStyle(
                        color: ws.status == ConnectionStatus.paired
                            ? Colors.green
                            : Colors.amber,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              const Divider(color: Colors.white10),

              // Reuse the full pairing screen content
              const Expanded(child: _EmbeddedPairing()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Embeds the PairingScreen widget directly (no outer Scaffold) so we get the
/// full Generate / Enter Code flow inside the Developer screen.
class _EmbeddedPairing extends StatelessWidget {
  const _EmbeddedPairing();

  @override
  Widget build(BuildContext context) {
    return const PairingScreen();
  }
}
