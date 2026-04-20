/// Developer Screen — accessible via Settings hidden menu with PIN 1793.
///
/// Exposes:
///   • A list of saved dev profiles (one per test partner).  Tap "Activate"
///     to switch the live WebSocket connection to that profile so you can
///     interact with that partner's full session (text, canvas, mood, etc.).
///   • A "Pair New Profile" section backed by the embedded PairingScreen.
///     After pairing you are prompted to label the new profile before it is
///     saved to the list.
///   • Dev-only toggles (screenshot blocking) that must NOT appear in the
///     regular Settings screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'pairing_screen.dart';

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  bool _screenshotDevMode = false;

  /// Whether the "Pair New Profile" section is expanded.
  bool _pairSectionExpanded = false;

  /// Non-null while a profile-switch is in progress.
  String? _switchingProfileId;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WebSocketService>().storage;
    _screenshotDevMode = storage.screenshotDevMode;
  }

  Future<void> _toggleScreenshotDevMode(bool value) async {
    final storage = context.read<WebSocketService>().storage;
    await storage.setScreenshotDevMode(value);
    setState(() => _screenshotDevMode = value);
  }

  // ── After a new pair completes, prompt for a label and save the profile ──

  Future<void> _onPairComplete(WebSocketService ws) async {
    // Determine a default label from the partner name (may be null until sync).
    final defaultLabel =
        ws.partnerDisplayName ?? ws.storage.partnerName ?? 'Profile';

    final label = await _showLabelDialog(defaultLabel);
    if (!mounted) return;

    final profile = await ws.saveCurrentSessionAsDevProfile(label ?? defaultLabel);

    setState(() {
      _pairSectionExpanded = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile "${profile.label}" saved and activated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _showLabelDialog(String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name this profile',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Alice, Test User 2…',
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Profile actions ───────────────────────────────────────────────────────

  Future<void> _activateProfile(WebSocketService ws, DevProfile profile) async {
    setState(() => _switchingProfileId = profile.id);
    await ws.switchDevProfile(profile);
    if (mounted) setState(() => _switchingProfileId = null);
  }

  Future<void> _renameProfile(WebSocketService ws, DevProfile profile) async {
    final label = await _showLabelDialog(profile.label);
    if (label != null && mounted) {
      await ws.renameDevProfile(profile.id, label);
      setState(() {});
    }
  }

  Future<void> _deleteProfile(WebSocketService ws, DevProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete profile?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${profile.label}"?\nThis only deletes the local profile — '
          'the pairing on the server is not affected.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ws.deleteDevProfile(profile.id);
      setState(() {});
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final profiles = ws.devProfiles;
    final activeId = ws.activeDevProfileId;

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────
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

              // ── Body (scrollable) ──────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // ── Partner Switcher (shown when profiles exist) ───
                    if (profiles.isNotEmpty) ...[
                      _SectionHeader(title: 'ACTIVE PARTNER'),
                      _PartnerSwitcherCard(
                        profiles: profiles,
                        activeId: activeId,
                        switchingId: _switchingProfileId,
                        onSwitch: (p) => _activateProfile(ws, p),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Dev-only settings ──────────────────────────────
                    _SectionHeader(title: 'SETTINGS'),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        secondary: Icon(
                          Icons.screenshot_monitor_rounded,
                          color: _screenshotDevMode
                              ? Colors.orange
                              : Colors.white38,
                          size: 22,
                        ),
                        title: const Text(
                          'Allow Screenshots in Moments',
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        subtitle: Text(
                          _screenshotDevMode
                              ? 'Screenshot blocking disabled'
                              : 'Screenshots blocked (default)',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        value: _screenshotDevMode,
                        onChanged: _toggleScreenshotDevMode,
                        activeColor: Colors.orange,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Profiles ───────────────────────────────────────
                    _SectionHeader(title: 'TEST PROFILES'),

                    if (profiles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No profiles yet. Pair with a test user below\n'
                          'to create your first profile.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13),
                        ),
                      ),

                    for (final profile in profiles)
                      _ProfileTile(
                        profile: profile,
                        isActive: profile.id == activeId,
                        isSwitching: _switchingProfileId == profile.id,
                        onActivate: () => _activateProfile(ws, profile),
                        onRename: () => _renameProfile(ws, profile),
                        onDelete: () => _deleteProfile(ws, profile),
                      ),

                    const SizedBox(height: 16),

                    // ── Active session info ────────────────────────────
                    if (ws.status == ConnectionStatus.paired)
                      _ActiveSessionBanner(ws: ws, activeProfileId: activeId),

                    const SizedBox(height: 8),

                    // ── Pair new profile ───────────────────────────────
                    _SectionHeader(title: 'PAIR NEW PROFILE'),

                    GestureDetector(
                      onTap: () => setState(
                          () => _pairSectionExpanded = !_pairSectionExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _pairSectionExpanded
                              ? LockSyncTheme.primaryColor.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _pairSectionExpanded
                                ? LockSyncTheme.primaryColor.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_link_rounded,
                              color: _pairSectionExpanded
                                  ? LockSyncTheme.primaryColor
                                  : Colors.white54,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _pairSectionExpanded
                                    ? 'Pair with a new test user'
                                    : 'Tap to pair with a new test user…',
                                style: TextStyle(
                                  color: _pairSectionExpanded
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              _pairSectionExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: Colors.white38,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_pairSectionExpanded) ...[
                      const SizedBox(height: 8),
                      _EmbeddedPairing(onPairComplete: () => _onPairComplete(ws)),
                    ],

                    const SizedBox(height: 32),
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

// ── Widgets ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _ActiveSessionBanner extends StatelessWidget {
  final WebSocketService ws;
  final String? activeProfileId;
  const _ActiveSessionBanner(
      {required this.ws, required this.activeProfileId});

  @override
  Widget build(BuildContext context) {
    final label = activeProfileId == null
        ? null
        : ws.devProfiles
            .where((p) => p.id == activeProfileId)
            .map((p) => p.label)
            .firstOrNull;
    final partnerName = ws.partnerDisplayName ?? ws.storage.partnerName;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 16, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label != null
                  ? 'Active profile: $label'
                  : partnerName != null
                      ? 'Live session with $partnerName'
                      : 'Paired (no profile selected)',
              style:
                  const TextStyle(color: Colors.greenAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final DevProfile profile;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback onActivate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.isSwitching,
    required this.onActivate,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive || isSwitching ? null : onActivate,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? LockSyncTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? LockSyncTheme.primaryColor.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            // Active indicator dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.greenAccent : Colors.white24,
              ),
            ),
            const SizedBox(width: 12),

            // Profile info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                  ),
                  if (profile.partnerDisplayName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Partner: ${profile.partnerDisplayName}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Pair ID: ${profile.pairId.length > 12 ? '${profile.pairId.substring(0, 12)}…' : profile.pairId}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),

            // Actions
            if (isSwitching)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (!isActive)
                TextButton(
                  onPressed: onActivate,
                  style: TextButton.styleFrom(
                    foregroundColor: LockSyncTheme.primaryColor,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Activate',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: Colors.white38, size: 20),
                color: const Color(0xFF1A1A2E),
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Rename',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Carousel card showing the currently-active partner with prev/next arrows.
/// Allows quick cycling through all saved profiles without scrolling.
class _PartnerSwitcherCard extends StatelessWidget {
  final List<DevProfile> profiles;
  final String? activeId;
  final String? switchingId;
  final void Function(DevProfile) onSwitch;

  const _PartnerSwitcherCard({
    required this.profiles,
    required this.activeId,
    required this.switchingId,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final activeIdx = activeId == null
        ? -1
        : profiles.indexWhere((p) => p.id == activeId);
    final hasActive = activeIdx >= 0;
    final current = hasActive ? profiles[activeIdx] : null;

    final prevIdx = profiles.isEmpty
        ? -1
        : activeIdx <= 0
            ? profiles.length - 1
            : activeIdx - 1;
    final nextIdx = profiles.isEmpty
        ? -1
        : activeIdx < 0 || activeIdx >= profiles.length - 1
            ? 0
            : activeIdx + 1;

    final isSwitching = switchingId != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: LockSyncTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: LockSyncTheme.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          // ── Prev arrow ──────────────────────────────────────────────
          _ArrowButton(
            icon: Icons.chevron_left_rounded,
            enabled: !isSwitching && profiles.length > 1,
            onTap: prevIdx >= 0 ? () => onSwitch(profiles[prevIdx]) : null,
          ),

          // ── Active profile display ───────────────────────────────────
          Expanded(
            child: isSwitching
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasActive ? current!.label : 'None',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasActive && current!.partnerDisplayName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'with ${current.partnerDisplayName}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        profiles.length > 1
                            ? '${hasActive ? activeIdx + 1 : 0} / ${profiles.length}'
                            : '1 profile',
                        style: TextStyle(
                          color: LockSyncTheme.primaryColor.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),

          // ── Next arrow ──────────────────────────────────────────────
          _ArrowButton(
            icon: Icons.chevron_right_rounded,
            enabled: !isSwitching && profiles.length > 1,
            onTap: nextIdx >= 0 ? () => onSwitch(profiles[nextIdx]) : null,
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _ArrowButton({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48,
        height: 64,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 32,
          color: enabled
              ? Colors.white.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}

/// Embeds the pairing UI (without its own Scaffold/header) and fires
/// [onPairComplete] when the WebSocket transitions to [ConnectionStatus.paired].
class _EmbeddedPairing extends StatefulWidget {
  final VoidCallback onPairComplete;
  const _EmbeddedPairing({required this.onPairComplete});

  @override
  State<_EmbeddedPairing> createState() => _EmbeddedPairingState();
}

class _EmbeddedPairingState extends State<_EmbeddedPairing> {
  StreamSubscription<void>? _pairingSub;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    // Listen to the dedicated "new pairing" stream so we fire exactly once
    // per completed pairing — even when the device was already in "paired"
    // status before the developer re-paired with a second test account.
    _pairingSub = ws.onNewPairing.listen((_) {
      if (mounted) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onPairComplete());
      }
    });
  }

  @override
  void dispose() {
    _pairingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WebSocketService>(); // keep widget in the rebuild tree

    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: const PairingScreen(disableAutoNavigate: true),
    );
  }
}
