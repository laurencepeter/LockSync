import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../../core/utils/device_utils.dart';
import '../../models/space.dart';
import '../../models/member.dart';
import '../../providers/app_providers.dart';
import '../../services/signaling_service.dart';

class JoinSpaceScreen extends ConsumerStatefulWidget {
  const JoinSpaceScreen({super.key});

  @override
  ConsumerState<JoinSpaceScreen> createState() => _JoinSpaceScreenState();
}

class _JoinSpaceScreenState extends ConsumerState<JoinSpaceScreen>
    with SingleTickerProviderStateMixin {
  final _signalingService = const SignalingService();
  final _uuid = const Uuid();
  final _codeController = TextEditingController();

  late TabController _tabController;
  bool _isJoining = false;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinWithInfo(Map<String, dynamic> infoMap) async {
    if (_isJoining) return;
    setState(() => _isJoining = true);

    try {
      final info = _signalingService.parseQrData(
        infoMap['raw'] as String? ?? '',
      );
      if (info == null) {
        _showError('Invalid connection info. Please try again.');
        setState(() => _isJoining = false);
        return;
      }

      final deviceIdAsync = ref.read(deviceIdProvider);
      final deviceNameAsync = ref.read(deviceNameProvider);
      final deviceId = deviceIdAsync.valueOrNull ?? _uuid.v4();
      final deviceName =
          deviceNameAsync.valueOrNull ?? DeviceUtils.generateDeviceName();

      final space = Space(
        spaceId: info.spaceId,
        createdAt: DateTime.now(),
        hostDeviceId: info.hostDeviceId,
      );

      await ref.read(spaceProvider.notifier).setSpace(space);

      final controller = ref.read(appControllerProvider);
      controller.onStatusChanged = (s) {
        if (mounted) {
          ref.read(connectionStatusProvider.notifier).state = s;
        }
      };
      controller.onMemberJoined = (member) {
        if (mounted) {
          ref.read(membersProvider.notifier).upsertMember(member);
        }
      };

      await controller.startAsClient(
        space: space,
        deviceId: deviceId,
        deviceName: deviceName,
        wsUrl: info.wsUrl,
      );

      // Add self.
      final selfMember = Member(
        memberId: _uuid.v4(),
        deviceId: deviceId,
        deviceName: deviceName,
        spaceId: space.spaceId,
        connectionStatus: 'connected',
        lastSeen: DateTime.now(),
      );
      await ref.read(membersProvider.notifier).upsertMember(selfMember);

      if (!mounted) return;
      context.go('/editor');
    } catch (e) {
      _showError('Failed to join: $e');
      setState(() => _isJoining = false);
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    if (_scanned || _isJoining) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _scanned = true);
    _joinWithInfo({'raw': barcode!.rawValue!});
  }

  Future<void> _joinWithCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final info = _signalingService.parseConnectionCode(code);
    if (info == null) {
      _showError('Invalid code. Please check and try again.');
      return;
    }
    _joinWithInfo({'raw': info.toQrData()});
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _scanned = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Join Space',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF6584),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan QR'),
            Tab(icon: Icon(Icons.keyboard_rounded), text: 'Enter Code'),
          ],
        ),
      ),
      body: _isJoining
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6584)),
                  SizedBox(height: 16),
                  Text('Connecting…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildQrScanner(),
                _buildCodeEntry(),
              ],
            ),
    );
  }

  Widget _buildQrScanner() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                onDetect: _onQrDetected,
              ),
              // Overlay frame
              Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: const Color(0xFFFF6584), width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Point the camera at the QR code displayed\non the host device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeEntry() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text(
            'Enter connection code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste or type the connection code shared by the host device.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _codeController,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste connection code here…',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: Color(0xFFFF6584), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _joinWithCode,
              icon: const Icon(Icons.login_rounded),
              label: const Text(
                'Join Space',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6584),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
