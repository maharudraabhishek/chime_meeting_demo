import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/meeting_bootstrap.dart';
import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_media_event.dart';
import '../../domain/entities/meeting_result.dart';
import '../../domain/entities/meeting_status.dart';
import '../../domain/gateways/meeting_media_gateway.dart';
import 'chime_event_mapper.dart';
import 'chime_platform_bridge.dart';

/// Android Amazon Chime implementation of the domain media boundary.
///
/// This adapter owns the EventChannel subscription for its application
/// lifetime. Native callbacks are mapped immediately, so wire maps and platform
/// exceptions cannot escape into domain or presentation code.
final class ChimeMeetingMediaGateway implements MeetingMediaGateway {
  ChimeMeetingMediaGateway({
    required ChimePlatformBridge bridge,
    ChimeEventMapper mapper = const ChimeEventMapper(),
  }) : _bridge = bridge,
       _mapper = mapper {
    _platformSubscription = _bridge.events.listen(
      _onPlatformEvent,
      onError: _onPlatformStreamError,
    );
  }

  final ChimePlatformBridge _bridge;
  final ChimeEventMapper _mapper;
  final StreamController<MeetingMediaEvent> _eventController =
      StreamController<MeetingMediaEvent>.broadcast();
  late final StreamSubscription<ChimePlatformEvent> _platformSubscription;
  bool _disposed = false;

  @override
  Stream<MeetingMediaEvent> get events => _eventController.stream;

  /// Validates credentials/configuration before asking Android to start Chime.
  ///
  /// Success means the command was accepted and deliberately returns joining;
  /// only a later session-started callback proves media connectivity.
  @override
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap) async {
    if (_disposed) {
      return _error<MeetingStatus>(MeetingFailureType.platformBridge);
    }

    if (bootstrap.meeting.mediaPlacement == null) {
      return _error<MeetingStatus>(
        MeetingFailureType.missingMediaConfiguration,
      );
    }
    if (bootstrap.attendee.attendeeId.trim().isEmpty ||
        bootstrap.attendee.externalUserId.trim().isEmpty ||
        bootstrap.attendee.joinToken.trim().isEmpty) {
      return _error<MeetingStatus>(
        MeetingFailureType.invalidAttendeeCredentials,
      );
    }

    try {
      await _bridge.startSession(bootstrap);
      return const MeetingSuccess<MeetingStatus>(MeetingStatus.joining);
    } catch (error) {
      return MeetingError<MeetingStatus>(
        _mapPlatformError(error, MeetingFailureType.nativeInitialization),
      );
    }
  }

  @override
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled) async {
    if (_disposed) {
      return _error<bool>(MeetingFailureType.platformBridge);
    }
    try {
      final confirmed = await _bridge.setMicrophoneEnabled(enabled);
      return MeetingSuccess<bool>(confirmed);
    } catch (error) {
      return MeetingError<bool>(
        _mapPlatformError(error, MeetingFailureType.microphoneOperation),
      );
    }
  }

  @override
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled) async {
    if (_disposed) {
      return _error<bool>(MeetingFailureType.platformBridge);
    }
    try {
      final confirmed = await _bridge.setCameraEnabled(enabled);
      return MeetingSuccess<bool>(confirmed);
    } catch (error) {
      return MeetingError<bool>(
        _mapPlatformError(error, MeetingFailureType.cameraOperation),
      );
    }
  }

  @override
  Future<MeetingResult<bool>> switchCamera() async {
    if (_disposed) {
      return _error<bool>(MeetingFailureType.platformBridge);
    }
    try {
      final accepted = await _bridge.switchCamera();
      return MeetingSuccess<bool>(accepted);
    } catch (error) {
      return MeetingError<bool>(
        _mapPlatformError(error, MeetingFailureType.cameraOperation),
      );
    }
  }

  @override
  Future<MeetingResult<MeetingStatus>> leave() async {
    if (_disposed) {
      return _error<MeetingStatus>(MeetingFailureType.platformBridge);
    }
    try {
      await _bridge.leaveSession();
      return const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
    } catch (error) {
      return MeetingError<MeetingStatus>(
        _mapPlatformError(error, MeetingFailureType.sessionUnavailable),
      );
    }
  }

  /// Cancels the native event subscription and requests idempotent cleanup.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      await _bridge.disposeSession();
    } on Object {
      // Disposal is best effort; resources below this boundary are still
      // detached so application teardown cannot retain Dart subscriptions.
    }
    await _platformSubscription.cancel();
    await _eventController.close();
  }

  /// Maps one validated native event into the domain event stream.
  void _onPlatformEvent(ChimePlatformEvent platformEvent) {
    final event = _mapper.map(platformEvent);
    if (!_disposed && event != null) {
      _eventController.add(event);
    }
  }

  /// Converts EventChannel failures into one safe terminal media event.
  void _onPlatformStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _eventController.add(
      MeetingMediaEvent(
        type: MeetingMediaEventType.sessionError,
        occurredAt: DateTime.now(),
        failure: _mapPlatformError(error, MeetingFailureType.platformBridge),
      ),
    );
  }

  /// Converts platform exceptions into stable domain failure categories.
  MeetingFailure _mapPlatformError(Object error, MeetingFailureType fallback) {
    if (error is PlatformException) {
      return MeetingFailure(
        ChimeEventMapper.failureTypeForPlatformCode(
          error.code,
          fallback: fallback,
        ),
      );
    }
    if (error is MissingPluginException) {
      return const MeetingFailure(MeetingFailureType.platformBridge);
    }
    return MeetingFailure(fallback);
  }

  /// Creates a typed media error without exposing platform exception details.
  MeetingError<T> _error<T>(MeetingFailureType type) {
    return MeetingError<T>(MeetingFailure(type));
  }
}
