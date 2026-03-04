import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../models/home_element.dart';
import '../../models/layout_state.dart';
import '../../providers/app_providers.dart';
import '../../services/peer_connection_service.dart';
import 'widgets/draggable_element.dart';
import 'widgets/text_note_widget.dart';
import 'widgets/drawing_canvas_widget.dart';
import 'widgets/element_toolbar.dart';

class HomescreenEditor extends ConsumerStatefulWidget {
  const HomescreenEditor({super.key});

  @override
  ConsumerState<HomescreenEditor> createState() => _HomescreenEditorState();
}

class _HomescreenEditorState extends ConsumerState<HomescreenEditor> {
  final _uuid = const Uuid();

  String? _selectedElementId;
  String? _editingElementId; // Text element being edited inline.

  /// Tracks which drawing canvas is currently in draw mode.
  String? _activeDrawingElementId;

  @override
  void initState() {
    super.initState();
    _initLayout();
    _listenLayoutChanges();
  }

  Future<void> _initLayout() async {
    final space = ref.read(spaceProvider);
    if (space == null) return;

    final controller = ref.read(appControllerProvider);
    final manager = controller.layoutManager;
    if (manager == null) return;

    // Mirror layout into the provider for UI reads.
    manager.addListener(() {
      if (mounted) {
        ref.read(layoutProvider.notifier).state = manager.layout;
      }
    });
    // Trigger first read.
    ref.read(layoutProvider.notifier).state = manager.layout;
  }

  void _listenLayoutChanges() {
    // Connection status badge.
    ref.listenManual(connectionStatusProvider, (_, __) {});
  }

  // ── Element creation ──────────────────────────────────────────────

  Future<void> _addTextNote(Offset position) async {
    final element = HomeElement.create(
      elementId: _uuid.v4(),
      type: AppConstants.elementTextNote,
      position: ElementPosition(x: position.dx, y: position.dy),
      properties: {
        'text': '',
        'color': Colors.white.value,
        'fontSize': 16.0,
      },
    );
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;

    final event = await manager.addElement(element);
    // SyncEngine picks up the event from eventStream automatically.
    setState(() {
      _selectedElementId = element.elementId;
      _editingElementId = element.elementId;
    });
  }

  Future<void> _addDrawingCanvas(Offset position) async {
    final element = HomeElement.create(
      elementId: _uuid.v4(),
      type: AppConstants.elementDrawingCanvas,
      position: ElementPosition(x: position.dx, y: position.dy),
      properties: {'strokes': []},
      zIndex: 0,
    );
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;

    await manager.addElement(element);
    setState(() {
      _selectedElementId = element.elementId;
      _activeDrawingElementId = element.elementId;
    });
  }

  // ── Element interactions ──────────────────────────────────────────

  void _selectElement(String id) {
    setState(() {
      _selectedElementId = (_selectedElementId == id) ? null : id;
      if (_selectedElementId == null) {
        _editingElementId = null;
        _activeDrawingElementId = null;
      }
    });
  }

  Future<void> _moveElement(HomeElement element, ElementPosition pos) async {
    final updated = element.copyWith(position: pos);
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.updateElement(updated);
  }

  Future<void> _resizeElement(HomeElement element, ElementSize size) async {
    final updated = element.copyWith(size: size);
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.updateElement(updated);
  }

  Future<void> _deleteElement(String elementId) async {
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.deleteElement(elementId);
    setState(() {
      if (_selectedElementId == elementId) _selectedElementId = null;
      if (_editingElementId == elementId) _editingElementId = null;
      if (_activeDrawingElementId == elementId) {
        _activeDrawingElementId = null;
      }
    });
  }

  Future<void> _updateTextContent(HomeElement element, String text) async {
    final props = Map<String, dynamic>.from(element.properties)
      ..['text'] = text;
    final updated = element.copyWith(properties: props);
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.updateElement(updated);
  }

  Future<void> _updateStrokes(
      HomeElement element, List<DrawStroke> strokes) async {
    final props = Map<String, dynamic>.from(element.properties)
      ..['strokes'] = strokes.map((s) => s.toJson()).toList();
    final updated = element.copyWith(properties: props);
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.updateElement(updated);
  }

  Future<void> _changeBackground(int color) async {
    final manager = ref.read(appControllerProvider).layoutManager;
    if (manager == null) return;
    await manager.changeBackground(color);
  }

  // ── Canvas tap → deselect ─────────────────────────────────────────

  void _onCanvasTap() {
    setState(() {
      _selectedElementId = null;
      _editingElementId = null;
      _activeDrawingElementId = null;
    });
  }

  // ── Bottom-sheet helpers ──────────────────────────────────────────

