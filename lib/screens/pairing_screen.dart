import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';
import '../widgets/glass_card.dart';
import 'qr_scanner_screen.dart';
import 'display_name_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _enterAnim;
  final _codeControllers = List.generate(6, (_) => TextEditingController());
  final _codeFocusNodes = List.generate(6, (_) => FocusNode());
  Timer? _expiryTimer;
  int _secondsLeft = 300;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _enterAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _enterAnim.dispose();
    _expiryTimer?.cancel();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startExpiry() {
    _secondsLeft = 300;
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) t.cancel();
      });
    });
  }

  void _generateCode(WebSocketService ws) {
    ws.requestCode();
    _startExpiry();
  }

  void _submitJoinCode(WebSocketService ws) {
    final code = _codeControllers.map((c) => c.text).join();
    if (code.length == 6) {
      ws.joinCode(code);
    }
  }

  void _fillCodeFromScanner(String code) {
    for (int i = 0; i < 6 && i < code.length; i++) {
      _codeControllers[i].text = code[i];
    }
    final ws = context.read<WebSocketService>();
    ws.joinCode(code);
  }

  Future<void> _openScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (code != null && mounted) {
      // Switch to Enter Code tab and fill in the code
      _tabController.animateTo(1);
      _fillCodeFromScanner(code);
    }
  }

  void _navigateToDisplayName() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DisplayNameScreen(isInitialSetup: true),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();

    // Navigate to display name screen when paired
    if (ws.status == ConnectionStatus.paired && !_navigated) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _navigateToDisplayName());
    }

    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _enterAnim,
              curve: Curves.easeOut,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _enterAnim,
                curve: Curves.easeOutCubic,
              )),
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
                          'Pair Devices',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tab bar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: LockSyncTheme.primaryColor,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Share Code'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dialpad_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Enter Code'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error banner
                  if (ws.errorMessage != null)
                    _buildErrorBanner(context, ws),

                  // Tab content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildShareCodeTab(context, ws),
                        _buildEnterCodeTab(context, ws),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, WebSocketService ws) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ws.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            onPressed: ws.clearError,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildShareCodeTab(BuildContext context, WebSocketService ws) {
    final code = ws.pairingCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Show this code to your partner',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),

          if (code == null) ...[
            // Generate button
            GlassCard(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Generate a pairing code to\nshare with your partner',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _generateCode(ws),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Generate Code'),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // QR Code
            GlassCard(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: 'locksync:$code',
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: Color(0xFF1A1A2E),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Code display — fixed layout with proper constraints
                  _AnimatedCodeDisplay(code: code),

                  const SizedBox(height: 16),

                  // Expiry timer
                  _ExpiryIndicator(secondsLeft: _secondsLeft),

                  const SizedBox(height: 16),

                  // Regenerate
                  TextButton.icon(
                    onPressed: () => _generateCode(ws),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Generate New Code'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'Your partner enters this code on their device\nor scans the QR code to complete pairing',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white38,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnterCodeTab(BuildContext context, WebSocketService ws) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Enter your partner\'s 6-digit code',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),

          // Scan QR button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR Code Instead'),
            ),
          ),

          const SizedBox(height: 24),

          GlassCard(
            child: Column(
              children: [
                // 6-digit input — wrapped in LayoutBuilder for proper sizing
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate width per digit based on available space
                    // 6 digits + 5 gaps (4 small + 1 large)
                    const totalGap = 8.0 * 4 + 16.0; // 4 small + 1 large gap
                    final digitWidth =
                        ((constraints.maxWidth - totalGap) / 6).clamp(36.0, 48.0);
                    final digitHeight = digitWidth * 1.27;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        return Container(
                          width: digitWidth,
                          height: digitHeight,
                          margin: EdgeInsets.only(
                            left: i == 0 ? 0 : (i == 3 ? 16 : 8),
                          ),
                          child: TextField(
                            controller: _codeControllers[i],
                            focusNode: _codeFocusNodes[i],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: TextStyle(
                              fontSize: digitWidth * 0.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: LockSyncTheme.primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (value) {
                              if (value.isNotEmpty && i < 5) {
                                _codeFocusNodes[i + 1].requestFocus();
                              }
                              if (value.isEmpty && i > 0) {
                                _codeFocusNodes[i - 1].requestFocus();
                              }
                              final full = _codeControllers
                                  .every((c) => c.text.isNotEmpty);
                              if (full) {
                                _submitJoinCode(ws);
                              }
                            },
                          ),
                        );
                      }),
                    );
                  },
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _submitJoinCode(ws),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Connect'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Waiting indicator
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: ws.pairingCode != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LockSyncTheme.accentColor
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Waiting for partner...',
                          style: TextStyle(
                            color: LockSyncTheme.accentColor
                                .withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          Text(
            'Ask your partner to generate a code\non their device, then enter it here',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white38,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Animated code display — fixed with proper constraints ──────────
class _AnimatedCodeDisplay extends StatelessWidget {
  final String code;
  const _AnimatedCodeDisplay({required this.code});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const totalGap = 8.0 * 4 + 16.0;
          final digitWidth =
              ((constraints.maxWidth - totalGap) / 6).clamp(36.0, 48.0);
          final digitHeight = digitWidth * 1.27;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(code.length, (i) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + i * 100),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value.clamp(0, 1),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: digitWidth,
                  height: digitHeight,
                  margin:
                      EdgeInsets.only(left: i == 0 ? 0 : (i == 3 ? 16 : 8)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        LockSyncTheme.primaryColor.withValues(alpha: 0.3),
                        LockSyncTheme.accentColor.withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border.all(
                      color:
                          LockSyncTheme.primaryColor.withValues(alpha: 0.4),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    code[i],
                    style: TextStyle(
                      fontSize: digitWidth * 0.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Expiry indicator ───────────────────────────────────────────────────
class _ExpiryIndicator extends StatelessWidget {
  final int secondsLeft;
  const _ExpiryIndicator({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final minutes = secondsLeft ~/ 60;
    final seconds = secondsLeft % 60;
    final isLow = secondsLeft < 60;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 16,
          color: isLow ? Colors.amber : Colors.white38,
        ),
        const SizedBox(width: 6),
        Text(
          'Expires in $minutes:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            color: isLow ? Colors.amber : Colors.white38,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
