import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import 'welcome_screen.dart';

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
  bool _showPartnerTyping = false;
  String _lastSentText = '';

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
  }

  @override
  void dispose() {
    _textController.dispose();
    _enterAnim.dispose();
    _typingAnim.dispose();
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

  void _unpair(WebSocketService ws) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unpair Devices?', style: TextStyle(color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final partnerText = ws.partnerText;

    // If we lost pairing, go back
    if (ws.status != ConnectionStatus.paired &&
        ws.status != ConnectionStatus.connecting &&
        ws.status != ConnectionStatus.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      });
    }

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterAnim,
              curve: Curves.easeOut,
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Partner status
                      _StatusBadge(online: ws.partnerOnline),
                      const Spacer(),
                      Text(
                        'LockSync',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 18,
                            ),
                      ),
                      const Spacer(),
                      // Unpair button
                      IconButton(
                        icon: const Icon(Icons.link_off_rounded, size: 22),
                        onPressed: () => _unpair(ws),
                        tooltip: 'Unpair',
                      ),
                    ],
                  ),
                ),

                const Divider(
                  color: Colors.white10,
                  height: 1,
                ),

                // Partner's text (what they're writing)
                Expanded(
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
                              color: LockSyncTheme.accentColor.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Partner\'s Lock Screen',
                              style: TextStyle(
                                color: LockSyncTheme.accentColor.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // The partner's message rendered like a lock screen
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: partnerText.isEmpty
                              ? _EmptyPartnerState(typingAnim: _typingAnim, online: ws.partnerOnline)
                              : _PartnerMessageCard(text: partnerText),
                        ),
                      ],
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
                            color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your Lock Screen Message',
                            style: TextStyle(
                              color: LockSyncTheme.primaryColor.withValues(alpha: 0.7),
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
                            color: LockSyncTheme.primaryColor.withValues(alpha: 0.2),
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
                            hintText: 'Type a message for your partner\'s lock screen...',
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
                                    ? LockSyncTheme.accentColor.withValues(alpha: 0.3 + _typingAnim.value * 0.4)
                                    : Colors.white12,
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ws.partnerOnline
                                ? 'Changes sync instantly'
                                : 'Partner will see this when they\'re back online',
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
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool online;
  const _StatusBadge({required this.online});

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
            online ? 'Partner online' : 'Partner offline',
            style: TextStyle(
              fontSize: 12,
              color: online ? LockSyncTheme.accentColor : Colors.white30,
              fontWeight: FontWeight.w500,
            ),
          ),
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
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: typingAnim,
            builder: (context, _) {
              return Icon(
                online ? Icons.edit_note_rounded : Icons.lock_clock_rounded,
                size: 48,
                color: Colors.white.withValues(alpha: 0.1 + typingAnim.value * 0.1),
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
