import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../services/websocket_service.dart';
import '../theme.dart';
import '../widgets/animated_gradient_bg.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class Moment {
  final String id;
  final String mediaType; // 'image' | 'video'
  final String data; // base64
  final bool nsfw;
  final int viewDuration; // seconds
  final int maxReplays; // 1–3
  final String sentAt;
  final String sentBy;
  int viewCount;

  Moment({
    required this.id,
    required this.mediaType,
    required this.data,
    required this.nsfw,
    required this.viewDuration,
    required this.maxReplays,
    required this.sentAt,
    required this.sentBy,
    this.viewCount = 0,
  });

  bool get isExpired => viewCount >= maxReplays;
  bool get isVideo => mediaType == 'video';

  factory Moment.fromJson(Map<String, dynamic> j) => Moment(
        id: j['id'] as String,
        mediaType: j['mediaType'] as String? ?? 'image',
        data: j['data'] as String,
        nsfw: j['nsfw'] as bool? ?? false,
        viewDuration: (j['viewDuration'] as num?)?.toInt() ?? 10,
        maxReplays: (j['maxReplays'] as num?)?.toInt() ?? 1,
        sentAt: j['sentAt'] as String? ?? DateTime.now().toIso8601String(),
        sentBy: j['sentBy'] as String? ?? 'Partner',
        viewCount: (j['viewCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaType': mediaType,
        'data': data,
        'nsfw': nsfw,
        'viewDuration': viewDuration,
        'maxReplays': maxReplays,
        'sentAt': sentAt,
        'sentBy': sentBy,
        'viewCount': viewCount,
      };
}

// ─── Moments Inbox ────────────────────────────────────────────────────────────

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  List<Moment> _moments = [];
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadMoments();
    _listenForSync();
  }

  void _loadMoments() {
    final storage = context.read<WebSocketService>().storage;
    final raw = storage.getMoments();
    setState(() {
      _moments = raw.map(Moment.fromJson).toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    });
  }

  void _listenForSync() {
    final ws = context.read<WebSocketService>();
    _syncSub = ws.onWidgetSync.listen((data) {
      if (data['syncType'] == 'moment' && mounted) {
        final moment = Moment.fromJson(Map<String, dynamic>.from(data));
        setState(() {
          _moments.insert(0, moment);
        });
        _persistMoments();
      }
    });
  }

  void _persistMoments() {
    final storage = context.read<WebSocketService>().storage;
    storage.setMoments(_moments.map((m) => m.toJson()).toList());
  }

  void _onMomentViewed(Moment moment) {
    setState(() => moment.viewCount++);
    _persistMoments();
  }

  Future<void> _openComposer() async {
    final ws = context.read<WebSocketService>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MomentComposerScreen(
          senderName: ws.storage.displayName ?? 'Me',
          onSend: (moment) {
            ws.sendWidgetSync('moment', moment.toJson());
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                    const Text(
                      'Moments',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _moments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_camera_rounded,
                                size: 56,
                                color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 16),
                            Text(
                              'No moments yet.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap + to send a photo or video.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _moments.length,
                        itemBuilder: (ctx, i) =>
                            _MomentCard(
                              moment: _moments[i],
                              onViewed: () => _onMomentViewed(_moments[i]),
                              onDelete: () {
                                setState(() => _moments.removeAt(i));
                                _persistMoments();
                              },
                            ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        backgroundColor: LockSyncTheme.primaryColor,
        child: const Icon(Icons.add_a_photo_rounded),
      ),
    );
  }
}

// ─── Moment Card ─────────────────────────────────────────────────────────────

class _MomentCard extends StatefulWidget {
  final Moment moment;
  final VoidCallback onViewed;
  final VoidCallback onDelete;

  const _MomentCard({
    required this.moment,
    required this.onViewed,
    required this.onDelete,
  });

  @override
  State<_MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<_MomentCard> {
  bool _nsfwRevealed = false;

  Uint8List? get _imageBytes {
    if (widget.moment.isVideo) return null;
    try {
      return base64Decode(widget.moment.data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openViewer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MomentViewerScreen(moment: widget.moment),
      ),
    );
    widget.onViewed();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final expired = m.isExpired;
    final bytes = _imageBytes;

    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      child: GestureDetector(
        onTap: expired ? null : _openViewer,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: expired
                  ? Colors.white.withValues(alpha: 0.05)
                  : LockSyncTheme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Thumbnail
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: expired
                      ? _ExpiredOverlay(mediaType: m.mediaType)
                      : m.isVideo
                          ? _VideoThumbnailPlaceholder(nsfw: m.nsfw)
                          : bytes != null
                              ? _ImageWithNsfw(
                                  bytes: bytes,
                                  nsfw: m.nsfw && !_nsfwRevealed,
                                  onReveal: () =>
                                      setState(() => _nsfwRevealed = true),
                                )
                              : const _BrokenMedia(),
                ),

                // Info bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          m.isVideo
                              ? Icons.videocam_rounded
                              : Icons.image_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'From ${m.sentBy}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        if (!expired) ...[
                          const Icon(Icons.timer_rounded,
                              color: Colors.white54, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(m.viewDuration),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${m.viewCount}/${m.maxReplays}',
                            style: TextStyle(
                              color: m.viewCount > 0
                                  ? Colors.amber
                                  : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ] else
                          const Text(
                            'Expired',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        const SizedBox(width: 8),
                        if (m.nsfw && !expired)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NSFW',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }
}

// ─── NSFW Image with blur ─────────────────────────────────────────────────────

class _ImageWithNsfw extends StatelessWidget {
  final Uint8List bytes;
  final bool nsfw;
  final VoidCallback onReveal;

  const _ImageWithNsfw({
    required this.bytes,
    required this.nsfw,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(bytes, fit: BoxFit.cover),
        if (nsfw)
          GestureDetector(
            onTap: onReveal,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.visibility_off_rounded,
                          color: Colors.white70, size: 36),
                      const SizedBox(height: 8),
                      const Text(
                        'Sensitive content',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to preview · tap card to open',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoThumbnailPlaceholder extends StatelessWidget {
  final bool nsfw;
  const _VideoThumbnailPlaceholder({required this.nsfw});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            nsfw ? Icons.visibility_off_rounded : Icons.play_circle_rounded,
            color: Colors.white54,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            nsfw ? 'Sensitive video — tap to open' : 'Tap to play',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ExpiredOverlay extends StatelessWidget {
  final String mediaType;
  const _ExpiredOverlay({required this.mediaType});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            mediaType == 'video'
                ? Icons.videocam_off_rounded
                : Icons.image_not_supported_rounded,
            color: Colors.white24,
            size: 40,
          ),
          const SizedBox(height: 8),
          const Text(
            'This moment has expired',
            style: TextStyle(color: Colors.white30, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _BrokenMedia extends StatelessWidget {
  const _BrokenMedia();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black54,
        child: const Center(
          child: Icon(Icons.broken_image_rounded,
              color: Colors.white30, size: 40),
        ),
      );
}

// ─── Moment Viewer (fullscreen with countdown) ────────────────────────────────

class MomentViewerScreen extends StatefulWidget {
  final Moment moment;
  const MomentViewerScreen({super.key, required this.moment});

  @override
  State<MomentViewerScreen> createState() => _MomentViewerScreenState();
}

class _MomentViewerScreenState extends State<MomentViewerScreen> {
  Timer? _timer;
  late int _remaining;
  VideoPlayerController? _videoController;
  bool _videoInitialised = false;
  bool _started = false;
  File? _videoFile;

  Uint8List? get _imageBytes {
    if (widget.moment.isVideo) return null;
    try {
      return base64Decode(widget.moment.data);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _remaining = widget.moment.viewDuration;
    if (widget.moment.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final bytes = base64Decode(widget.moment.data);
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/moment_${widget.moment.id}.mp4');
      await file.writeAsBytes(bytes);
      _videoFile = file;
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();
      if (mounted) setState(() => _videoInitialised = true);
    } catch (_) {}
  }

  void _startTimer() {
    if (_started) return;
    _started = true;
    _videoController?.play();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _timer?.cancel();
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController?.dispose();
    _videoFile?.deleteSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.moment;
    final bytes = _imageBytes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _startTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media
            if (m.isVideo)
              _videoInitialised && _videoController != null
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white54))
            else if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain)
            else
              const _BrokenMedia(),

            // Top bar: timer + replays
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      // Countdown bar
                      Expanded(
                        flex: 4,
                        child: _CountdownBar(
                          remaining: _remaining,
                          total: m.viewDuration,
                          started: _started,
                        ),
                      ),
                      const Spacer(),
                      // Replay indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.replay_rounded,
                                color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${m.viewCount + 1}/${m.maxReplays}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Tap-to-start hint
            if (!_started)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Tap anywhere to start timer',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountdownBar extends StatelessWidget {
  final int remaining;
  final int total;
  final bool started;

  const _CountdownBar({
    required this.remaining,
    required this.total,
    required this.started,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = started ? (remaining / total).clamp(0.0, 1.0) : 1.0;
    final color = fraction > 0.5
        ? Colors.green
        : fraction > 0.25
            ? Colors.amber
            : Colors.red;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          started ? _label(remaining) : _label(total),
          style:
              TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _label(int s) {
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  }
}

// ─── Moment Composer ─────────────────────────────────────────────────────────

class MomentComposerScreen extends StatefulWidget {
  final String senderName;
  final void Function(Moment) onSend;

  const MomentComposerScreen({
    super.key,
    required this.senderName,
    required this.onSend,
  });

  @override
  State<MomentComposerScreen> createState() => _MomentComposerScreenState();
}

class _MomentComposerScreenState extends State<MomentComposerScreen> {
  XFile? _pickedFile;
  String _mediaType = 'image';
  bool _nsfw = false;
  int _maxReplays = 1;
  bool _sending = false;

  // Duration unit (seconds / minutes / hours)
  String _durationUnit = 'seconds';
  int _durationValue = 10;

  int get _viewDurationSeconds {
    switch (_durationUnit) {
      case 'minutes':
        return _durationValue * 60;
      case 'hours':
        return _durationValue * 3600;
      default:
        return _durationValue;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (file != null) {
      setState(() {
        _pickedFile = file;
        _mediaType = 'image';
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (file != null) {
      setState(() {
        _pickedFile = file;
        _mediaType = 'video';
      });
    }
  }

  Future<void> _send() async {
    if (_pickedFile == null) return;
    setState(() => _sending = true);

    try {
      final bytes = await File(_pickedFile!.path).readAsBytes();
      final encoded = base64Encode(bytes);

      final moment = Moment(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        mediaType: _mediaType,
        data: encoded,
        nsfw: _nsfw,
        viewDuration: _viewDurationSeconds,
        maxReplays: _maxReplays,
        sentAt: DateTime.now().toIso8601String(),
        sentBy: widget.senderName,
      );

      widget.onSend(moment);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      'New Moment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _pickedFile != null && !_sending ? _send : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Send',
                              style: TextStyle(
                                color: _pickedFile != null
                                    ? LockSyncTheme.primaryColor
                                    : Colors.white30,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Media picker
                      GestureDetector(
                        onTap: _showMediaPicker,
                        child: Container(
                          height: 240,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: LockSyncTheme.primaryColor
                                  .withValues(alpha: 0.3),
                              style: _pickedFile == null
                                  ? BorderStyle.solid
                                  : BorderStyle.none,
                            ),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _pickedFile == null
                              ? _PickerPlaceholder(
                                  onPickImage: _pickImage,
                                  onPickVideo: _pickVideo,
                                )
                              : _MediaPreview(
                                  file: _pickedFile!,
                                  mediaType: _mediaType,
                                  onClear: () =>
                                      setState(() => _pickedFile = null),
                                ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // View duration
                      const _SectionLabel('View duration'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Numeric value
                          Expanded(
                            child: Slider(
                              value: _durationValue.toDouble(),
                              min: 1,
                              max: _durationUnit == 'seconds'
                                  ? 60
                                  : _durationUnit == 'minutes'
                                      ? 60
                                      : 24,
                              divisions: _durationUnit == 'seconds'
                                  ? 59
                                  : _durationUnit == 'minutes'
                                      ? 59
                                      : 23,
                              activeColor: LockSyncTheme.primaryColor,
                              label: '$_durationValue',
                              onChanged: (v) =>
                                  setState(() => _durationValue = v.round()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_durationValue',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          // Unit picker
                          _UnitPicker(
                            value: _durationUnit,
                            onChanged: (u) => setState(() {
                              _durationUnit = u;
                              // Reset to a sensible value for the new unit
                              _durationValue = u == 'seconds'
                                  ? 10
                                  : u == 'minutes'
                                      ? 1
                                      : 1;
                            }),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Text(
                          'Total: ${_formatLabel(_viewDurationSeconds)}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Replays
                      const _SectionLabel('Allowed replays'),
                      const SizedBox(height: 12),
                      Row(
                        children: [1, 2, 3].map((n) {
                          final selected = _maxReplays == n;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _maxReplays = n),
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? LockSyncTheme.primaryColor
                                      : Colors.white
                                          .withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(16),
                                  border: selected
                                      ? null
                                      : Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.15)),
                                ),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$n',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white60,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      n == 1 ? 'once' : '×',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white70
                                            : Colors.white30,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // NSFW toggle
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _nsfw
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _nsfw
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'NSFW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Sensitive content',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Blurred until partner taps to reveal',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _nsfw,
                              onChanged: (v) => setState(() => _nsfw = v),
                              activeThumbColor: Colors.red,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaPicker() {
    if (_pickedFile != null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_rounded, color: Colors.white70),
              title: const Text('Photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded,
                  color: Colors.white70),
              title: const Text('Video',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatLabel(int s) {
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  }
}

// ─── Composer helpers ────────────────────────────────────────────────────────

class _PickerPlaceholder extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;

  const _PickerPlaceholder({
    required this.onPickImage,
    required this.onPickVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_rounded,
            size: 48, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PickBtn(
                icon: Icons.image_rounded,
                label: 'Photo',
                onTap: onPickImage),
            const SizedBox(width: 16),
            _PickBtn(
                icon: Icons.videocam_rounded,
                label: 'Video',
                onTap: onPickVideo),
          ],
        ),
      ],
    );
  }
}

class _PickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: LockSyncTheme.primaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: LockSyncTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: LockSyncTheme.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: LockSyncTheme.primaryColor,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final XFile file;
  final String mediaType;
  final VoidCallback onClear;

  const _MediaPreview({
    required this.file,
    required this.mediaType,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (mediaType == 'image')
          Image.file(File(file.path), fit: BoxFit.cover)
        else
          Container(
            color: Colors.black,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_rounded, color: Colors.white54, size: 48),
                SizedBox(height: 8),
                Text('Video selected',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _UnitPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      dropdownColor: const Color(0xFF1A1A2E),
      style: const TextStyle(color: Colors.white),
      underline: const SizedBox(),
      items: const [
        DropdownMenuItem(value: 'seconds', child: Text('sec')),
        DropdownMenuItem(value: 'minutes', child: Text('min')),
        DropdownMenuItem(value: 'hours', child: Text('hr')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

