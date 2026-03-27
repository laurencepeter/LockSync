import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/canvas_models.dart';
import '../services/websocket_service.dart';
import '../services/wallpaper_service.dart';
import '../theme.dart';

enum CanvasTool { draw, text, eraser, sticker, select }

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  CanvasTool _currentTool = CanvasTool.draw;
  Color _currentColor = LockSyncTheme.primaryColor;
  double _penThickness = 3.0;
  double _textSize = 18.0;
  String _selectedFont = 'Inter';

  CanvasState _canvasState = CanvasState();
  final List<CanvasState> _undoStack = [];
  final List<CanvasState> _redoStack = [];

  // Current in-progress stroke
  List<Offset> _currentStrokePoints = [];

  // Text editing
  int? _draggingTextIndex;
  Offset? _dragStartOffset;

  // Sticker dragging
  int? _draggingStickerIndex;

  // Live sync from partner
  StreamSubscription? _canvasSyncSub;
  Timer? _sendThrottle;
  bool _isDrawing = false;
  Map<String, dynamic>? _pendingPartnerUpdate;

  static const Map<String, int> _canvasThemes = {
    'default':  0xFF0F0F1A,
    'midnight': 0xFF000000,
    'rose':     0xFF1A070F,
    'ocean':    0xFF071422,
    'forest':   0xFF071A0F,
    'sunset':   0xFF1A0F07,
    'lavender': 0xFF130A1A,
  };

  Color _getThemeColor() =>
      Color(_canvasThemes[_canvasState.theme] ?? 0xFF0F0F1A);

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Canvas Theme',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _canvasThemes.entries.map((entry) {
                  final isSelected = _canvasState.theme == entry.key;
                  return GestureDetector(
                    onTap: () {
                      _pushUndo();
                      setState(() => _canvasState.theme = entry.key);
                      _saveAndSync();
                      Navigator.pop(ctx);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Color(entry.value),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? LockSyncTheme.primaryColor
                                  : Colors.white24,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 24)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.key[0].toUpperCase() +
                              entry.key.substring(1),
                          style: TextStyle(
                            color: isSelected
                                ? LockSyncTheme.primaryColor
                                : Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _fontOptions = [
    'Inter',
    'Caveat',
    'Merriweather',
    'Roboto',
    'Pacifico',
    'JetBrains Mono',
  ];

  static const List<String> _stickerEmojis = [
    '\u2764\uFE0F', '\uD83D\uDE0D', '\uD83D\uDD25', '\u2B50', '\uD83D\uDC4D',
    '\uD83D\uDE02', '\uD83C\uDF39', '\uD83C\uDF1F', '\uD83D\uDCAF', '\uD83E\uDD70',
    '\uD83D\uDE18', '\uD83D\uDC95', '\uD83C\uDF08', '\uD83C\uDF89', '\uD83E\uDD29',
    '\uD83E\uDD17', '\uD83D\uDE4C', '\uD83D\uDCA5', '\uD83C\uDF1E', '\uD83C\uDF0A',
  ];

  @override
  void initState() {
    super.initState();
    _loadCanvasState();

    // Listen for live partner canvas updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = context.read<WebSocketService>();
      _canvasSyncSub = ws.onCanvasSync.listen(_onPartnerCanvasUpdate);
    });
  }

  @override
  void dispose() {
    _canvasSyncSub?.cancel();
    _sendThrottle?.cancel();
    super.dispose();
  }

  /// When partner sends canvas data, update the local canvas. If the user
  /// is mid-stroke, queue the update so it applies once the stroke finishes.
  void _onPartnerCanvasUpdate(Map<String, dynamic> data) {
    if (_isDrawing) {
      _pendingPartnerUpdate = data;
      return;
    }
    _applyPartnerUpdate(data);
  }

  void _applyPartnerUpdate(Map<String, dynamic> data) {
    final incoming = CanvasState.fromJson(data);
    setState(() {
      _canvasState = incoming;
    });
  }

  void _loadCanvasState() {
    final storage = context.read<WebSocketService>().storage;
    final saved = storage.canvasState;
    if (saved != null) {
      try {
        _canvasState = CanvasState.fromJson(jsonDecode(saved));
      } catch (_) {}
    }
    // Load user color/font preferences
    _currentColor = Color(storage.userColor);
    _selectedFont = storage.userFont;
  }

  void _saveAndSync() {
    final storage = context.read<WebSocketService>().storage;
    final json = jsonEncode(_canvasState.toJson());
    storage.setCanvasState(json);

    final ws = context.read<WebSocketService>();
    ws.sendCanvasData(_canvasState.toJson());
  }

  void _pushUndo() {
    _undoStack.add(CanvasState.fromJson(_canvasState.toJson()));
    _redoStack.clear();
    if (_undoStack.length > 30) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(CanvasState.fromJson(_canvasState.toJson()));
    setState(() {
      _canvasState = _undoStack.removeLast();
    });
    _saveAndSync();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(CanvasState.fromJson(_canvasState.toJson()));
    setState(() {
      _canvasState = _redoStack.removeLast();
    });
    _saveAndSync();
  }

  void _onPanStart(DragStartDetails details) {
    if (_currentTool == CanvasTool.draw || _currentTool == CanvasTool.eraser) {
      _pushUndo();
      _isDrawing = true;
      _currentStrokePoints = [details.localPosition];
    } else if (_currentTool == CanvasTool.select) {
      _tryStartDrag(details.localPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentTool == CanvasTool.draw || _currentTool == CanvasTool.eraser) {
      setState(() {
        _currentStrokePoints.add(details.localPosition);
      });
      // Throttled live sync so partner sees strokes as they're drawn
      _throttledSync();
    } else if (_currentTool == CanvasTool.select) {
      _updateDrag(details.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentTool == CanvasTool.draw || _currentTool == CanvasTool.eraser) {
      setState(() {
        _canvasState.strokes.add(CanvasStroke(
          points: List.from(_currentStrokePoints),
          color: _currentTool == CanvasTool.eraser
              ? 0xFF0F0F1A
              : _currentColor.toARGB32(),
          thickness:
              _currentTool == CanvasTool.eraser ? 20.0 : _penThickness,
          isEraser: _currentTool == CanvasTool.eraser,
        ));
        _currentStrokePoints = [];
      });
      _isDrawing = false;
      _sendThrottle?.cancel();
      _saveAndSync();
      // Apply any queued partner update that arrived mid-stroke
      if (_pendingPartnerUpdate != null) {
        final pending = _pendingPartnerUpdate!;
        _pendingPartnerUpdate = null;
        // Apply partner's update then re-sync so both sides converge
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applyPartnerUpdate(pending);
            _saveAndSync();
          }
        });
      }
    } else if (_currentTool == CanvasTool.select) {
      _endDrag();
    }
  }

  /// Send canvas data at most every 150ms during active drawing so the
  /// partner sees strokes appearing in real-time.
  void _throttledSync() {
    if (_sendThrottle?.isActive ?? false) return;
    _sendThrottle = Timer(const Duration(milliseconds: 150), () {
      // Build a temporary state that includes the in-progress stroke
      final tempState = CanvasState.fromJson(_canvasState.toJson());
      if (_currentStrokePoints.isNotEmpty) {
        tempState.strokes.add(CanvasStroke(
          points: List.from(_currentStrokePoints),
          color: _currentTool == CanvasTool.eraser
              ? 0xFF0F0F1A
              : _currentColor.toARGB32(),
          thickness:
              _currentTool == CanvasTool.eraser ? 20.0 : _penThickness,
          isEraser: _currentTool == CanvasTool.eraser,
        ));
      }
      final ws = context.read<WebSocketService>();
      ws.sendCanvasData(tempState.toJson());
    });
  }

  void _tryStartDrag(Offset pos) {
    // Check stickers first (on top)
    for (int i = _canvasState.stickers.length - 1; i >= 0; i--) {
      final s = _canvasState.stickers[i];
      if ((pos - Offset(s.x, s.y)).distance < s.size) {
        _draggingStickerIndex = i;
        _dragStartOffset = Offset(pos.dx - s.x, pos.dy - s.y);
        return;
      }
    }
    // Check text elements
    for (int i = _canvasState.textElements.length - 1; i >= 0; i--) {
      final t = _canvasState.textElements[i];
      final rect = Rect.fromLTWH(t.x, t.y, 200, t.fontSize + 10);
      if (rect.contains(pos)) {
        _pushUndo();
        _draggingTextIndex = i;
        _dragStartOffset = Offset(pos.dx - t.x, pos.dy - t.y);
        return;
      }
    }
  }

  void _updateDrag(Offset pos) {
    if (_draggingTextIndex != null && _dragStartOffset != null) {
      setState(() {
        _canvasState.textElements[_draggingTextIndex!].x =
            pos.dx - _dragStartOffset!.dx;
        _canvasState.textElements[_draggingTextIndex!].y =
            pos.dy - _dragStartOffset!.dy;
      });
    }
    if (_draggingStickerIndex != null && _dragStartOffset != null) {
      setState(() {
        _canvasState.stickers[_draggingStickerIndex!].x =
            pos.dx - _dragStartOffset!.dx;
        _canvasState.stickers[_draggingStickerIndex!].y =
            pos.dy - _dragStartOffset!.dy;
      });
    }
  }

  void _endDrag() {
    if (_draggingTextIndex != null || _draggingStickerIndex != null) {
      _saveAndSync();
    }
    _draggingTextIndex = null;
    _draggingStickerIndex = null;
    _dragStartOffset = null;
  }

  void _onTapCanvas(TapUpDetails details) {
    if (_currentTool == CanvasTool.text) {
      _showTextInputDialog(details.localPosition);
    } else if (_currentTool == CanvasTool.sticker) {
      _showStickerPicker(details.localPosition);
    }
  }

  void _showTextInputDialog(Offset position) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Text', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Type your text...',
            hintStyle: TextStyle(color: Colors.white30),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _pushUndo();
                final storage = context.read<WebSocketService>().storage;
                setState(() {
                  _canvasState.textElements.add(CanvasTextElement(
                    text: controller.text,
                    x: position.dx,
                    y: position.dy,
                    color: _currentColor.toARGB32(),
                    fontSize: _textSize,
                    fontFamily: _selectedFont,
                    addedBy: storage.displayName ?? '',
                  ));
                });
                _saveAndSync();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showStickerPicker(Offset position) {
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
              'Pick a Sticker',
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
              children: _stickerEmojis.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    _pushUndo();
                    setState(() {
                      _canvasState.stickers.add(CanvasStickerElement(
                        emoji: emoji,
                        x: position.dx,
                        y: position.dy,
                      ));
                    });
                    _saveAndSync();
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
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

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            const Text('Pick a Color', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _currentColor,
            onColorChanged: (color) {
              setState(() => _currentColor = color);
            },
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final storage = context.read<WebSocketService>().storage;
              storage.setUserColor(_currentColor.toARGB32());
              Navigator.pop(ctx);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showFontPicker() {
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
              'Choose Font',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(_fontOptions.length, (i) {
              final font = _fontOptions[i];
              final isSelected = _selectedFont == font;
              return ListTile(
                title: Text(
                  'Sample Text',
                  style: _getGoogleFont(font).copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  font,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle,
                        color: LockSyncTheme.accentColor)
                    : null,
                onTap: () {
                  setState(() => _selectedFont = font);
                  context.read<WebSocketService>().storage.setUserFont(font);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  TextStyle _getGoogleFont(String fontName) {
    switch (fontName) {
      case 'Caveat':
        return GoogleFonts.caveat();
      case 'Merriweather':
        return GoogleFonts.merriweather();
      case 'Roboto':
        return GoogleFonts.roboto();
      case 'Pacifico':
        return GoogleFonts.pacifico();
      case 'JetBrains Mono':
        return GoogleFonts.jetBrainsMono();
      default:
        return GoogleFonts.inter();
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image != null) {
      _pushUndo();
      setState(() {
        _canvasState.backgroundImagePath = image.path;
      });
      _saveAndSync();
    }
  }

  Future<void> _captureAndSetWallpaper() async {
    try {
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      if (!mounted) return;
      await WallpaperService.setLockScreenWallpaper(
        bytes,
        context: context,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set wallpaper: $e')),
        );
      }
    }
  }

  Future<void> _saveMemory() async {
    final storage = context.read<WebSocketService>().storage;
    final memory = {
      'canvas': _canvasState.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    await storage.saveMemory(memory);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas saved to memories!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Canvas'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            onPressed: _undoStack.isNotEmpty ? _undo : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            tooltip: 'Redo',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: const Color(0xFF1A1A2E),
            onSelected: (value) {
              switch (value) {
                case 'wallpaper':
                  _captureAndSetWallpaper();
                  break;
                case 'theme':
                  _showThemePicker();
                  break;
                case 'photo':
                  _pickImage();
                  break;
                case 'memory':
                  _saveMemory();
                  break;
                case 'clear':
                  _pushUndo();
                  setState(() => _canvasState = CanvasState());
                  _saveAndSync();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'wallpaper',
                child: Row(
                  children: [
                    Icon(Icons.wallpaper_rounded, color: Colors.white70),
                    SizedBox(width: 12),
                    Text('Set as Lock Screen',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(Icons.color_lens_rounded, color: Colors.white70),
                    SizedBox(width: 12),
                    Text('Canvas Theme',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'photo',
                child: Row(
                  children: [
                    Icon(Icons.photo_rounded, color: Colors.white70),
                    SizedBox(width: 12),
                    Text('Background Photo',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'memory',
                child: Row(
                  children: [
                    Icon(Icons.bookmark_rounded, color: Colors.white70),
                    SizedBox(width: 12),
                    Text('Save to Memories',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Clear Canvas',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas area
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onTapUp: _onTapCanvas,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  color: _getThemeColor(),
                  child: Stack(
                    children: [
                      // Background image
                      if (_canvasState.backgroundImagePath != null)
                        Positioned.fill(
                          child: Image.file(
                            File(_canvasState.backgroundImagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                        ),

                      // Drawing layer
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CanvasPainter(
                            strokes: _canvasState.strokes,
                            currentStroke: _currentStrokePoints,
                            currentColor: _currentTool == CanvasTool.eraser
                                ? const Color(0xFF0F0F1A)
                                : _currentColor,
                            currentThickness: _currentTool == CanvasTool.eraser
                                ? 20.0
                                : _penThickness,
                          ),
                        ),
                      ),

                      // Text elements
                      ..._canvasState.textElements
                          .asMap()
                          .entries
                          .map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return Positioned(
                          left: t.x,
                          top: t.y,
                          child: GestureDetector(
                            onLongPress: () {
                              // Delete on long press
                              _pushUndo();
                              setState(() {
                                _canvasState.textElements.removeAt(i);
                              });
                              _saveAndSync();
                            },
                            child: Text(
                              t.text,
                              style: _getGoogleFont(t.fontFamily).copyWith(
                                color: Color(t.color),
                                fontSize: t.fontSize,
                              ),
                            ),
                          ),
                        );
                      }),

                      // Sticker elements
                      ..._canvasState.stickers
                          .asMap()
                          .entries
                          .map((entry) {
                        final i = entry.key;
                        final s = entry.value;
                        return Positioned(
                          left: s.x - s.size / 2,
                          top: s.y - s.size / 2,
                          child: GestureDetector(
                            onLongPress: () {
                              _pushUndo();
                              setState(() {
                                _canvasState.stickers.removeAt(i);
                              });
                              _saveAndSync();
                            },
                            child: Text(
                              s.emoji,
                              style: TextStyle(fontSize: s.size),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Toolbar
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tool selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolButton(CanvasTool.draw, Icons.brush_rounded, 'Draw'),
                _toolButton(CanvasTool.eraser, Icons.auto_fix_high_rounded, 'Erase'),
                _toolButton(CanvasTool.text, Icons.text_fields_rounded, 'Text'),
                _toolButton(CanvasTool.sticker, Icons.emoji_emotions_rounded, 'Sticker'),
                _toolButton(CanvasTool.select, Icons.open_with_rounded, 'Move'),
              ],
            ),

            const SizedBox(height: 8),

            // Options row based on tool
            if (_currentTool == CanvasTool.draw ||
                _currentTool == CanvasTool.eraser) ...[
              Row(
                children: [
                  // Color picker
                  if (_currentTool == CanvasTool.draw)
                    GestureDetector(
                      onTap: _showColorPicker,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 2),
                        ),
                      ),
                    ),
                  if (_currentTool == CanvasTool.draw)
                    const SizedBox(width: 12),
                  // Thickness slider
                  Expanded(
                    child: Slider(
                      value: _currentTool == CanvasTool.eraser
                          ? 20.0
                          : _penThickness,
                      min: 1,
                      max: _currentTool == CanvasTool.eraser ? 40 : 15,
                      onChanged: (v) {
                        setState(() {
                          if (_currentTool != CanvasTool.eraser) {
                            _penThickness = v;
                          }
                        });
                      },
                      activeColor: LockSyncTheme.primaryColor,
                    ),
                  ),
                  Text(
                    _currentTool == CanvasTool.eraser
                        ? 'Eraser'
                        : '${_penThickness.toStringAsFixed(0)}px',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ] else if (_currentTool == CanvasTool.text) ...[
              Row(
                children: [
                  GestureDetector(
                    onTap: _showColorPicker,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _currentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white30, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showFontPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _selectedFont,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _textSize,
                      min: 12,
                      max: 48,
                      onChanged: (v) => setState(() => _textSize = v),
                      activeColor: LockSyncTheme.primaryColor,
                    ),
                  ),
                  Text(
                    '${_textSize.toStringAsFixed(0)}pt',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    'Tap on canvas to place, long-press to delete',
                    style: TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolButton(CanvasTool tool, IconData icon, String label) {
    final isActive = _currentTool == tool;
    return GestureDetector(
      onTap: () => setState(() => _currentTool = tool),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? LockSyncTheme.primaryColor.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? LockSyncTheme.primaryColor : Colors.white38,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? LockSyncTheme.primaryColor : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Canvas Painter ──────────────────────────────────────────────────
class _CanvasPainter extends CustomPainter {
  final List<CanvasStroke> strokes;
  final List<Offset> currentStroke;
  final Color currentColor;
  final double currentThickness;

  _CanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentColor,
    required this.currentThickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, Color(stroke.color), stroke.thickness,
          stroke.isEraser);
    }

    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, currentColor, currentThickness, false);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> points, Color color,
      double thickness, bool isEraser) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isEraser) {
      paint.blendMode = BlendMode.clear;
    }

    if (points.length == 1) {
      canvas.drawCircle(points[0], thickness / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}
