import 'dart:ui';

// ─── Stroke (drawing) ────────────────────────────────────────────────
class CanvasStroke {
  final List<Offset> points;
  final int color;
  final double thickness;
  final bool isEraser;

  CanvasStroke({
    required this.points,
    required this.color,
    required this.thickness,
    this.isEraser = false,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => [p.dx, p.dy]).toList(),
        'color': color,
        'thickness': thickness,
        'isEraser': isEraser,
      };

  factory CanvasStroke.fromJson(Map<String, dynamic> json) {
    return CanvasStroke(
      points: (json['points'] as List)
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      color: json['color'] as int,
      thickness: (json['thickness'] as num).toDouble(),
      isEraser: json['isEraser'] as bool? ?? false,
    );
  }
}

// ─── Text element ────────────────────────────────────────────────────
class CanvasTextElement {
  String text;
  double x;
  double y;
  int color;
  double fontSize;
  String fontFamily;
  String addedBy;

  CanvasTextElement({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    this.fontSize = 18,
    this.fontFamily = 'Inter',
    this.addedBy = '',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'color': color,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'addedBy': addedBy,
      };

  factory CanvasTextElement.fromJson(Map<String, dynamic> json) {
    return CanvasTextElement(
      text: json['text'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      color: json['color'] as int,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      fontFamily: json['fontFamily'] as String? ?? 'Inter',
      addedBy: json['addedBy'] as String? ?? '',
    );
  }
}

// ─── Image element ───────────────────────────────────────────────────
class CanvasImageElement {
  String imageId; // local file path or asset path
  double x;
  double y;
  double width;
  double height;
  double rotation;

  CanvasImageElement({
    required this.imageId,
    required this.x,
    required this.y,
    this.width = 150,
    this.height = 150,
    this.rotation = 0,
  });

  Map<String, dynamic> toJson() => {
        'imageId': imageId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotation': rotation,
      };

  factory CanvasImageElement.fromJson(Map<String, dynamic> json) {
    return CanvasImageElement(
      imageId: json['imageId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 150,
      height: (json['height'] as num?)?.toDouble() ?? 150,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ─── Sticker element ─────────────────────────────────────────────────
class CanvasStickerElement {
  String emoji; // emoji character or asset name
  double x;
  double y;
  double size;

  CanvasStickerElement({
    required this.emoji,
    required this.x,
    required this.y,
    this.size = 48,
  });

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        'x': x,
        'y': y,
        'size': size,
      };

  factory CanvasStickerElement.fromJson(Map<String, dynamic> json) {
    return CanvasStickerElement(
      emoji: json['emoji'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      size: (json['size'] as num?)?.toDouble() ?? 48,
    );
  }
}

// ─── Full canvas state ──────────────────────────────────────────────
class CanvasState {
  List<CanvasStroke> strokes;
  List<CanvasTextElement> textElements;
  List<CanvasStickerElement> stickers;
  String? backgroundImagePath;
  String theme;

  CanvasState({
    List<CanvasStroke>? strokes,
    List<CanvasTextElement>? textElements,
    List<CanvasStickerElement>? stickers,
    this.backgroundImagePath,
    this.theme = 'default',
  })  : strokes = strokes ?? [],
        textElements = textElements ?? [],
        stickers = stickers ?? [];

  Map<String, dynamic> toJson() => {
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'textElements': textElements.map((t) => t.toJson()).toList(),
        'stickers': stickers.map((s) => s.toJson()).toList(),
        'backgroundImagePath': backgroundImagePath,
        'theme': theme,
      };

  factory CanvasState.fromJson(Map<String, dynamic> json) {
    return CanvasState(
      strokes: (json['strokes'] as List?)
              ?.map((s) => CanvasStroke.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      textElements: (json['textElements'] as List?)
              ?.map((t) =>
                  CanvasTextElement.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      stickers: (json['stickers'] as List?)
              ?.map((s) =>
                  CanvasStickerElement.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      backgroundImagePath: json['backgroundImagePath'] as String?,
      theme: json['theme'] as String? ?? 'default',
    );
  }
}
