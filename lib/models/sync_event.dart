import 'package:equatable/equatable.dart';

/// An immutable delta event broadcast between peers.
///
/// Only deltas are sent over the wire — never full layout snapshots (except
/// for late-join). Conflict resolution uses [timestamp] LWW.
class SyncEvent extends Equatable {
  final String eventId;

  /// The element this event targets. Empty for background_change events.
  final String elementId;

  /// One of AppConstants.change* values.
  final String changeType;

  /// Event-specific data:
  ///   add    → { 'element': HomeElement.toJson() }
  ///   update → { 'element': HomeElement.toJson() }
  ///   delete → {}
  ///   background_change → { 'color': int }
  final Map<String, dynamic> payload;

  /// When this change was made on the originating device.
  final DateTime timestamp;

  /// DeviceId of the device that created this event.
  final String originatingDevice;

  /// Whether this event has been acknowledged/forwarded to all peers.
  /// Locally-queued unsynced events have synced = false.
  final bool synced;

  const SyncEvent({
    required this.eventId,
    required this.elementId,
    required this.changeType,
    required this.payload,
    required this.timestamp,
    required this.originatingDevice,
    this.synced = false,
  });

  factory SyncEvent.fromJson(Map<String, dynamic> json) => SyncEvent(
        eventId: json['eventId'] as String,
        elementId: json['elementId'] as String? ?? '',
        changeType: json['changeType'] as String,
        payload:
            Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
        timestamp: DateTime.parse(json['timestamp'] as String),
        originatingDevice: json['originatingDevice'] as String,
        synced: json['synced'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'elementId': elementId,
        'changeType': changeType,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'originatingDevice': originatingDevice,
        'synced': synced,
      };

  SyncEvent markSynced() => SyncEvent(
        eventId: eventId,
        elementId: elementId,
        changeType: changeType,
        payload: payload,
        timestamp: timestamp,
        originatingDevice: originatingDevice,
        synced: true,
      );

  @override
  List<Object?> get props =>
      [eventId, elementId, changeType, payload, timestamp, originatingDevice];
}
