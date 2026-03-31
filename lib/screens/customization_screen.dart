import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';

// ─── Font choices available for UI customization ──────────────────────────────

const _kAvailableFonts = [
  'Inter',
  'Poppins',
  'Montserrat',
  'Roboto',
  'Lato',
  'Nunito',
  'Raleway',
  'Space Grotesk',
  'DM Sans',
  'Outfit',
];

// ─── CustomizationScreen ──────────────────────────────────────────────────────

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  late Color _primaryColor;
  late Color _accentColor;
  late String _font;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WebSocketService>().storage;
    _primaryColor = Color(storage.menuPrimaryColor ?? 0xFF6C5CE7);
    _accentColor = Color(storage.menuAccentColor ?? 0xFF00CEC9);
    _font = storage.menuFont ?? 'Inter';
  }

  Future<void> _save() async {
    final storage = context.read<WebSocketService>().storage;
    await storage.setMenuPrimaryColor(_primaryColor.value);
    await storage.setMenuAccentColor(_accentColor.value);
    await storage.setMenuFont(_font);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customization saved — restart the app to apply.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _changed = false);
    }
  }

  Future<void> _reset() async {
    final storage = context.read<WebSocketService>().storage;
    await storage.setMenuPrimaryColor(null);
    await storage.setMenuAccentColor(null);
    await storage.setMenuFont(null);
    setState(() {
      _primaryColor = const Color(0xFF6C5CE7);
      _accentColor = const Color(0xFF00CEC9);
      _font = 'Inter';
      _changed = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset to defaults — restart the app to apply.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _pickColor({required bool isPrimary}) {
    Color current = isPrimary ? _primaryColor : _accentColor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isPrimary ? 'Primary Color' : 'Accent Color',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => current = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (isPrimary) {
                  _primaryColor = current;
                } else {
                  _accentColor = current;
                }
                _changed = true;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    const Text(
                      'Customization',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_changed)
                      TextButton(
                        onPressed: _save,
                        child: Text('Save',
                            style: TextStyle(
                                color: LockSyncTheme.primaryColor,
                                fontWeight: FontWeight.w700)),
                      )
                    else
                      const SizedBox(width: 56),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 8),

                    // ── Colors ────────────────────────────────────────────
                    _SectionHeader('COLORS'),

                    _ColorTile(
                      label: 'Primary Color',
                      subtitle:
                          'Buttons, highlights, active elements',
                      color: _primaryColor,
                      onTap: () => _pickColor(isPrimary: true),
                    ),

                    _ColorTile(
                      label: 'Accent Color',
                      subtitle: 'Secondary highlights & toggles',
                      color: _accentColor,
                      onTap: () => _pickColor(isPrimary: false),
                    ),

                    const SizedBox(height: 24),

                    // ── Font ─────────────────────────────────────────────
                    _SectionHeader('FONT'),

                    ..._kAvailableFonts.map((font) {
                      final selected = _font == font;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _font = font;
                          _changed = true;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? _primaryColor.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? _primaryColor.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'The quick brown fox',
                                  style: GoogleFonts.getFont(
                                    font,
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                font,
                                style: TextStyle(
                                  color: selected
                                      ? _primaryColor
                                      : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle_rounded,
                                    color: _primaryColor, size: 18),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 32),

                    // ── Reset ─────────────────────────────────────────────
                    OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Reset to Defaults'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title,
        style: TextStyle(
          color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ColorTile({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.color_lens_rounded,
                color: Colors.white.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}

