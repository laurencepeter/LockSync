import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final name = await ref.read(localStorageProvider).getDeviceName();
    if (mounted && name != null) {
      _nameController.text = name;
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(localStorageProvider).saveDeviceName(name);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Device name saved.')));
    }
  }

  Future<void> _leaveSpace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Leave Space?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Your local data will be preserved but you will be disconnected from all peers.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave',
                style: TextStyle(color: Color(0xFFFF6584))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(appControllerProvider).leaveSpace();
    await ref.read(spaceProvider.notifier).clearSpace();
    ref.read(membersProvider.notifier).clear();
    if (!mounted) return;
    context.go('/connect');
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear All Data?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will permanently erase all local spaces and layouts. This cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear',
                style: TextStyle(color: Color(0xFFFF6584))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(appControllerProvider).leaveSpace();

    // Re-initialize storage boxes as empty.
    await ref.read(localStorageProvider).clearCurrentSpaceId();
    ref.read(membersProvider.notifier).clear();
    await ref.read(spaceProvider.notifier).clearSpace();
    if (!mounted) return;
    context.go('/connect');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    final deviceId = ref.watch(deviceIdProvider).valueOrNull;

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
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Device ──────────────────────────────────────────────
          _SectionHeader('Device'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              _LabeledField(
                label: 'Device Name',
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Enter device name',
                          hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.3)),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _saveName,
                      child: Text(
                        _saving ? 'Saving…' : 'Save',
                        style: const TextStyle(
                            color: Color(0xFF6C63FF),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (deviceId != null) ...[
                _SettingsDivider(),
                _InfoRow('Device ID', _truncate(deviceId, 16)),
              ],
            ],
          ),
          const SizedBox(height: 24),
          // ── Space ────────────────────────────────────────────────
          _SectionHeader('Space'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              if (space != null) ...[
                _InfoRow('Space Name', space.spaceName ?? 'Unnamed'),
                _SettingsDivider(),
                _InfoRow('Space ID', _truncate(space.spaceId, 16)),
                _SettingsDivider(),
                _InfoRow(
                    'Created', _formatDate(space.createdAt)),
                _SettingsDivider(),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.exit_to_app_rounded,
                    color: Color(0xFFFF6584)),
                title: const Text('Leave Space',
                    style: TextStyle(
                        color: Color(0xFFFF6584),
                        fontWeight: FontWeight.w600)),
                onTap: _leaveSpace,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Data ─────────────────────────────────────────────────
          _SectionHeader('Data'),
          const SizedBox(height: 12),
          _SettingsCard(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever_rounded,
                    color: Color(0xFFFF6584)),
                title: const Text('Clear All Local Data',
                    style: TextStyle(
                        color: Color(0xFFFF6584),
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Removes all saved layouts and spaces.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12),
                ),
                onTap: _clearLocalData,
              ),
            ],
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              'LockSync v1.0.0 • Local-first P2P',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
          child,
          const SizedBox(height: 4),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 14)),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      );
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
        color: Colors.white.withOpacity(0.07),
        height: 1,
      );
}
