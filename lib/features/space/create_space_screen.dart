import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/device_utils.dart';
import '../../models/space.dart';
import '../../models/member.dart';
import '../../providers/app_providers.dart';
import '../../services/signaling_service.dart';

class CreateSpaceScreen extends ConsumerStatefulWidget {
  const CreateSpaceScreen({super.key});

  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _signalingService = const SignalingService();
  final _uuid = const Uuid();

  bool _isCreating = false;
  String? _qrData;
  String? _connectionCode;
  Space? _createdSpace;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Our Space';
  }

  Future<void> _createSpace() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final deviceIdAsync = ref.read(deviceIdProvider);
      final deviceNameAsync = ref.read(deviceNameProvider);

      final deviceId = deviceIdAsync.valueOrNull ?? _uuid.v4();
      final deviceName = deviceNameAsync.valueOrNull ??
          DeviceUtils.generateDeviceName();

      final space = Space(
        spaceId: _uuid.v4(),
        createdAt: DateTime.now(),
        hostDeviceId: deviceId,
        spaceName: _nameController.text.trim(),
      );

      final info = await _signalingService.buildConnectionInfo(
        space: space,
        port: AppConstants.defaultWsPort,
        hostDeviceName: deviceName,
      );

      if (info == null) {
        _showError('Could not determine local IP. Connect to WiFi and retry.');
        setState(() => _isCreating = false);
        return;
      }

      // Save space and start the host.
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

      await controller.startAsHost(
        space: space,
        deviceId: deviceId,
        deviceName: deviceName,
        port: AppConstants.defaultWsPort,
        localIp: info.hostIp,
      );

      // Add self as first member.
      final selfMember = Member(
        memberId: _uuid.v4(),
        deviceId: deviceId,
        deviceName: deviceName,
        spaceId: space.spaceId,
        connectionStatus: 'connected',
        lastSeen: DateTime.now(),
      );
      await ref.read(membersProvider.notifier).upsertMember(selfMember);

      setState(() {
        _createdSpace = space;
        _qrData = info.toQrData();
        _connectionCode = info.toConnectionCode();
        _isCreating = false;
      });
    } catch (e) {
      _showError('Failed to create space: $e');
      setState(() => _isCreating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openEditor() {
    if (_createdSpace == null) return;
    context.go('/editor');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
          'Create Space',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: _qrData == null
              ? _buildCreateForm()
              : _buildQrDisplay(),
        ),
      ),
    );
  }

  Widget _buildCreateForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Name your shared space',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Give your space a name so connected devices know which space they\'re joining.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: 'e.g. Our Space',
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
                    color: Color(0xFF6C63FF), width: 1.5),
              ),
              prefixIcon: const Icon(Icons.space_dashboard_rounded,
                  color: Color(0xFF6C63FF)),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createSpace,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isCreating
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : const Text(
                      'Create & Generate QR Code',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        Text(
          _createdSpace?.spaceName ?? 'Space Created!',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share this QR code with your partner to connect.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 32),
        // QR Code
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: QrImageView(
            data: _qrData!,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        // Manual connection code
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              const Icon(Icons.key_rounded,
                  color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _connectionCode ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: Colors.white54, size: 20),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: _connectionCode ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Connection code copied!')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Or share the code above manually if QR scanning isn\'t available.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _openEditor,
            icon: const Icon(Icons.dashboard_customize_rounded),
            label: const Text(
              'Open Editor',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
