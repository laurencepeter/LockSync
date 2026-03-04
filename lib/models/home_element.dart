import 'package:equatable/equatable.dart';
import '../core/constants/app_constants.dart';

/// The x/y position of an element on the canvas (device-independent pixels).
class ElementPosition extends Equatable {
  final double x;
  final double y;

  const ElementPosition({required this.x, required this.y});

  factory ElementPosition.fromJson(Map<String, dynamic> json) =>
      ElementPosition(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  ElementPosition translate(double dx, double dy) =>
      ElementPosition(x: x + dx, y: y + dy);

  @override
  List<Object?> get props => [x, y];
}

/// The width/height size of an element.
class ElementSize extends Equatable {
  final double width;
  final double height;

  const ElementSize({required this.width, required this.height});

  factory ElementSize.fromJson(Map<String, dynamic> json) => ElementSize(
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'width': width, 'height': height};

  ElementSize clampMin(double minW, double minH) => ElementSize(
        width: width < minW ? minW : width,
        height: height < minH ? minH : height,
      );

  @override
  List<Object?> get props => [width, height];
}

/// A single interactive element on the shared homescreen canvas.
///
/// Supported types: text_note, drawing_canvas, background, movable_widget.
class HomeElement extends Equatable {
  final String elementId;

  /// One of AppConstants.element* values.
  final String type;

  final ElementPosition position;
  final ElementSize size;

  /// Type-specific data stored as a flat JSON-compatible map:
  ///   text_note    → { 'text': String, 'color': int, 'fontSize': double }
  ///   drawing_canvas → { 'strokes': List<List<Map>> }
  ///   background   → { 'color': int, 'imageUrl': String? }
  ///   movable_widget → { 'widgetType': String, 'data': Map }
  final Map<String, dynamic> properties;

  /// Last modification timestamp used for LWW conflict resolution.
  final DateTime updatedAt;

  /// z-index on the canvas (higher = in front).
  final int zIndex;

  const HomeElement({
    required this.elementId,
    required this.type,
    required this.position,
    required this.size,
    required this.properties,
    required this.updatedAt,
    this.zIndex = 0,
  });

  factory HomeElement.create({
    required String elementId,
    required String type,
    required ElementPosition position,
    Map<String, dynamic>? properties,
    int zIndex = 0,
  }) =>
      HomeElement(
        elementId: elementId,
        type: type,
        position: position,
        size: const ElementSize(
          width: AppConstants.defaultElementWidth,
          height: AppConstants.defaultElementHeight,
        ),
        properties: properties ?? {},
        updatedAt: DateTime.now(),
        zIndex: zIndex,
      );

  factory HomeElement.fromJson(Map<String, dynamic> json) => HomeElement(
        elementId: json['elementId'] as String,
        type: json['type'] as String,
        position:
            ElementPosition.fromJson(json['position'] as Map<String, dynamic>),
        size: ElementSize.fromJson(json['size'] as Map<String, dynamic>),
        properties:
            Map<String, dynamic>.from(json['properties'] as Map? ?? {}),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'elementId': elementId,
        'type': type,
        'position': position.toJson(),
        'size': size.toJson(),
        'properties': properties,
        'updatedAt': updatedAt.toIso8601String(),
        'zIndex': zIndex,
      };

  HomeElement copyWith({
    String? elementId,
    String? type,
    ElementPosition? position,
    ElementSize? size,
    Map<String, dynamic>? properties,
    DateTime? updatedAt,
    int? zIndex,
  }) =>
      HomeElement(
        elementId: elementId ?? this.elementId,
        type: type ?? this.type,
        position: position ?? this.position,
        size: size ?? this.size,
        properties: properties ?? this.properties,
        updatedAt: updatedAt ?? this.updatedAt,
        zIndex: zIndex ?? this.zIndex,
      );

  HomeElement withUpdatedTimestamp() =>
      copyWith(updatedAt: DateTime.now());

  @override
  List<Object?> get props =>
      [elementId, type, position, size, properties, updatedAt, zIndex];
}
