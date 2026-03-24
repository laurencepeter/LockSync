import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'display_name_screen.dart';
import 'memory_wall_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final storage = ws.storage;

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
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 8),

                    // Profile section
                    _SectionHeader(title: 'PROFILE'),
                    _SettingsTile(
                      icon: Icons.person_rounded,
                      title: 'Display Name',
                      subtitle: storage.displayName ?? 'Not set',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const DisplayNameScreen(isInitialSetup: false),
                          ),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.palette_rounded,
                      title: 'Your Color',
                      subtitle: 'Color used for your text & drawings',
                      trailing: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(storage.userColor),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      onTap: () {
                        // Reuse the color picker from canvas
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Change your color from the Canvas drawing tool.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.text_fields_rounded,
                      title: 'Your Font',
                      subtitle: storage.userFont,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Change your font from the Canvas text tool.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Lock Screen section
                    _SectionHeader(title: 'LOCK SCREEN'),
                    if (Platform.isAndroid)
                      _SettingsToggle(
                        icon: Icons.wallpaper_rounded,
                        title: 'Auto-update Lock Screen',
                        subtitle:
                            'Automatically set wallpaper when partner sends updates',
                        value: storage.autoUpdateWallpaper,
                        onChanged: (v) {
                          storage.setAutoUpdateWallpaper(v);
                          setState(() {});
                        },
                      ),
                    if (Platform.isIOS)
                      _SettingsTile(
                        icon: Icons.photo_library_rounded,
                        title: 'How to Set Lock Screen',
                        subtitle:
                            'Guide for setting your lock screen on iOS',
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A2E),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              title: const Text('Set Lock Screen',
                                  style: TextStyle(color: Colors.white)),
                              content: const Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '1. Tap "Set as Lock Screen" from the canvas\n'
                                    '2. The image will be saved to Photos\n'
                                    '3. Open Settings → Wallpaper\n'
                                    '4. Tap "Add New Wallpaper"\n'
                                    '5. Select the saved image\n'
                                    '6. Set as Lock Screen',
                                    style: TextStyle(
                                        color: Colors.white70, height: 1.8),
                                  ),
                                ],
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Got it!'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 24),

                    // Memories section
                    _SectionHeader(title: 'MEMORIES'),
                    _SettingsTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Memory Wall',
                      subtitle: 'View saved canvas snapshots',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MemoryWallScreen()),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Theme section
                    _SectionHeader(title: 'THEMES'),
                    _ThemeSelector(
                      currentTheme: storage.activeTheme,
                      onSelect: (theme) {
                        storage.setActiveTheme(theme);
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 24),

                    // Connection section
                    _SectionHeader(title: 'CONNECTION'),
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Pair ID',
                      subtitle: ws.pairId ?? 'Not paired',
                      onTap: null,
                    ),
                    _SettingsTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Partner',
                      subtitle: ws.partnerDisplayName ?? ws.partnerId ?? 'Unknown',
                      onTap: null,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white38, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
                if (onTap != null && trailing == null)
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white38, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: LockSyncTheme.accentColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  final String currentTheme;
  final ValueChanged<String> onSelect;

  const _ThemeSelector({
    required this.currentTheme,
    required this.onSelect,
  });

  static const _themes = [
    {
      'id': 'default',
      'name': 'Default',
      'colors': [Color(0xFF6C5CE7), Color(0xFF00CEC9)],
    },
    {
      'id': 'neon_night',
      'name': 'Neon Night',
      'colors': [Color(0xFFFF006E), Color(0xFF8338EC)],
    },
    {
      'id': 'soft_pastel',
      'name': 'Soft Pastel',
      'colors': [Color(0xFFFFB6C1), Color(0xFFB0E0E6)],
    },
    {
      'id': 'minimal_bw',
      'name': 'Minimal B&W',
      'colors': [Color(0xFF333333), Color(0xFFCCCCCC)],
    },
    {
      'id': 'retro_arcade',
      'name': 'Retro Arcade',
      'colors': [Color(0xFF00FF41), Color(0xFFFF00FF)],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _themes.length,
        itemBuilder: (ctx, i) {
          final theme = _themes[i];
          final id = theme['id'] as String;
          final name = theme['name'] as String;
          final colors = theme['colors'] as List<Color>;
          final isSelected = currentTheme == id;

          return GestureDetector(
            onTap: () => onSelect(id),
            child: Container(
              width: 100,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.all(8),
              child: Text(
                name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
