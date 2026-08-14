import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_event_mapper.dart';
import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_platform_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = ChimeEventMapper();
  final occurredAt = DateTime.utc(2026, 8, 11, 12);

  test('maps every Stage 1 native event to its domain equivalent', () {
    const expectedTypes = <String, MeetingMediaEventType>{
      'sessionStarted': MeetingMediaEventType.sessionStarted,
      'sessionStopped': MeetingMediaEventType.sessionStopped,
      'participantJoined': MeetingMediaEventType.participantJoined,
      'participantLeft': MeetingMediaEventType.participantLeft,
      'localVideoAvailable': MeetingMediaEventType.localVideoAvailable,
      'localVideoRemoved': MeetingMediaEventType.localVideoRemoved,
      'remoteVideoAvailable': MeetingMediaEventType.remoteVideoAvailable,
      'remoteVideoRemoved': MeetingMediaEventType.remoteVideoRemoved,
      'microphoneEnabled': MeetingMediaEventType.microphoneEnabled,
      'microphoneDisabled': MeetingMediaEventType.microphoneDisabled,
      'cameraEnabled': MeetingMediaEventType.cameraEnabled,
      'cameraDisabled': MeetingMediaEventType.cameraDisabled,
      'sessionError': MeetingMediaEventType.sessionError,
    };

    for (final entry in expectedTypes.entries) {
      final mapped = mapper.map(
        ChimePlatformEvent(
          type: entry.key,
          occurredAt: occurredAt,
          payload: entry.key == 'sessionError'
              ? const <String, Object?>{'code': 'meeting_start_failure'}
              : const <String, Object?>{},
        ),
      );

      expect(mapped?.type, entry.value, reason: entry.key);
      expect(mapped?.occurredAt, occurredAt, reason: entry.key);
      expect(
        mapped?.failure,
        entry.key == 'sessionError'
            ? const MeetingFailure(MeetingFailureType.meetingStart)
            : isNull,
        reason: entry.key,
      );
    }
  });

  test('ignores unknown native event types', () {
    final mapped = mapper.map(
      ChimePlatformEvent(
        type: 'futureSdkEvent',
        occurredAt: occurredAt,
        payload: const <String, Object?>{},
      ),
    );

    expect(mapped, isNull);
  });

  test('maps safe platform codes and falls back without leaking details', () {
    expect(
      ChimeEventMapper.failureTypeForPlatformCode('permission_unavailable'),
      MeetingFailureType.permissionUnavailable,
    );
    expect(
      ChimeEventMapper.failureTypeForPlatformCode('unsupported_runtime'),
      MeetingFailureType.unsupportedRuntime,
    );
    expect(
      ChimeEventMapper.failureTypeForPlatformCode(
        'unknown-native-code',
        fallback: MeetingFailureType.cameraOperation,
      ),
      MeetingFailureType.cameraOperation,
    );
  });
}
