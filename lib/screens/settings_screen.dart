import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/crash_logger.dart';
import '../services/wallpaper_service.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'customization_screen.dart';
import 'developer_screen.dart';
import 'diagnostics_screen.dart';
import 'display_name_screen.dart';
import 'memory_wall_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Hidden developer menu: tap the "Settings" title 5 times → PIN dialog.
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;

  // Whether any crashes have been recorded — drives a small warning dot in
  // the Diagnostics tile so the user knows to check it.
  bool _hasCrashLog = false;

  // Tracks whether battery optimisation is already disabled for this app.
  bool _batteryOptExempt = true;

  @override
  void initState() {
    super.initState();
    _checkCrashLog();
    _checkBatteryOpt();
  }

  Future<void> _checkBatteryOpt() async {
    final exempt = await WallpaperService.isBatteryOptimizationExempt();
    if (!mounted) return;
    if (exempt != _batteryOptExempt) setState(() => _batteryOptExempt = exempt);
  }

  Future<void> _checkCrashLog() async {
    final any = await CrashLogger.hasAny();
    if (!mounted) return;
    if (any != _hasCrashLog) setState(() => _hasCrashLog = any);
  }

  void _onTitleTap() {
    final now = DateTime.now();
    // Reset counter if more than 2 s between taps
    if (_lastTitleTap != null &&
        now.difference(_lastTitleTap!).inSeconds > 2) {
      _titleTapCount = 0;
    }
    _lastTitleTap = now;
    _titleTapCount++;
    if (_titleTapCount >= 5) {
      _titleTapCount = 0;
      HapticFeedback.mediumImpact();
      _showPinDialog();
    }
  }

  /// Show the PIN entry dialog.
  /// 0000 → Customization   (colors & fonts)
  /// 1793 → Developer mode  (pairing)
  void _showPinDialog() {
    final pinController = TextEditingController();
    // Explicit FocusNode so we can force keyboard open on devices where
    // autofocus inside an AlertDialog doesn't trigger the IME reliably.
    final pinFocusNode = FocusNode();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter PIN',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: pinController,
          focusNode: pinFocusNode,
          autofocus: true,
          // TextInputType.visiblePassword keeps digits-only appearance while
          // still showing the full keyboard on devices where TextInputType.number
          // silently fails to open the IME.
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          maxLength: 4,
          obscureText: true,
          style: const TextStyle(
              color: Colors.white, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••',
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                letterSpacing: 8),
          ),
          // Defer navigation to the next frame so the dialog close animation
          // completes before we push a new route — prevents the "flash then
          // disappear" effect caused by Navigator.push racing with pop.
          onSubmitted: (pin) {
            Navigator.pop(ctx);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _handlePin(pin);
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinController.text;
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handlePin(pin);
              });
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    ).whenComplete(() {
      pinController.dispose();
      pinFocusNode.dispose();
    });

    // Force the keyboard open after the dialog's widget tree is fully built.
    // Some Android devices (especially those with aggressive battery policies)
    // ignore autofocus inside AlertDialog until we explicitly request focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) pinFocusNode.requestFocus();
    });
  }

  void _handlePin(String pin) {
    switch (pin) {
      case '0000':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const CustomizationScreen()),
        );
        break;
      case '1793':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const DeveloperScreen()),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect PIN.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

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
                    GestureDetector(
                      onTap: _onTitleTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        'Settings',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
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
                    const _SectionHeader(title: 'PROFILE'),
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
                    const _SectionHeader(title: 'LOCK SCREEN'),
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
                    if (Platform.isAndroid)
                      _SettingsTile(
                        icon: Icons.battery_saver_rounded,
                        title: 'Battery Optimization',
                        subtitle: _batteryOptExempt
                            ? 'Disabled — service stays alive'
                            : 'Enabled — may kill background service',
                        trailing: _batteryOptExempt
                            ? null
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.orangeAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: _batteryOptExempt
                            ? null
                            : () async {
                                await WallpaperService
                                    .requestBatteryOptimizationExemption();
                                // Re-check after returning from settings
                                await _checkBatteryOpt();
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
                    const _SectionHeader(title: 'MEMORIES'),
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
                    const _SectionHeader(title: 'THEMES'),
                    _ThemeSelector(
                      currentTheme: storage.activeTheme,
                      onSelect: (theme) {
                        storage.setActiveTheme(theme);
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 24),

                    // Diagnostics section — surfaces captured crashes so the
                    // user can copy the stack trace and share it.
                    const _SectionHeader(title: 'DIAGNOSTICS'),
                    _SettingsTile(
                      icon: Icons.bug_report_rounded,
                      title: 'Crash Log',
                      subtitle: _hasCrashLog
                          ? 'A crash was recorded — tap to view'
                          : 'No crashes recorded',
                      trailing: _hasCrashLog
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DiagnosticsScreen()),
                        );
                        // Re-check after returning — user may have cleared
                        _checkCrashLog();
                      },
                    ),

                    const SizedBox(height: 24),

                    // Connection section
                    const _SectionHeader(title: 'CONNECTION'),
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
              activeThumbColor: LockSyncTheme.accentColor,
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
