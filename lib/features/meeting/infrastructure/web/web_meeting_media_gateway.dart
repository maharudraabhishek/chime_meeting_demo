import 'dart:async';

import '../../domain/entities/meeting_bootstrap.dart';
import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_media_event.dart';
import '../../domain/entities/meeting_result.dart';
import '../../domain/entities/meeting_status.dart';
import '../../domain/entities/meeting_video_role.dart';
import '../../domain/gateways/meeting_media_gateway.dart';
import '../../domain/gateways/meeting_video_surface_coordinator.dart';
import 'chime_web_bridge_client.dart';
import 'web_bridge_event_decoder.dart';

/// Amazon Chime JavaScript adapter behind the shared media domain boundary.
///
/// The bridge owns WebRTC and DOM binding. This adapter owns session generation,
/// typed event mapping, and the in-memory relationship between Flutter video
/// surfaces and the current browser session.
final class WebMeetingMediaGateway
    implements MeetingMediaGateway, MeetingVideoSurfaceCoordinator {
  WebMeetingMediaGateway({
    required ChimeWebBridgeClient bridge,
    WebBridgeEventDecoder decoder = const WebBridgeEventDecoder(),
  }) : _bridge = bridge,
       _decoder = decoder {
    _bridge.setEventHandler(_onBridgeEvent);
  }

  final ChimeWebBridgeClient _bridge;
  final WebBridgeEventDecoder _decoder;
  final StreamController<MeetingMediaEvent> _events =
      StreamController<MeetingMediaEvent>.broadcast();
  final Map<MeetingVideoRole, String> _elementIds =
      <MeetingVideoRole, String>{};

  int _lastGeneration = 0;
  int? _activeGeneration;
  bool _disposed = false;

  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  @override
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap) async {
    if (_disposed || !_bridge.isAvailable) {
      return _error<MeetingStatus>(MeetingFailureType.bridgeUnavailable);
    }
    if (!_bridge.isSupported) {
      return _error<MeetingStatus>(MeetingFailureType.unsupportedRuntime);
    }
    final validationFailure = _validate(bootstrap);
    if (validationFailure != null) {
      return MeetingError<MeetingStatus>(validationFailure);
    }

    final previousGeneration = _activeGeneration;
    _activeGeneration = null;
    if (previousGeneration != null) {
      try {
        await _bridge.stopSession(previousGeneration);
      } on Object {
        // Replacement continues because the bridge also performs idempotent
        // old-session cleanup before constructing the new Chime session.
      }
    }

    final generation = ++_lastGeneration;
    _activeGeneration = generation;
    try {
      await _bridge.startSession(
        WebStartSessionRequest(generation: generation, bootstrap: bootstrap),
      );
      if (_activeGeneration != generation || _disposed) {
        return _error<MeetingStatus>(MeetingFailureType.sessionUnavailable);
      }
      _reattachElements(generation);
      // Chime's sessionStarted callback, not this accepted command, is the
      // connected-state authority.
      return const MeetingSuccess<MeetingStatus>(MeetingStatus.joining);
    } on Object {
      if (_activeGeneration == generation) {
        _activeGeneration = null;
      }
      try {
        await _bridge.stopSession(generation);
      } on Object {
        // Preserve the original safe start category while cleanup continues.
      }
      return _error<MeetingStatus>(MeetingFailureType.meetingStart);
    }
  }

  @override
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled) async {
    final generation = _activeGeneration;
    if (_disposed || generation == null) {
      return _error<bool>(MeetingFailureType.sessionUnavailable);
    }
    try {
      final confirmed = enabled
          ? await _bridge.unmuteLocalAudio(generation)
          : await _bridge.muteLocalAudio(generation);
      return MeetingSuccess<bool>(confirmed);
    } on Object {
      return _error<bool>(MeetingFailureType.microphoneOperation);
    }
  }

  @override
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled) async {
    final generation = _activeGeneration;
    if (_disposed || generation == null) {
      return _error<bool>(MeetingFailureType.sessionUnavailable);
    }
    try {
      if (enabled) {
        await _bridge.startLocalVideo(generation);
      } else {
        await _bridge.stopLocalVideo(generation);
      }
      return MeetingSuccess<bool>(enabled);
    } on Object {
      return _error<bool>(MeetingFailureType.cameraOperation);
    }
  }

  @override
  Future<MeetingResult<bool>> switchCamera() async {
    final generation = _activeGeneration;
    if (_disposed || generation == null) {
      return _error<bool>(MeetingFailureType.sessionUnavailable);
    }
    try {
      return MeetingSuccess<bool>(await _bridge.switchCamera(generation));
    } on Object {
      return _error<bool>(MeetingFailureType.cameraOperation);
    }
  }

  @override
  Future<MeetingResult<MeetingStatus>> leave() async {
    if (_disposed) {
      return _error<MeetingStatus>(MeetingFailureType.bridgeUnavailable);
    }
    final generation = _activeGeneration;
    _activeGeneration = null;
    if (generation == null) {
      return const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
    }
    try {
      await _bridge.stopSession(generation);
      return const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
    } on Object {
      return _error<MeetingStatus>(MeetingFailureType.sessionUnavailable);
    }
  }

  @override
  Future<void> attachVideoSurface(
    MeetingVideoRole role,
    String elementId,
  ) async {
    if (_disposed || elementId.trim().isEmpty) {
      return;
    }
    _elementIds[role] = elementId;
    final generation = _activeGeneration;
    if (generation == null) {
      return;
    }
    _attach(role, generation, elementId);
  }

  @override
  Future<void> detachVideoSurface(
    MeetingVideoRole role,
    String elementId,
  ) async {
    // Disposal of a replaced HtmlElementView must not detach its newer surface.
    if (_disposed || _elementIds[role] != elementId) {
      return;
    }
    _elementIds.remove(role);
    final generation = _activeGeneration;
    if (generation != null) {
      try {
        _bridge.detachVideoElement(generation, role.name);
      } on Object {
        // Surface disposal remains best effort during route/session teardown.
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final generation = _activeGeneration;
    _activeGeneration = null;
    _bridge.setEventHandler(null);
    if (generation != null) {
      try {
        await _bridge.stopSession(generation);
      } on Object {
        // Continue releasing the remaining bridge and Dart-owned resources.
      }
    }
    try {
      await _bridge.dispose();
    } on Object {
      // The Dart stream must still close if JavaScript cleanup partially fails.
    }
    _elementIds.clear();
    await _events.close();
  }

  void _onBridgeEvent(WebBridgeEventData data) {
    // Browser promises and Chime observers can complete after leave/rejoin.
    // Ignore callbacks from the replaced session before they reach BLoC.
    if (_disposed || data.generation != _activeGeneration) {
      return;
    }
    final event = _decoder.decode(data);
    if (event != null && !_events.isClosed) {
      _events.add(event);
    }
  }

  void _reattachElements(int generation) {
    for (final entry in _elementIds.entries) {
      _attach(entry.key, generation, entry.value);
    }
  }

  void _attach(MeetingVideoRole role, int generation, String elementId) {
    try {
      switch (role) {
        case MeetingVideoRole.local:
          _bridge.attachLocalVideoElement(generation, elementId);
        case MeetingVideoRole.remote:
          _bridge.attachRemoteVideoElement(generation, elementId);
      }
    } on Object {
      // Tile/element binding is retried by later view or tile callbacks. A DOM
      // attachment race must not terminate an otherwise healthy meeting.
    }
  }

  MeetingFailure? _validate(MeetingBootstrap bootstrap) {
    final placement = bootstrap.meeting.mediaPlacement;
    if (placement == null ||
        placement.audioHostUrl.trim().isEmpty ||
        placement.audioFallbackUrl.trim().isEmpty ||
        placement.signalingUrl.trim().isEmpty ||
        placement.turnControlUrl.trim().isEmpty) {
      return const MeetingFailure(MeetingFailureType.missingMediaConfiguration);
    }
    if (bootstrap.meeting.id.value.trim().isEmpty ||
        bootstrap.attendee.attendeeId.trim().isEmpty ||
        bootstrap.attendee.externalUserId.trim().isEmpty ||
        bootstrap.attendee.joinToken.trim().isEmpty) {
      return const MeetingFailure(
        MeetingFailureType.invalidAttendeeCredentials,
      );
    }
    return null;
  }

  MeetingError<T> _error<T>(MeetingFailureType type) {
    return MeetingError<T>(MeetingFailure(type));
  }
}
