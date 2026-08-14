import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/meeting_bootstrap.dart';

/// Wire-level event emitted by the Android Amazon Chime integration.
///
/// This value exists only inside infrastructure so channel maps never enter
/// the domain or presentation layers.
final class ChimePlatformEvent {
  const ChimePlatformEvent({
    required this.type,
    required this.occurredAt,
    required this.payload,
    this.generation,
  });

  final String type;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
  final int? generation;
}

/// Owns the Flutter side of the typed Android platform-channel contract.
///
/// Commands contain only fields required to construct an Amazon Chime
/// session. In particular, API keys and unused REST response fields never
/// cross this boundary.
final class ChimePlatformBridge {
  ChimePlatformBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  static const String methodChannelName =
      'com.example.chimemeeting/chime/methods';
  static const String eventChannelName =
      'com.example.chimemeeting/chime/events';
  static const String videoViewType = 'com.example.chimemeeting/chime/video';

  static const String startSessionMethod = 'startSession';
  static const String setMicrophoneEnabledMethod = 'setMicrophoneEnabled';
  static const String setCameraEnabledMethod = 'setCameraEnabled';
  static const String switchCameraMethod = 'switchCamera';
  static const String leaveSessionMethod = 'leaveSession';
  static const String disposeSessionMethod = 'disposeSession';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  /// Emits only structurally valid event envelopes.
  ///
  /// Malformed and unknown event types are discarded by this bridge and its
  /// mapper rather than terminating the long-lived session stream.
  Stream<ChimePlatformEvent> get events {
    if (kIsWeb) {
      return const Stream<ChimePlatformEvent>.empty();
    }

    return _eventChannel
        .receiveBroadcastStream()
        .asyncExpand<ChimePlatformEvent>((Object? message) {
          final event = _decodeEvent(message);
          return event == null
              ? const Stream<ChimePlatformEvent>.empty()
              : Stream<ChimePlatformEvent>.value(event);
        });
  }

  /// Requests native session construction and start with ephemeral credentials.
  Future<void> startSession(MeetingBootstrap bootstrap) {
    _ensureNativeRuntime();

    final placement = bootstrap.meeting.mediaPlacement;
    if (placement == null) {
      throw PlatformException(code: 'missing_media_configuration');
    }

    return _methodChannel
        .invokeMethod<void>(startSessionMethod, <String, Object?>{
          'meetingId': bootstrap.meeting.id.value,
          'attendeeId': bootstrap.attendee.attendeeId,
          'externalUserId': bootstrap.attendee.externalUserId,
          'joinToken': bootstrap.attendee.joinToken,
          'audioHostUrl': placement.audioHostUrl,
          'audioFallbackUrl': placement.audioFallbackUrl,
          'signalingUrl': placement.signalingUrl,
          'turnControlUrl': placement.turnControlUrl,
          'eventIngestionUrl': placement.eventIngestionUrl,
        });
  }

  /// Requests a confirmed microphone state from the active native session.
  Future<bool> setMicrophoneEnabled(bool enabled) async {
    _ensureNativeRuntime();

    final result = await _methodChannel.invokeMethod<bool>(
      setMicrophoneEnabledMethod,
      <String, Object>{'enabled': enabled},
    );
    if (result == null) {
      throw PlatformException(code: 'platform_bridge_failure');
    }
    return result;
  }

  /// Requests a camera state change from the active native session.
  ///
  /// The return value confirms command acceptance only. Actual camera state is
  /// reported asynchronously through Chime media events.
  Future<bool> setCameraEnabled(bool enabled) async {
    _ensureNativeRuntime();

    final result = await _methodChannel.invokeMethod<bool>(
      setCameraEnabledMethod,
      <String, Object>{'enabled': enabled},
    );
    if (result == null) {
      throw PlatformException(code: 'platform_bridge_failure');
    }
    return result;
  }

  /// Requests the native session to switch between available cameras.
  ///
  /// Returns true when the native bridge accepted the request; actual camera
  /// facing changes are reported by video-tile callbacks.
  Future<bool> switchCamera() async {
    _ensureNativeRuntime();

    final result = await _methodChannel.invokeMethod<bool>(switchCameraMethod);
    if (result == null) {
      throw PlatformException(code: 'platform_bridge_failure');
    }
    return result;
  }

  /// Stops and releases the active session while retaining bridge registration.
  Future<void> leaveSession() {
    _ensureNativeRuntime();
    return _methodChannel.invokeMethod<void>(leaveSessionMethod);
  }

  /// Releases the native session during application-scope disposal.
  Future<void> disposeSession() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    return _methodChannel.invokeMethod<void>(disposeSessionMethod);
  }

  /// Validates and normalizes one EventChannel wire message.
  void _ensureNativeRuntime() {
    if (kIsWeb) {
      throw PlatformException(code: 'unsupported_runtime');
    }
  }

  ChimePlatformEvent? _decodeEvent(Object? message) {
    if (message is! Map) {
      return null;
    }
    final type = message['type'];
    final timestampMs = message['timestampMs'];
    final rawPayload = message['payload'];
    final generation = message['generation'];
    if (type is! String || type.isEmpty || timestampMs is! num) {
      return null;
    }
    if (rawPayload != null && rawPayload is! Map) {
      return null;
    }
    if (generation != null && generation is! int) {
      return null;
    }

    return ChimePlatformEvent(
      type: type,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt()),
      payload: rawPayload == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawPayload),
      generation: generation as int?,
    );
  }
}
