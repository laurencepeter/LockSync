import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'canvas_screen.dart';
import 'settings_screen.dart';
import 'welcome_screen.dart';
import 'widgets_screen.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  late AnimationController _enterAnim;
  late AnimationController _typingAnim;
  String _lastSentText = '';

  // Floating reactions
  final List<_FloatingReaction> _floatingReactions = [];
  StreamSubscription? _reactionSub;
  StreamSubscription? _nudgeSub;
  StreamSubscription? _wallpaperPromptSub;

  @override
  void initState() {
    super.initState();
    _enterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _typingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _textController.addListener(_onTextChanged);

    // Listen for reactions / partner events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = context.read<WebSocketService>();
      _reactionSub = ws.onReaction.listen(_onReactionReceived);
      _nudgeSub = ws.onNudge.listen((_) => _onNudgeReceived());
      _wallpaperPromptSub =
          ws.onWallpaperPromptNeeded.listen((_) => _showWallpaperPermissionDialog());

      // Ask lock screen permission proactively (once, on first ever launch
      // after pairing) rather than waiting for the first canvas update.
      if (!ws.storage.autoWallpaperPrompted) {
        // Small delay so the screen has finished animating in first.
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _showWallpaperPermissionDialog();
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _enterAnim.dispose();
    _typingAnim.dispose();
    _reactionSub?.cancel();
    _nudgeSub?.cancel();
    _wallpaperPromptSub?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (text != _lastSentText) {
      _lastSentText = text;
      final ws = context.read<WebSocketService>();
      ws.sendText(text);
    }
  }

  void _onReactionReceived(Map<String, dynamic> data) {
    final emoji = data['emoji'] as String? ?? '\u2764\uFE0F';
    final x = (data['x'] as num?)?.toDouble() ?? 0.5;
    final y = (data['y'] as num?)?.toDouble() ?? 0.5;
    _showFloatingReaction(emoji, x, y);
  }

  void _showFloatingReaction(String emoji, double relX, double relY) {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final reaction = _FloatingReaction(
      emoji: emoji,
      x: relX * size.width,
      y: relY * size.height,
      createdAt: DateTime.now(),
    );
    setState(() => _floatingReactions.add(reaction));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _floatingReactions.remove(reaction));
      }
    });
  }

  void _onNudgeReceived() {
    HapticFeedback.heavyImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.vibration_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                '${context.read<WebSocketService>().partnerDisplayName ?? "Partner"} nudged you!',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: LockSyncTheme.primaryColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showWallpaperPermissionDialog() async {
    if (!mounted) return;
    final ws = context.read<WebSocketService>();
    // Mark as prompted so this only ever shows once
    await ws.storage.setAutoWallpaperPrompted(true);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: LockSyncTheme.primaryColor),
            SizedBox(width: 10),
            Text(
              'Live Lock Screen',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'LockSync can keep your lock screen updated with your shared canvas '
          'automatically — so every time your partner draws or adds a photo, '
          'it appears on your lock screen.\n\n'
          'You can turn this off anytime in Settings → Lock Screen.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ws.storage.setAutoUpdateWallpaper(false);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Not now',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: LockSyncTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await ws.storage.setAutoUpdateWallpaper(true);
              Navigator.pop(ctx);
              if (ws.partnerCanvasData != null) {
                ws.scheduleWallpaperUpdate(ws.partnerCanvasData!);
              }
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  void _sendReaction(String emoji, TapUpDetails details) {
    final size = MediaQuery.of(context).size;
    final relX = details.globalPosition.dx / size.width;
    final relY = details.globalPosition.dy / size.height;

    final ws = context.read<WebSocketService>();
    ws.sendReaction(emoji, relX, relY);

    // Show locally too
    _showFloatingReaction(emoji, relX, relY);
  }

  void _unpair(WebSocketService ws) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('Unpair Devices?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will disconnect you from your partner. You\'ll need to pair again.',
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ws.unpair();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  void _showMoodPicker() {
    const moods = [
      '\uD83D\uDE0A', '\uD83D\uDE0D', '\uD83E\uDD14', '\uD83D\uDE34',
      '\uD83D\uDE1E', '\uD83E\uDD2F', '\uD83E\uDD73', '\uD83D\uDE0E',
      '\uD83E\uDD22', '\uD83D\uDE21', '\uD83E\uDD7A', '\uD83D\uDE07',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How are you feeling?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: moods.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    context.read<WebSocketService>().sendMood(emoji);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(TapUpDetails details) {
    const reactions = [
      '\u2764\uFE0F', '\uD83D\uDE0D', '\uD83D\uDD25', '\uD83D\uDE02',
      '\uD83D\uDC4D', '\u2B50',
    ];

    final position = details.globalPosition;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx - 100, position.dy - 60, position.dx + 100, position.dy),
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: reactions.map((emoji) {
              return GestureDetector(
                onTapUp: (tapDetails) {
                  Navigator.pop(context);
                  _sendReaction(emoji, details);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final partnerText = ws.partnerText;
    final partnerName = ws.partnerDisplayName ?? 'Partner';
    final partnerMood = ws.partnerMood;

    // Navigate to welcome only when the session is explicitly cleared
    // (e.g. server rejects token / manual unpair). A temporary disconnect
    // while still stored-as-paired must NOT boot the user — SyncScreen shows
    // its own reconnecting banner instead.
    if (!ws.storage.isPaired &&
        (ws.status == ConnectionStatus.connected ||
         ws.status == ConnectionStatus.disconnected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      });
    }

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Stack(
            children: [
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: _enterAnim,
                  curve: Curves.easeOut,
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // Partner status + name + mood
                          _StatusBadge(
                            online: ws.partnerOnline,
                            name: partnerName,
                            mood: partnerMood,
                          ),
                          const Spacer(),
                          Text(
                            'LockSync',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontSize: 18),
                          ),
                          const Spacer(),
                          // Settings
                          IconButton(
                            icon:
                                const Icon(Icons.settings_rounded, size: 22),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SettingsScreen()),
                              );
                            },
                            tooltip: 'Settings',
                          ),
                        ],
                      ),
                    ),

                    // Reconnecting overlay
                    if (ws.isReconnecting)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 16),
                        color: Colors.amber.withValues(alpha: 0.15),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Reconnecting...',
                              style:
                                  TextStyle(color: Colors.amber, fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                    const Divider(color: Colors.white10, height: 1),

                    // Partner's text (what they're writing)
                    Expanded(
                      child: GestureDetector(
                        onDoubleTapDown: (details) {
                          _showReactionPicker(TapUpDetails(
                            kind: PointerDeviceKind.touch,
                            globalPosition: details.globalPosition,
                            localPosition: details.localPosition,
                          ));
                        },
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 16,
                                    color: LockSyncTheme.accentColor
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$partnerName\'s Lock Screen',
                                    style: TextStyle(
                                      color: LockSyncTheme.accentColor
                                          .withValues(alpha: 0.7),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: partnerText.isEmpty
                                    ? _EmptyPartnerState(
                                        typingAnim: _typingAnim,
                                        online: ws.partnerOnline,
                                      )
                                    : _PartnerMessageCard(text: partnerText),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Divider
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            LockSyncTheme.primaryColor.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    // Your text input
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                size: 16,
                                color: LockSyncTheme.primaryColor
                                    .withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Your Lock Screen Message',
                                style: TextStyle(
                                  color: LockSyncTheme.primaryColor
                                      .withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border.all(
                                color: LockSyncTheme.primaryColor
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: TextField(
                              controller: _textController,
                              maxLines: 4,
                              minLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Type a message for $partnerName\'s lock screen...',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              AnimatedBuilder(
                                animation: _typingAnim,
                                builder: (context, _) {
                                  return Icon(
                                    Icons.sync_rounded,
                                    size: 14,
                                    color: ws.partnerOnline
                                        ? LockSyncTheme.accentColor
                                            .withValues(
                                                alpha: 0.3 +
                                                    _typingAnim.value * 0.4)
                                        : Colors.white12,
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              Text(
                                ws.partnerOnline
                                    ? 'Changes sync instantly'
                                    : '$partnerName will see this when they\'re back online',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Floating reactions overlay
              ..._floatingReactions.map((r) => _FloatingReactionWidget(
                    key: ValueKey(r.createdAt),
                    reaction: r,
                  )),
            ],
          ),
        ),
      ),

      // Bottom action bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BottomAction(
                icon: Icons.brush_rounded,
                label: 'Canvas',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CanvasScreen()),
                ),
              ),
              _BottomAction(
                icon: Icons.widgets_rounded,
                label: 'Widgets',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => const WidgetDrawer(),
                  );
                },
              ),
              _BottomAction(
                icon: Icons.mood_rounded,
                label: 'Mood',
                onTap: _showMoodPicker,
              ),
              _BottomAction(
                icon: Icons.vibration_rounded,
                label: 'Nudge',
                onTap: () {
                  final ws = context.read<WebSocketService>();
                  ws.sendNudge();
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nudge sent!'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              _BottomAction(
                icon: Icons.link_off_rounded,
                label: 'Unpair',
                onTap: () {
                  final ws = context.read<WebSocketService>();
                  _unpair(ws);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom action button ────────────────────────────────────────────
class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Status Badge ────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final bool online;
  final String name;
  final String? mood;

  const _StatusBadge({
    required this.online,
    required this.name,
    this.mood,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: online
            ? LockSyncTheme.accentColor.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
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
              color: online ? LockSyncTheme.accentColor : Colors.white30,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              color: online ? LockSyncTheme.accentColor : Colors.white30,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (mood != null && mood!.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(mood!, style: const TextStyle(fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

class _EmptyPartnerState extends StatelessWidget {
  final AnimationController typingAnim;
  final bool online;
  const _EmptyPartnerState({required this.typingAnim, required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: typingAnim,
            builder: (context, _) {
              return Icon(
                online ? Icons.edit_note_rounded : Icons.lock_clock_rounded,
                size: 48,
                color: Colors.white.withValues(
                    alpha: 0.1 + typingAnim.value * 0.1),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            online
                ? 'Your partner hasn\'t written anything yet'
                : 'Waiting for your partner to come online...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerMessageCard extends StatelessWidget {
  final String text;
  const _PartnerMessageCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(text),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            LockSyncTheme.accentColor.withValues(alpha: 0.08),
            LockSyncTheme.primaryColor.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: LockSyncTheme.accentColor.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          height: 1.6,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

// ─── Floating Reaction ───────────────────────────────────────────────
class _FloatingReaction {
  final String emoji;
  final double x;
  final double y;
  final DateTime createdAt;

  _FloatingReaction({
    required this.emoji,
    required this.x,
    required this.y,
    required this.createdAt,
  });
}

class _FloatingReactionWidget extends StatefulWidget {
  final _FloatingReaction reaction;
  const _FloatingReactionWidget({super.key, required this.reaction});

  @override
  State<_FloatingReactionWidget> createState() =>
      _FloatingReactionWidgetState();
}

class _FloatingReactionWidgetState extends State<_FloatingReactionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
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
        final progress = _controller.value;
        return Positioned(
          left: widget.reaction.x - 20 + sin(progress * 6) * 10,
          top: widget.reaction.y - 20 - progress * 80,
          child: Opacity(
            opacity: (1.0 - progress).clamp(0, 1),
            child: Transform.scale(
              scale: 1.0 + progress * 0.5,
              child: Text(
                widget.reaction.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
        );
      },
    );
  }
}
