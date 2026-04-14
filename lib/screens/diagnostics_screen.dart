import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/crash_logger.dart';
import '../services/server_health.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';

/// Shows captured crash / uncaught-error entries persisted by [CrashLogger]
/// so the user can copy or clear them.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<CrashEntry> _entries = const [];
  bool _loading = true;

  // null = checking, true = healthy, false = unreachable
  bool? _serverHealthy;
  bool _serverChecking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkServer();
  }

  Future<void> _checkServer() async {
    if (_serverChecking) return;
    setState(() => _serverChecking = true);
    final healthy = await ServerHealth.check();
    if (!mounted) return;
    setState(() {
      _serverHealthy = healthy;
      _serverChecking = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final entries = await CrashLogger.readAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear crash log?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove all recorded crashes from this device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await CrashLogger.clear();
      await _refresh();
    }
  }

  Future<void> _copyAll() async {
    if (_entries.isEmpty) return;
    final buf = StringBuffer();
    for (final e in _entries) {
      buf.writeln('── ${e.timestamp.toIso8601String()} · ${e.source} ──');
      if (e.library != null) buf.writeln('library: ${e.library}');
      buf.writeln(e.summary);
      if (e.stack != null) {
        buf.writeln();
        buf.writeln(e.stack);
      }
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Crash log copied to clipboard.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Column(
            children: [
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
                      'Diagnostics',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: (_loading || _serverChecking)
                          ? null
                          : () {
                              _refresh();
                              _checkServer();
                            },
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
              // ── Server health card ───────────────────────────────────────
              _ServerHealthCard(
                checking: _serverChecking,
                healthy: _serverHealthy,
                onRecheck: _checkServer,
              ),
              if (!_loading && _entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyAll,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copy all'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _entries.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: _entries.length,
                            itemBuilder: (_, i) =>
                                _CrashCard(entry: _entries[i]),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Server health card ────────────────────────────────────────────────────────

class _ServerHealthCard extends StatelessWidget {
  final bool checking;
  final bool? healthy;
  final VoidCallback onRecheck;

  const _ServerHealthCard({
    required this.checking,
    required this.healthy,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (checking || healthy == null) {
      statusColor = Colors.white38;
      statusIcon = Icons.hourglass_top_rounded;
      statusLabel = 'Checking…';
    } else if (healthy!) {
      statusColor = Colors.greenAccent;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = 'Online';
    } else {
      statusColor = Colors.redAccent;
      statusIcon = Icons.cancel_rounded;
      statusLabel = 'Unreachable';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withValues(alpha: checking ? 0.1 : 0.25),
          ),
        ),
        child: Row(
          children: [
            checking
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                : Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Server — $statusLabel',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppConfig.healthUrl,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              color: Colors.white38,
              onPressed: checking ? null : onRecheck,
              tooltip: 'Re-check',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded,
                color: LockSyncTheme.primaryColor.withValues(alpha: 0.6),
                size: 56),
            const SizedBox(height: 16),
            const Text(
              'No crashes recorded.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'If the app crashes, the details will show up here so you '
              'can copy them for debugging.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrashCard extends StatefulWidget {
  final CrashEntry entry;
  const _CrashCard({required this.entry});

  @override
  State<_CrashCard> createState() => _CrashCardState();
}

class _CrashCardState extends State<_CrashCard> {
  bool _expanded = false;

  String _formatTs(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.redAccent
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            e.source,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatTs(e.timestamp),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.summary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && e.stack != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (e.library != null) ...[
                      Text(
                        'library: ${e.library}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        e.stack!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final txt = StringBuffer()
                            ..writeln(
                                '── ${_formatTs(e.timestamp)} · ${e.source} ──')
                            ..writeln(e.summary);
                          if (e.stack != null) {
                            txt.writeln();
                            txt.writeln(e.stack);
                          }
                          await Clipboard.setData(
                              ClipboardData(text: txt.toString()));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied.'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
