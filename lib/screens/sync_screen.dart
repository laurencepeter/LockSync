import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/canvas_models.dart';
import '../services/websocket_service.dart';
import '../services/wallpaper_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'canvas_screen.dart';
import 'moments_screen.dart';
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

  // Page view for swiping between screens
  // Page 0: Chat/Messages (default), Page 1: Canvas, Page 2: Widgets, Page 3: Moments
  final _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  // Canvas preview state
  CanvasState _previewCanvasState = CanvasState();
  StreamSubscription? _canvasSyncSub;

  // Floating reactions
  final List<_FloatingReaction> _floatingReactions = [];
  StreamSubscription? _reactionSub;
  StreamSubscription? _nudgeSub;

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

      // Listen for live canvas updates from partner
      _canvasSyncSub = ws.onCanvasSync.listen(_onCanvasSyncReceived);

      // Load initial canvas preview from local storage
      _loadCanvasPreview();

      // Auto-enable lock screen display and wallpaper updates — no dialog.
      _autoEnableLockScreen(ws);
    });
  }

  static const Map<String, int> _themeColors = {
    'default':  0xFF0F0F1A,
    'midnight': 0xFF000000,
    'rose':     0xFF1A070F,
    'ocean':    0xFF071422,
    'forest':   0xFF071A0F,
    'sunset':   0xFF1A0F07,
    'lavender': 0xFF130A1A,
  };

  Color _previewThemeColor() =>
      Color(_themeColors[_previewCanvasState.theme] ?? 0xFF0F0F1A);

  void _loadCanvasPreview() {
    final ws = context.read<WebSocketService>();
    CanvasState? loaded;
    final saved = ws.storage.canvasState;
    if (saved != null) {
      try {
        loaded = CanvasState.fromJson(jsonDecode(saved));
      } catch (_) {}
    }
    // Partner canvas data in memory takes priority (most recent)
    if (ws.partnerCanvasData != null) {
      try {
        loaded = CanvasState.fromJson(ws.partnerCanvasData!);
      } catch (_) {}
    }
    if (loaded != null && mounted) {
      setState(() {
        _previewCanvasState = loaded!;
      });
    }
  }

  void _onCanvasSyncReceived(Map<String, dynamic> data) {
    if (!mounted) return;
    try {
      setState(() {
        _previewCanvasState = CanvasState.fromJson(data);
      });
    } catch (_) {}
  }

  /// Auto-enable lock screen features without requiring user interaction.
  void _autoEnableLockScreen(WebSocketService ws) {
    if (!ws.storage.autoWallpaperPrompted) {
      ws.storage.setAutoWallpaperPrompted(true);
      ws.storage.setAutoUpdateWallpaper(true);
    }
    // Always ensure the app can display over the lock screen
    WallpaperService.setShowOnLockScreen(true);
  }

  @override
  void dispose() {
    _textController.dispose();
    _enterAnim.dispose();
    _typingAnim.dispose();
    _pageController.dispose();
    _reactionSub?.cancel();
    _nudgeSub?.cancel();
    _canvasSyncSub?.cancel();
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
    if (!mounted) return;
    final partnerName =
        context.read<WebSocketService>().partnerDisplayName ?? 'Partner';
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, _, __) => _NudgePopup(partnerName: partnerName),
      transitionBuilder: (ctx, anim, _, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
    // Auto-dismiss after 3 s
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    });
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

                    // ── Swipeable pages: Chat | Canvas | Widgets | Moments ──
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (page) {
                          setState(() => _currentPage = page);
                        },
                        children: [
                          // Page 0: Chat / Messages (default landing)
                          _buildTextPage(ws, partnerName, partnerText),
                          // Page 1: Live canvas preview (full screen)
                          _buildCanvasPage(ws, partnerName),
                          // Page 2: Widgets (grocery, watchlist, etc.)
                          _buildWidgetsPage(ws),
                          // Page 3: Moments (images / videos)
                          _buildMomentsPage(ws),
                        ],
                      ),
                    ),

                    // Page indicator dots
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PageDot(
                            active: _currentPage == 0,
                            label: 'Chat',
                          ),
                          const SizedBox(width: 8),
                          _PageDot(
                            active: _currentPage == 1,
                            label: 'Canvas',
                          ),
                          const SizedBox(width: 8),
                          _PageDot(
                            active: _currentPage == 2,
                            label: 'Widgets',
                          ),
                          const SizedBox(width: 8),
                          _PageDot(
                            active: _currentPage == 3,
                            label: 'Moments',
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
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CanvasScreen()),
                  );
                  _loadCanvasPreview();
                  setState(() {});
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
                icon: Icons.settings_rounded,
                label: 'Settings',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
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

  // ── Page 0: Live canvas preview ──────────────────────────────────
  Widget _buildCanvasPage(WebSocketService ws, String partnerName) {
    final hasContent = _previewCanvasState.strokes.isNotEmpty ||
        _previewCanvasState.textElements.isNotEmpty ||
        _previewCanvasState.stickers.isNotEmpty ||
        _previewCanvasState.backgroundImagePath != null;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CanvasScreen()),
        );
        _loadCanvasPreview();
        setState(() {});
      },
      onDoubleTapDown: (details) {
        _showReactionPicker(TapUpDetails(
          kind: PointerDeviceKind.touch,
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
        ));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        color: _previewThemeColor(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            if (_previewCanvasState.backgroundImagePath != null)
              Positioned.fill(
                child: Image.file(
                  File(_previewCanvasState.backgroundImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),

            // Canvas strokes
            if (hasContent)
              Positioned.fill(
                child: CustomPaint(
                  painter: _CanvasPreviewPainter(
                    state: _previewCanvasState,
                  ),
                ),
              ),

            // Text elements overlay
            ..._previewCanvasState.textElements.map((t) {
              return Positioned(
                left: t.x,
                top: t.y,
                child: Text(
                  t.text,
                  style: TextStyle(
                    color: Color(t.color),
                    fontSize: t.fontSize,
                  ),
                ),
              );
            }),

            // Sticker elements overlay
            ..._previewCanvasState.stickers.map((s) {
              return Positioned(
                left: s.x - s.size / 2,
                top: s.y - s.size / 2,
                child: Text(
                  s.emoji,
                  style: TextStyle(fontSize: s.size),
                ),
              );
            }),

            // Empty state
            if (!hasContent)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.brush_rounded,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Shared Canvas',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to edit canvas\nSwipe for more screens',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.15),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            // Edit hint overlay (bottom)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.brush_rounded,
                          color: Colors.white54, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Tap to edit',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 2: Widgets ──────────────────────────────────────────────
  Widget _buildWidgetsPage(WebSocketService ws) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.widgets_rounded,
                size: 16,
                color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Shared Widgets',
                style: TextStyle(
                  color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _WidgetPageCard(
            icon: Icons.shopping_cart_rounded,
            title: 'Grocery Checklist',
            subtitle: 'Shared shopping list',
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const WidgetDrawer(),
              );
            },
          ),
          const SizedBox(height: 12),
          _WidgetPageCard(
            icon: Icons.movie_rounded,
            title: 'Watchlist',
            subtitle: 'Movies & shows to watch together',
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const WidgetDrawer(),
              );
            },
          ),
          const SizedBox(height: 12),
          _WidgetPageCard(
            icon: Icons.alarm_rounded,
            title: 'Reminders',
            subtitle: 'Shared reminders for each other',
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const WidgetDrawer(),
              );
            },
          ),
          const SizedBox(height: 12),
          _WidgetPageCard(
            icon: Icons.timer_rounded,
            title: 'Countdowns',
            subtitle: 'Count down to special dates',
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const WidgetDrawer(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Page 3: Moments ─────────────────────────────────────────────
  Widget _buildMomentsPage(WebSocketService ws) {
    final moments = ws.storage.getMoments();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Icon(
                Icons.photo_camera_rounded,
                size: 16,
                color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Moments',
                style: TextStyle(
                  color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MomentsScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: LockSyncTheme.primaryColor
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_a_photo_rounded,
                          color: LockSyncTheme.primaryColor, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Send',
                        style: TextStyle(
                          color: LockSyncTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: moments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_camera_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'No moments yet',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap "Send" to share a photo or video',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.15),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: moments.length,
                  itemBuilder: (ctx, i) {
                    final m = Moment.fromJson(moments[i]);
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MomentsScreen()),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: m.isExpired
                                ? Colors.white.withValues(alpha: 0.05)
                                : LockSyncTheme.primaryColor
                                    .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              m.isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.image_rounded,
                              color: m.isExpired
                                  ? Colors.white24
                                  : Colors.white60,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'From ${m.sentBy}',
                                    style: TextStyle(
                                      color: m.isExpired
                                          ? Colors.white30
                                          : Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m.isExpired
                                        ? 'Expired'
                                        : '${m.viewCount}/${m.maxReplays} views',
                                    style: TextStyle(
                                      color: m.isExpired
                                          ? Colors.red.withValues(
                                              alpha: 0.6)
                                          : Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Page 0: Text messages (Chat) ────────────────────────────────
  Widget _buildTextPage(
      WebSocketService ws, String partnerName, String partnerText) {
    return Column(
      children: [
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
    );
  }
}

// ─── Page indicator dot ──────────────────────────────────────────────
class _PageDot extends StatelessWidget {
  final bool active;
  final String label;
  const _PageDot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? LockSyncTheme.primaryColor
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        if (active) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Widget page card ─────────────────────────────────────────────────
class _WidgetPageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WidgetPageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: LockSyncTheme.primaryColor.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: LockSyncTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: LockSyncTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Canvas preview painter (read-only) ──────────────────────────────
class _CanvasPreviewPainter extends CustomPainter {
  final CanvasState state;
  _CanvasPreviewPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in state.strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.thickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.isEraser) {
        paint.blendMode = BlendMode.clear;
      }
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points[0],
          stroke.thickness / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()..moveTo(stroke.points[0].dx, stroke.points[0].dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CanvasPreviewPainter old) => true;
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

// ─── Nudge Popup ─────────────────────────────────────────────────────
class _NudgePopup extends StatelessWidget {
  final String partnerName;
  const _NudgePopup({required this.partnerName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).maybePop(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: LockSyncTheme.primaryColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: LockSyncTheme.primaryColor.withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📳', style: TextStyle(fontSize: 60)),
                const SizedBox(height: 20),
                Text(
                  '$partnerName nudged you!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Say something back!',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Tap to dismiss',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
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
