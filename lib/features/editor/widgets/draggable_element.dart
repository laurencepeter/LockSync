import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/home_element.dart';

/// Wraps any homescreen element with:
///   • Drag-to-move (fires [onMoved])
///   • Corner-handle resize (fires [onResized])
///   • Tap-to-select / deselect
///   • Long-press → delete confirmation (fires [onDeleted])
class DraggableElement extends StatefulWidget {
  const DraggableElement({
    super.key,
    required this.element,
    required this.isSelected,
    required this.canvasSize,
    required this.onTap,
    required this.onMoved,
    required this.onResized,
    required this.onDeleted,
    required this.child,
  });

  final HomeElement element;
  final bool isSelected;
  final Size canvasSize;
  final VoidCallback onTap;
  final void Function(ElementPosition) onMoved;
  final void Function(ElementSize) onResized;
  final VoidCallback onDeleted;
  final Widget child;

  @override
  State<DraggableElement> createState() => _DraggableElementState();
}

class _DraggableElementState extends State<DraggableElement> {
  late double _x;
  late double _y;
  late double _w;
  late double _h;

  double _startX = 0;
  double _startY = 0;
  double _startW = 0;
  double _startH = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DraggableElement old) {
    super.didUpdateWidget(old);
    if (old.element != widget.element) _sync();
  }

  void _sync() {
    _x = widget.element.position.x;
    _y = widget.element.position.y;
    _w = widget.element.size.width;
    _h = widget.element.size.height;
  }

  // ── Drag body (move) ──────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    _startX = _x;
    _startY = _y;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _x = (_startX + d.localPosition.dx - _w / 2)
          .clamp(0, widget.canvasSize.width - _w);
      _y = (_startY + d.localPosition.dy - _h / 2)
          .clamp(0, widget.canvasSize.height - _h);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    widget.onMoved(ElementPosition(x: _x, y: _y));
  }

  // ── Corner handle (resize) ────────────────────────────────────────

  void _onHandleDragStart(DragStartDetails _) {
    _startW = _w;
    _startH = _h;
  }

  void _onHandleDragUpdate(DragUpdateDetails d) {
    setState(() {
      _w = (_startW + d.delta.dx)
          .clamp(AppConstants.minElementWidth, widget.canvasSize.width - _x);
      _h = (_startH + d.delta.dy)
          .clamp(AppConstants.minElementHeight, widget.canvasSize.height - _y);
    });
  }

  void _onHandleDragEnd(DragEndDetails _) {
    widget.onResized(ElementSize(width: _w, height: _h));
  }

  void _confirmDelete(BuildContext ctx) {
    showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete element?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFFF6584)))),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) widget.onDeleted();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () => _confirmDelete(context),
        onPanStart: widget.isSelected ? _onDragStart : null,
        onPanUpdate: widget.isSelected ? _onDragUpdate : null,
        onPanEnd: widget.isSelected ? _onDragEnd : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Element content ──────────────────────────────────
            Container(
              width: _w,
              height: _h,
              decoration: widget.isSelected
                  ? BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF6C63FF),
                        width: AppConstants.selectionBorderWidth,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                    widget.isSelected ? 6 : 0),
                child: widget.child,
              ),
            ),
            // ── Bottom-right resize handle (shown when selected) ──
            if (widget.isSelected)
              Positioned(
                right: -AppConstants.handleSize / 2,
                bottom: -AppConstants.handleSize / 2,
                child: GestureDetector(
                  onPanStart: _onHandleDragStart,
                  onPanUpdate: _onHandleDragUpdate,
                  onPanEnd: _onHandleDragEnd,
                  child: Container(
                    width: AppConstants.handleSize,
                    height: AppConstants.handleSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
