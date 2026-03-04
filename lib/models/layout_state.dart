import 'package:equatable/equatable.dart';
import 'home_element.dart';

/// The complete, authoritative layout of a shared homescreen.
///
/// Stored locally on every device as JSON. Each mutation increments [version].
/// The [elements] list is ordered by [HomeElement.zIndex] ascending.
class LayoutState extends Equatable {
  final String layoutId;
  final int version;
  final DateTime updatedTimestamp;
  final List<HomeElement> elements;

  /// Background color as ARGB int (e.g. 0xFF1A1A2E). Null = system default.
  final int? backgroundColor;

  const LayoutState({
    required this.layoutId,
    required this.version,
    required this.updatedTimestamp,
    required this.elements,
    this.backgroundColor,
  });

  /// Creates a blank layout for a new space.
  factory LayoutState.empty(String layoutId) => LayoutState(
        layoutId: layoutId,
        version: 0,
        updatedTimestamp: DateTime.now(),
        elements: const [],
      );

  factory LayoutState.fromJson(Map<String, dynamic> json) => LayoutState(
        layoutId: json['layoutId'] as String,
        version: (json['version'] as num).toInt(),
        updatedTimestamp: DateTime.parse(json['updatedTimestamp'] as String),
        elements: (json['elements'] as List<dynamic>? ?? [])
            .map((e) => HomeElement.fromJson(e as Map<String, dynamic>))
            .toList(),
        backgroundColor: json['backgroundColor'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'layoutId': layoutId,
        'version': version,
        'updatedTimestamp': updatedTimestamp.toIso8601String(),
        'elements': elements.map((e) => e.toJson()).toList(),
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
      };

  // ── Mutation helpers ──────────────────────────────────────────────

  LayoutState _bump() => copyWith(
        version: version + 1,
        updatedTimestamp: DateTime.now(),
      );

  LayoutState withAddedElement(HomeElement element) {
    final updated = [...elements, element]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return _bump().copyWith(elements: updated);
  }

  LayoutState withUpdatedElement(HomeElement element) {
    final updated = elements.map((e) {
      if (e.elementId != element.elementId) return e;
      // LWW: keep the newer version.
      return element.updatedAt.isAfter(e.updatedAt) ? element : e;
    }).toList();
    return _bump().copyWith(elements: updated);
  }

  LayoutState withRemovedElement(String elementId) {
    final updated = elements.where((e) => e.elementId != elementId).toList();
    return _bump().copyWith(elements: updated);
  }

  LayoutState withBackgroundColor(int color) =>
      _bump().copyWith(backgroundColor: color);

  HomeElement? findElement(String elementId) {
    try {
      return elements.firstWhere((e) => e.elementId == elementId);
    } catch (_) {
      return null;
    }
  }

  LayoutState copyWith({
    String? layoutId,
    int? version,
    DateTime? updatedTimestamp,
    List<HomeElement>? elements,
    int? backgroundColor,
  }) =>
      LayoutState(
        layoutId: layoutId ?? this.layoutId,
        version: version ?? this.version,
        updatedTimestamp: updatedTimestamp ?? this.updatedTimestamp,
        elements: elements ?? this.elements,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );

  @override
  List<Object?> get props =>
      [layoutId, version, updatedTimestamp, elements, backgroundColor];
}
