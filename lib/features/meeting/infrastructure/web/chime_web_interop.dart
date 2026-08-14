// ignore_for_file: non_constant_identifier_names

import 'dart:js_interop';

import 'chime_web_bridge_client.dart';

@JS('chimeWebBridge')
external _ChimeWebBridgeJs? get _chimeWebBridge;

/// Typed access to the single browser-global application bridge.
@JS()
extension type _ChimeWebBridgeJs._(JSObject _) implements JSObject {
  external bool isSupported();
  external void setEventHandler(JSFunction? handler);
  external JSPromise<JSAny?> startSession(_StartSessionRequestJs request);
  external JSPromise<JSAny?> stopSession(int generation);
  external JSPromise<JSBoolean> muteLocalAudio(int generation);
  external JSPromise<JSBoolean> unmuteLocalAudio(int generation);
  external JSPromise<JSAny?> startLocalVideo(int generation);
  external JSPromise<JSAny?> stopLocalVideo(int generation);
  external JSPromise<JSBoolean> switchCamera(int generation);
  external void attachLocalVideoElement(int generation, String elementId);
  external void attachRemoteVideoElement(int generation, String elementId);
  external void detachVideoElement(int generation, String role);
  external JSPromise<JSAny?> dispose();
}

@JS()
extension type _StartSessionRequestJs._(JSObject _) implements JSObject {
  external factory _StartSessionRequestJs({
    required int generation,
    required _MeetingJs meeting,
    required _AttendeeJs attendee,
    required bool debugLogging,
  });
}

@JS()
extension type _MeetingJs._(JSObject _) implements JSObject {
  external factory _MeetingJs({
    required String MeetingId,
    required _MediaPlacementJs MediaPlacement,
  });
}

@JS()
extension type _MediaPlacementJs._(JSObject _) implements JSObject {
  external factory _MediaPlacementJs({
    required String AudioHostUrl,
    required String AudioFallbackUrl,
    required String SignalingUrl,
    required String TurnControlUrl,
    String? EventIngestionUrl,
  });
}

@JS()
extension type _AttendeeJs._(JSObject _) implements JSObject {
  external factory _AttendeeJs({
    required String AttendeeId,
    required String ExternalUserId,
    required String JoinToken,
  });
}

@JS()
extension type _BridgeEventJs._(JSObject _) implements JSObject {
  external String? get type;
  external JSNumber? get generation;
  external String? get attendeeId;
  external JSNumber? get volume;
  external String? get failureCode;
}

/// Converts typed JavaScript calls and promises into a testable Dart bridge.
final class InteropChimeWebBridgeClient implements ChimeWebBridgeClient {
  JSFunction? _eventHandler;

  _ChimeWebBridgeJs? get _bridge => _chimeWebBridge;

  @override
  bool get isAvailable => _bridge != null;

  @override
  bool get isSupported {
    final bridge = _bridge;
    return bridge != null && bridge.isSupported();
  }

  @override
  void setEventHandler(void Function(WebBridgeEventData event)? handler) {
    final bridge = _bridge;
    if (bridge == null) {
      _eventHandler = null;
      return;
    }
    if (handler == null) {
      _eventHandler = null;
      bridge.setEventHandler(null);
      return;
    }
    void decode(_BridgeEventJs event) {
      try {
        final type = event.type;
        final generationValue = event.generation?.toDartDouble;
        if (type == null ||
            generationValue == null ||
            !generationValue.isFinite ||
            generationValue != generationValue.truncateToDouble()) {
          return;
        }
        handler(
          WebBridgeEventData(
            type: type,
            generation: generationValue.toInt(),
            attendeeId: event.attendeeId,
            volume: event.volume?.toDartDouble,
            failureCode: event.failureCode,
          ),
        );
      } on Object {
        // No malformed or late external callback may throw into Chime realtime.
      }
    }

    _eventHandler = decode.toJS;
    bridge.setEventHandler(_eventHandler);
  }

  @override
  Future<void> startSession(WebStartSessionRequest request) async {
    final bridge = _requireBridge();
    final bootstrap = request.bootstrap;
    final placement = bootstrap.meeting.mediaPlacement!;
    final mediaPlacement = _MediaPlacementJs(
      AudioHostUrl: placement.audioHostUrl,
      AudioFallbackUrl: placement.audioFallbackUrl,
      SignalingUrl: placement.signalingUrl,
      TurnControlUrl: placement.turnControlUrl,
      EventIngestionUrl: placement.eventIngestionUrl,
    );
    final meeting = _MeetingJs(
      MeetingId: bootstrap.meeting.id.value,
      MediaPlacement: mediaPlacement,
    );
    final attendee = _AttendeeJs(
      AttendeeId: bootstrap.attendee.attendeeId,
      ExternalUserId: bootstrap.attendee.externalUserId,
      JoinToken: bootstrap.attendee.joinToken,
    );
    await bridge
        .startSession(
          _StartSessionRequestJs(
            generation: request.generation,
            meeting: meeting,
            attendee: attendee,
            debugLogging: request.debugLogging,
          ),
        )
        .toDart;
  }

  @override
  Future<void> stopSession(int generation) async {
    await _requireBridge().stopSession(generation).toDart;
  }

  @override
  Future<bool> muteLocalAudio(int generation) async {
    return (await _requireBridge().muteLocalAudio(generation).toDart).toDart;
  }

  @override
  Future<bool> unmuteLocalAudio(int generation) async {
    return (await _requireBridge().unmuteLocalAudio(generation).toDart).toDart;
  }

  @override
  Future<void> startLocalVideo(int generation) async {
    await _requireBridge().startLocalVideo(generation).toDart;
  }

  @override
  Future<void> stopLocalVideo(int generation) async {
    await _requireBridge().stopLocalVideo(generation).toDart;
  }

  @override
  Future<bool> switchCamera(int generation) async {
    return (await _requireBridge().switchCamera(generation).toDart).toDart;
  }

  @override
  void attachLocalVideoElement(int generation, String elementId) {
    _requireBridge().attachLocalVideoElement(generation, elementId);
  }

  @override
  void attachRemoteVideoElement(int generation, String elementId) {
    _requireBridge().attachRemoteVideoElement(generation, elementId);
  }

  @override
  void detachVideoElement(int generation, String role) {
    _requireBridge().detachVideoElement(generation, role);
  }

  @override
  Future<void> dispose() async {
    final bridge = _bridge;
    _eventHandler = null;
    if (bridge != null) {
      bridge.setEventHandler(null);
      await bridge.dispose().toDart;
    }
  }

  _ChimeWebBridgeJs _requireBridge() {
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError('Browser meeting bridge unavailable.');
    }
    return bridge;
  }
}
