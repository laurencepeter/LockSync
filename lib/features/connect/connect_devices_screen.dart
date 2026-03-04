import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Entry screen: choose between creating a new space or joining one.
class ConnectDevicesScreen extends StatelessWidget {
  const ConnectDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              // Header
              const Text(
                'Connect\nDevices',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Create a shared space or join an existing one\nwith a QR code or connection code.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              // Create space card
              _ConnectOptionCard(
                icon: Icons.add_circle_rounded,
                iconColor: const Color(0xFF6C63FF),
                title: 'Create Space',
                subtitle: 'Start a new shared screen. Share the QR code with your partner.',
                onTap: () => context.push('/create-space'),
              ),
              const SizedBox(height: 16),
              // Join space card
              _ConnectOptionCard(
                icon: Icons.qr_code_scanner_rounded,
                iconColor: const Color(0xFFFF6584),
                title: 'Join Space',
                subtitle: 'Scan a QR code or enter a connection code to join an existing space.',
                onTap: () => context.push('/join-space'),
              ),
              const Spacer(),
              Center(
                child: Text(
                  'Devices must be on the same local network\nfor peer-to-peer connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectOptionCard extends StatelessWidget {
  const _ConnectOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
