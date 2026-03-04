import 'package:flutter/material.dart';

/// A single draw stroke — a list of [Offset] points with rendering properties.
class DrawStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  const DrawStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  factory DrawStroke.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List<dynamic>).map((p) {
      final m = p as Map<String, dynamic>;
      return Offset(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
      );
    }).toList();
    return DrawStroke(
      points: pts,
      color: Color(json['color'] as int? ?? 0xFFFFFFFF),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'points': points
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList(),
        'color': color.value,
        'strokeWidth': strokeWidth,
      };
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _DrawingPainter extends CustomPainter {
  final List<DrawStroke> strokes;
  final DrawStroke? activeStroke;

  const _DrawingPainter({required this.strokes, this.activeStroke});

  @override
  void paint(Canvas canvas, Size size) {
    void drawStroke(DrawStroke stroke) {
      if (stroke.points.isEmpty) return;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        // Smooth curve through points.
        if (i < stroke.points.length - 1) {
          final mid = (stroke.points[i] + stroke.points[i + 1]) / 2;
          path.quadraticBezierTo(
              stroke.points[i].dx, stroke.points[i].dy, mid.dx, mid.dy);
        } else {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    for (final s in strokes) {
      drawStroke(s);
    }
    if (activeStroke != null) drawStroke(activeStroke!);
  }

  @override
  bool shouldRepaint(_DrawingPainter old) =>
      old.strokes != strokes || old.activeStroke != activeStroke;
}

// ── Widget ─────────────────────────────────────────────────────────────────────

/// An interactive drawing canvas that serialises strokes to/from JSON.
///
/// Calls [onStrokesChanged] after each completed stroke with the full
/// serialised list (for inclusion in HomeElement.properties).
class DrawingCanvasWidget extends StatefulWidget {
  const DrawingCanvasWidget({
    super.key,
    required this.strokes,
    required this.onStrokesChanged,
    this.penColor = Colors.white,
    this.penWidth = 3.0,
    this.isEditable = true,
  });

  /// Initial strokes decoded from storage.
  final List<DrawStroke> strokes;
  final void Function(List<DrawStroke>) onStrokesChanged;
  final Color penColor;
  final double penWidth;
  final bool isEditable;

  @override
  State<DrawingCanvasWidget> createState() => _DrawingCanvasWidgetState();
}

class _DrawingCanvasWidgetState extends State<DrawingCanvasWidget> {
  late List<DrawStroke> _strokes;
  DrawStroke? _activeStroke;

  @override
  void initState() {
    super.initState();
    _strokes = List.from(widget.strokes);
  }

  @override
  void didUpdateWidget(DrawingCanvasWidget old) {
    super.didUpdateWidget(old);
    if (old.strokes != widget.strokes) {
      _strokes = List.from(widget.strokes);
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.isEditable) return;
    setState(() {
      _activeStroke = DrawStroke(
        points: [details.localPosition],
        color: widget.penColor,
        strokeWidth: widget.penWidth,
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isEditable || _activeStroke == null) return;
    setState(() {
      _activeStroke = DrawStroke(
        points: [..._activeStroke!.points, details.localPosition],
        color: _activeStroke!.color,
        strokeWidth: _activeStroke!.strokeWidth,
      );
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (!widget.isEditable || _activeStroke == null) return;
    final completed = _activeStroke!;
    setState(() {
      _strokes = [..._strokes, completed];
      _activeStroke = null;
    });
    widget.onStrokesChanged(_strokes);
  }

  /// Undo the last stroke.
  void undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes = _strokes.sublist(0, _strokes.length - 1));
    widget.onStrokesChanged(_strokes);
  }

  /// Clear all strokes.
  void clear() {
    setState(() => _strokes = []);
    widget.onStrokesChanged(_strokes);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        painter: _DrawingPainter(
          strokes: _strokes,
          activeStroke: _activeStroke,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
