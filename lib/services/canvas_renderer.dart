import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/canvas_models.dart';

// ──────────────────────────────────────────────────────────────────────────────
// CanvasRenderer
//
// Renders a [CanvasState] to PNG bytes using dart:ui primitives only —
// no Flutter widget tree required.  Works from the main isolate AND from
// the flutter_background_service isolate.
// ──────────────────────────────────────────────────────────────────────────────

class CanvasRenderer {
  CanvasRenderer._();

  static const int _defaultWidth = 1080;
  static const int _defaultHeight = 1920;

  /// Renders [canvasJson] to PNG bytes at the given [width] × [height].
  /// Returns null on any error.
  static Future<Uint8List?> renderToBytes(
    Map<String, dynamic> canvasJson, {
    int width = _defaultWidth,
    int height = _defaultHeight,
  }) async {
    try {
      final state = CanvasState.fromJson(canvasJson);
      return await _render(state, width, height);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _render(
    CanvasState state,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Background fill — colour follows the canvas theme
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = _themeToColor(state.theme),
    );

    // Background image (loaded from local file path)
    if (state.backgroundImagePath != null) {
      await _drawBackgroundImage(
        canvas,
        state.backgroundImagePath!,
        width,
        height,
      );
    }

    // Strokes
    for (final stroke in state.strokes) {
      _drawStroke(canvas, stroke);
    }

    // Text elements
    for (final element in state.textElements) {
      _drawText(canvas, element);
    }

    // Sticker emojis
    for (final sticker in state.stickers) {
      _drawSticker(canvas, sticker);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData?.buffer.asUint8List();
  }

  static ui.Color _themeToColor(String theme) {
    const themes = <String, int>{
      'default':  0xFF0F0F1A,
      'midnight': 0xFF000000,
      'rose':     0xFF1A070F,
      'ocean':    0xFF071422,
      'forest':   0xFF071A0F,
      'sunset':   0xFF1A0F07,
      'lavender': 0xFF130A1A,
    };
    return ui.Color(themes[theme] ?? 0xFF0F0F1A);
  }

  static Future<void> _drawBackgroundImage(
    ui.Canvas canvas,
    String path,
    int width,
    int height,
  ) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final src = ui.Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst =
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas.drawImageRect(image, src, dst, ui.Paint());
      image.dispose();
    } catch (_) {
      // If the image can't be loaded, silently skip it
    }
  }

  static void _drawStroke(ui.Canvas canvas, CanvasStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = ui.Paint()
      ..color = ui.Color(stroke.color)
      ..strokeWidth = stroke.thickness
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = ui.PaintingStyle.stroke;

    if (stroke.isEraser) {
      paint.blendMode = ui.BlendMode.clear;
    }

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points[0],
        stroke.thickness / 2,
        paint..style = ui.PaintingStyle.fill,
      );
      return;
    }

    final path = ui.Path()
      ..moveTo(stroke.points[0].dx, stroke.points[0].dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  static void _drawText(ui.Canvas canvas, CanvasTextElement element) {
    // Use system sans-serif — Google Fonts aren't available in background isolates
    final paragraphStyle = ui.ParagraphStyle(
      fontSize: element.fontSize,
      fontFamily: 'sans-serif',
    );
    final textStyle = ui.TextStyle(
      color: ui.Color(element.color),
      fontSize: element.fontSize,
      fontFamily: 'sans-serif',
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(element.text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 500));
    canvas.drawParagraph(paragraph, ui.Offset(element.x, element.y));
  }

  static void _drawSticker(ui.Canvas canvas, CanvasStickerElement sticker) {
    final paragraphStyle = ui.ParagraphStyle(fontSize: sticker.size);
    final textStyle = ui.TextStyle(fontSize: sticker.size);
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(sticker.emoji);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: sticker.size + 16));
    canvas.drawParagraph(
      paragraph,
      ui.Offset(sticker.x - sticker.size / 2, sticker.y - sticker.size / 2),
    );
  }
}
