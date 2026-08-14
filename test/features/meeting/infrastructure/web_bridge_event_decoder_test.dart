import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/infrastructure/web/chime_web_bridge_client.dart';
import 'package:chime_meeting/features/meeting/infrastructure/web/web_bridge_event_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const decoder = WebBridgeEventDecoder();
  final occurredAt = DateTime.utc(2026, 8, 14);

  test('maps known minimal bridge event fields', () {
    final event = decoder.decode(
      const WebBridgeEventData(
        type: 'volumeLevel',
        generation: 7,
        attendeeId: 'attendee-a',
        volume: 0.75,
      ),
      occurredAt: occurredAt,
    );

    expect(event?.type, MeetingMediaEventType.volumeLevel);
    expect(event?.generation, 7);
    expect(event?.attendeeId, 'attendee-a');
    expect(event?.volume, 0.75);
    expect(event?.occurredAt, occurredAt);
  });

  test('rejects unknown, malformed, and invalid numeric data', () {
    expect(
      decoder.decode(const WebBridgeEventData(type: 'unknown', generation: 1)),
      isNull,
    );
    expect(
      decoder.decode(
        const WebBridgeEventData(type: 'sessionStarted', generation: 0),
      ),
      isNull,
    );

    final event = decoder.decode(
      const WebBridgeEventData(type: 'volumeLevel', generation: 1, volume: 2),
    );
    expect(event?.volume, isNull);
  });

  test(
    'maps recoverable browser media failures without making them terminal',
    () {
      final event = decoder.decode(
        const WebBridgeEventData(
          type: 'cameraDisabled',
          generation: 2,
          failureCode: 'camera_permission_denied',
        ),
      );

      expect(event?.type, MeetingMediaEventType.cameraDisabled);
      expect(event?.failure?.type, MeetingFailureType.cameraPermissionDenied);
    },
  );

  test('maps unclassified session errors to a safe unexpected failure', () {
    final event = decoder.decode(
      const WebBridgeEventData(type: 'sessionError', generation: 2),
    );

    expect(event?.failure?.type, MeetingFailureType.unexpected);
  });
}