  void _showAddElementMenu(BuildContext ctx, BoxConstraints constraints) {
    final canvasCenter = Offset(
      constraints.maxWidth / 2 - AppConstants.defaultElementWidth / 2,
      constraints.maxHeight / 2 - AppConstants.defaultElementHeight / 2,
    );
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Element',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _AddOption(
              icon: Icons.text_fields_rounded,
              color: const Color(0xFF6C63FF),
              label: 'Text Note',
              onTap: () {
                Navigator.pop(ctx);
                _addTextNote(canvasCenter);
              },
            ),
            const SizedBox(height: 8),
            _AddOption(
              icon: Icons.draw_rounded,
              color: const Color(0xFF43E97B),
              label: 'Drawing Canvas',
              onTap: () {
                Navigator.pop(ctx);
                _addDrawingCanvas(canvasCenter);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBackgroundPicker(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => BackgroundColorPicker(
        onColorSelected: _changeBackground,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(layoutProvider);
    final status = ref.watch(connectionStatusProvider);
    final space = ref.watch(spaceProvider);

    final bgColor = layout?.backgroundColor != null
        ? Color(layout!.backgroundColor!)
        : const Color(0xFF0D0D1A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(status, space?.spaceName),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTap: _onCanvasTap,
            behavior: HitTestBehavior.translucent,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ── Element layer ──────────────────────────────
                if (layout != null)
                  ...layout.elements.map((el) =>
                      _buildElement(el, canvasSize)),
                // ── Toolbar ────────────────────────────────────
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElementToolbar(
                          onAddTextNote: () =>
                              _showAddElementMenu(ctx, constraints),
                          onAddDrawingCanvas: () =>
                              _showAddElementMenu(ctx, constraints),
                          onChangeBackground: () =>
                              _showBackgroundPicker(ctx),
                          onOpenMembers: () => context.push('/members'),
                          onOpenSettings: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Builder(
        builder: (ctx) => FloatingActionButton(
          onPressed: () {
            final mq = MediaQuery.of(context);
            final topPad = kToolbarHeight + mq.padding.top;
            final bottomPad = 80 + mq.padding.bottom;
            final fakeConstraints = BoxConstraints.tight(
              Size(mq.size.width, mq.size.height - topPad - bottomPad),
            );
            _showAddElementMenu(ctx, fakeConstraints);
          },
          backgroundColor: const Color(0xFF6C63FF),
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      PeerConnectionStatus status, String? spaceName) {
    final statusColor = status == PeerConnectionStatus.connected
        ? const Color(0xFF43E97B)
        : status == PeerConnectionStatus.connecting
            ? const Color(0xFFFFBF00)
            : const Color(0xFFFF6584);

    final statusLabel = status == PeerConnectionStatus.connected
        ? 'Live'
        : status == PeerConnectionStatus.connecting
            ? 'Connecting…'
            : 'Offline';

    return AppBar(
      backgroundColor: Colors.black.withOpacity(0.3),
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            spaceName ?? 'LockSync',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: statusColor.withOpacity(0.5), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildElement(HomeElement element, Size canvasSize) {
    final isSelected = _selectedElementId == element.elementId;
    return DraggableElement(
      key: ValueKey(element.elementId),
      element: element,
      isSelected: isSelected,
      canvasSize: canvasSize,
      onTap: () => _selectElement(element.elementId),
      onMoved: (pos) => _moveElement(element, pos),
      onResized: (size) => _resizeElement(element, size),
      onDeleted: () => _deleteElement(element.elementId),
      child: _buildElementContent(element, isSelected),
    );
  }

  Widget _buildElementContent(HomeElement element, bool isSelected) {
    switch (element.type) {
      case AppConstants.elementTextNote:
        return _buildTextNote(element, isSelected);

      case AppConstants.elementDrawingCanvas:
        return _buildDrawingCanvas(element, isSelected);

      case AppConstants.elementMovableWidget:
        return _buildMovableWidget(element);

      default:
        return Container(
          color: Colors.white12,
          child: const Center(
            child: Text('Unknown element',
                style: TextStyle(color: Colors.white54)),
          ),
        );
    }
  }

  Widget _buildTextNote(HomeElement element, bool isSelected) {
    final props = element.properties;
    final text = props['text'] as String? ?? '';
    final colorVal = props['color'] as int? ?? Colors.white.value;
    final fontSize = (props['fontSize'] as num?)?.toDouble() ?? 16.0;
    final isEditing = _editingElementId == element.elementId;

    return GestureDetector(
      onDoubleTap: isSelected
          ? () => setState(() => _editingElementId = element.elementId)
          : null,
      child: TextNoteWidget(
        text: text,
        color: Color(colorVal),
        fontSize: fontSize,
        isEditing: isEditing,
        onTextChanged: (t) => _updateTextContent(element, t),
      ),
    );
  }

  Widget _buildDrawingCanvas(HomeElement element, bool isSelected) {
    final rawStrokes =
        element.properties['strokes'] as List<dynamic>? ?? [];
    final strokes = rawStrokes
        .map((s) => DrawStroke.fromJson(s as Map<String, dynamic>))
        .toList();

    final isDrawing = _activeDrawingElementId == element.elementId;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DrawingCanvasWidget(
            strokes: strokes,
            isEditable: isDrawing,
            penColor: Colors.white,
            penWidth: 3.0,
            onStrokesChanged: (updated) => _updateStrokes(element, updated),
          ),
        ),
        if (isSelected && !isDrawing)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _activeDrawingElementId = element.elementId),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF43E97B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Draw',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        if (isDrawing)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () =>
                  setState(() => _activeDrawingElementId = null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6584),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Done',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMovableWidget(HomeElement element) {
    final widgetType =
        element.properties['widgetType'] as String? ?? 'clock';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.widgets_rounded,
                color: Colors.white54, size: 28),
            const SizedBox(height: 4),
            Text(widgetType,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Helper widget ──────────────────────────────────────────────────────────────

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
    );
  }
}
