import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_diagnostics.dart';
import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_id.dart';
import '../../domain/entities/meeting_log_entry.dart';
import '../../domain/entities/meeting_media_event.dart';
import '../../domain/entities/meeting_media_state.dart';
import '../../domain/entities/meeting_result.dart';
import '../../domain/entities/meeting_status.dart';
import '../../domain/gateways/connectivity_gateway.dart';
import '../../domain/gateways/meeting_media_gateway.dart';
import '../../domain/gateways/meeting_permission_gateway.dart';
import '../../domain/gateways/meeting_video_surface_coordinator.dart';
import '../../domain/usecases/create_meeting.dart';
import '../../domain/usecases/join_meeting.dart';
import 'meeting_event.dart';
import 'meeting_state.dart';

const Duration _defaultReconnectTimeout = Duration(seconds: 25);

/// Coordinates presentation state with REST and native media outcomes.
///
/// The BLoC never owns credentials or SDK objects. It listens to the shared
/// media gateway before a start can be requested, ensuring the Chime
/// session-start callback—not REST success—is the connected-state authority.
final class MeetingBloc extends Bloc<MeetingEvent, MeetingState> {
  MeetingBloc({
    required CreateMeeting createMeeting,
    required JoinMeeting joinMeeting,
    required MeetingMediaGateway mediaGateway,
    required MeetingPermissionGateway permissionGateway,
    required ConnectivityGateway connectivityGateway,
    MeetingVideoSurfaceCoordinator? videoSurfaceCoordinator,
    Duration sessionStartTimeout = const Duration(seconds: 20),
    Duration reconnectTimeout = _defaultReconnectTimeout,
  }) : _createMeeting = createMeeting,
       _joinMeeting = joinMeeting,
       _mediaGateway = mediaGateway,
       _permissionGateway = permissionGateway,
       _connectivityGateway = connectivityGateway,
       _videoSurfaceCoordinator =
           videoSurfaceCoordinator ?? _coordinatorFrom(mediaGateway),
       _sessionStartTimeout = sessionStartTimeout,
       _reconnectTimeout = reconnectTimeout,
       super(MeetingState()) {
    on<MeetingCreateRequested>(_onCreateRequested);
    on<MeetingJoinRequested>(_onJoinRequested);
    on<MeetingInitialPermissionsRequested>(_onInitialPermissionsRequested);
    on<MeetingRetryPermissionsRequested>(_onRetryPermissionsRequested);
    on<MeetingOpenSettingsRequested>(_onOpenSettingsRequested);
    on<MeetingMicrophoneChanged>(_onMicrophoneChanged);
    on<MeetingCameraChanged>(_onCameraChanged);
    on<MeetingSwitchCameraRequested>(_onSwitchCameraRequested);
    on<MeetingLeaveRequested>(_onLeaveRequested);
    on<MeetingLifecycleChanged>(_onLifecycleChanged);
    on<MeetingSessionStartTimedOut>(_onSessionStartTimedOut);
    on<MeetingReconnectTimedOut>(_onReconnectTimedOut);
    on<MeetingMediaEventReceived>(_onMediaEventReceived);
    on<MeetingVideoSurfaceAttached>(_onVideoSurfaceAttached);
    on<MeetingVideoSurfaceDetached>(_onVideoSurfaceDetached);

    _mediaSubscription = _mediaGateway.events.listen(
      (event) {
        if (!isClosed) {
          add(MeetingMediaEventReceived(event));
        }
      },
      onError: (Object _, StackTrace _) {
        if (!isClosed) {
          add(
            MeetingMediaEventReceived(
              MeetingMediaEvent(
                type: MeetingMediaEventType.sessionError,
                occurredAt: DateTime.now(),
                failure: const MeetingFailure(
                  MeetingFailureType.platformBridge,
                ),
              ),
            ),
          );
        }
      },
    );
  }

  final CreateMeeting _createMeeting;
  final JoinMeeting _joinMeeting;
  final MeetingMediaGateway _mediaGateway;
  final MeetingPermissionGateway _permissionGateway;
  final ConnectivityGateway _connectivityGateway;
  final MeetingVideoSurfaceCoordinator? _videoSurfaceCoordinator;
  final Duration _sessionStartTimeout;
  final Duration _reconnectTimeout;
  late final StreamSubscription<MeetingMediaEvent> _mediaSubscription;

  Timer? _sessionStartTimer;
  Timer? _reconnectWatchdogTimer;
  bool _lifecycleBackgrounded = false;
  bool _restoreCameraOnResume = false;

  bool _bootstrapInFlight = false;
  bool _leaveInFlight = false;
  bool _leaveRequestedDuringBootstrap = false;

  /// Active generation for the current session. Null until first sessionStarted.
  int? _activeSessionGeneration;

  /// Dart-owned identity protects async work even before native generation exists.
  int _lastSessionIdentity = 0;
  int? _activeSessionIdentity;

  /// Monotonic reconnect episode identity rejects stale watchdog callbacks.
  int _lastReconnectEpisode = 0;
  int? _activeReconnectEpisode;

  /// Number of reconnect attempts observed for the current meeting session.
  int _reconnectAttempts = 0;

  /// Keeps the last N meeting events in memory to avoid unbounded growth.
  static const int _maxEventLogEntries = 50;

  /// Starts the create workflow through the shared bootstrap pipeline.
  Future<void> _onCreateRequested(
    MeetingCreateRequested event,
    Emitter<MeetingState> emit,
  ) async {
    await _runBootstrap(
      operation: _createMeeting.call,
      initialStatusMessage: 'Creating meeting…',
      emit: emit,
    );
  }

  /// Starts the join workflow using the user-provided meeting identifier.
  Future<void> _onJoinRequested(
    MeetingJoinRequested event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      MeetingId.fromUserInput(event.meetingIdInput);
    } on FormatException {
      emit(
        state.copyWith(
          status: MeetingStatus.disconnected,
          meetingId: null,
          media: const MeetingMediaState(),
          failure: const MeetingFailure(MeetingFailureType.invalidMeeting),
          statusMessage: null,
        ),
      );
      return;
    }

    await _runBootstrap(
      operation: () => _joinMeeting(event.meetingIdInput),
      initialStatusMessage: 'Joining meeting…',
      emit: emit,
    );
  }

  /// Requests the required media permissions once when the meeting flow starts.
  Future<void> _onInitialPermissionsRequested(
    MeetingInitialPermissionsRequested event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      final permissionResult = await _permissionGateway
          .requestRequiredPermissions();
      if (permissionResult is MeetingSuccess<MeetingPermissionStatus>) {
        final status = permissionResult.value;
        if (status == MeetingPermissionStatus.granted) return;
        if (status == MeetingPermissionStatus.denied) {
          emit(
            state.copyWith(
              status: MeetingStatus.idle,
              meetingId: null,
              media: const MeetingMediaState(),
              failure: const MeetingFailure(
                MeetingFailureType.permissionUnavailable,
              ),
              statusMessage: null,
            ),
          );
          return;
        }
        if (status == MeetingPermissionStatus.permanentlyDenied) {
          emit(
            state.copyWith(
              status: MeetingStatus.idle,
              meetingId: null,
              media: const MeetingMediaState(),
              failure: const MeetingFailure(
                MeetingFailureType.permissionPermanentlyDenied,
              ),
              statusMessage: null,
            ),
          );
          return;
        }
      } else if (permissionResult is MeetingError<MeetingPermissionStatus>) {
        emit(
          state.copyWith(
            status: MeetingStatus.idle,
            meetingId: null,
            media: const MeetingMediaState(),
            failure: permissionResult.failure,
            statusMessage: null,
          ),
        );
        return;
      }
    } on Object {
      emit(
        state.copyWith(
          status: MeetingStatus.idle,
          meetingId: null,
          media: const MeetingMediaState(),
          failure: const MeetingFailure(MeetingFailureType.platformBridge),
          statusMessage: null,
        ),
      );
    }
  }

  /// Handles a user-initiated Retry of the permission flow.
  Future<void> _onRetryPermissionsRequested(
    MeetingRetryPermissionsRequested event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      final permissionResult = await _permissionGateway
          .requestRequiredPermissions();
      if (permissionResult is MeetingSuccess<MeetingPermissionStatus>) {
        final status = permissionResult.value;
        if (status == MeetingPermissionStatus.granted) {
          // Clear a prior permission failure; do not auto-retry join/create.
          emit(state.copyWith(failure: null, statusMessage: null));
          return;
        }
        if (status == MeetingPermissionStatus.denied) {
          emit(
            state.copyWith(
              failure: const MeetingFailure(
                MeetingFailureType.permissionUnavailable,
              ),
              statusMessage: null,
            ),
          );
          return;
        }
        if (status == MeetingPermissionStatus.permanentlyDenied) {
          emit(
            state.copyWith(
              failure: const MeetingFailure(
                MeetingFailureType.permissionPermanentlyDenied,
              ),
              statusMessage: null,
            ),
          );
          return;
        }
      } else if (permissionResult is MeetingError<MeetingPermissionStatus>) {
        emit(
          state.copyWith(
            failure: permissionResult.failure,
            statusMessage: null,
          ),
        );
        return;
      }
    } on Object {
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.platformBridge),
          statusMessage: null,
        ),
      );
    }
  }

  /// Handles a user intent to open the platform app settings screen.
  Future<void> _onOpenSettingsRequested(
    MeetingOpenSettingsRequested event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      final result = await _permissionGateway.openAppSettings();
      if (result is MeetingSuccess<bool>) {
        if (result.value) {
          emit(
            state.copyWith(
              statusMessage: 'Opened app settings. Return and Retry.',
            ),
          );
        } else {
          emit(
            state.copyWith(
              failure: const MeetingFailure(MeetingFailureType.platformBridge),
              statusMessage: null,
            ),
          );
        }
      } else if (result is MeetingError<bool>) {
        emit(state.copyWith(failure: result.failure, statusMessage: null));
      }
    } on Object {
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.platformBridge),
          statusMessage: null,
        ),
      );
    }
  }

  /// Serializes permission, REST, and native-start work for create/join.
  ///
  /// The method intentionally keeps [MeetingStatus.joining] until the native
  /// session-start event arrives; accepted REST credentials are not treated as
  /// proof of media connectivity.
  Future<void> _runBootstrap({
    required Future<MeetingResult<MeetingId>> Function() operation,
    required String initialStatusMessage,
    required Emitter<MeetingState> emit,
  }) async {
    if (_bootstrapInFlight ||
        state.status == MeetingStatus.joining ||
        state.status == MeetingStatus.connected ||
        state.status == MeetingStatus.reconnecting) {
      return;
    }

    // Ownership is claimed before the first async boundary.
    _bootstrapInFlight = true;
    _leaveRequestedDuringBootstrap = false;

    _clearSessionOwnership();
    _reconnectAttempts = 0;

    emit(
      state.copyWith(
        status: MeetingStatus.joining,
        meetingId: null,
        media: const MeetingMediaState(),
        eventLog: const <MeetingLogEntry>[],
        failure: null,
        statusMessage: initialStatusMessage,
        reconnectAttempts: 0,
        networkQuality: NetworkQuality.unknown,
      ),
    );

    try {
      final bool isOnline;
      try {
        isOnline = await _connectivityGateway.isOnline;
      } on Object {
        emit(
          state.copyWith(
            status: MeetingStatus.disconnected,
            meetingId: null,
            media: const MeetingMediaState(),
            failure: const MeetingFailure(MeetingFailureType.network),
            statusMessage: null,
            networkQuality: NetworkQuality.unknown,
          ),
        );
        return;
      }

      if (!isOnline) {
        emit(
          state.copyWith(
            status: MeetingStatus.disconnected,
            meetingId: null,
            media: const MeetingMediaState(),
            failure: const MeetingFailure(MeetingFailureType.network),
            statusMessage: null,
            networkQuality: NetworkQuality.unknown,
          ),
        );
        return;
      }

      final permissionResult = await _permissionGateway
          .requestRequiredPermissions();

      switch (permissionResult) {
        case MeetingSuccess<MeetingPermissionStatus>(:final value):
          switch (value) {
            case MeetingPermissionStatus.granted:
              break;

            case MeetingPermissionStatus.denied:
              emit(
                state.copyWith(
                  status: MeetingStatus.idle,
                  meetingId: null,
                  media: const MeetingMediaState(),
                  failure: const MeetingFailure(
                    MeetingFailureType.permissionUnavailable,
                  ),
                  statusMessage: null,
                  networkQuality: NetworkQuality.unknown,
                ),
              );
              return;

            case MeetingPermissionStatus.permanentlyDenied:
              emit(
                state.copyWith(
                  status: MeetingStatus.idle,
                  meetingId: null,
                  media: const MeetingMediaState(),
                  failure: const MeetingFailure(
                    MeetingFailureType.permissionPermanentlyDenied,
                  ),
                  statusMessage: null,
                  networkQuality: NetworkQuality.unknown,
                ),
              );
              return;
          }

        case MeetingError<MeetingPermissionStatus>(:final failure):
          emit(
            state.copyWith(
              status: MeetingStatus.idle,
              meetingId: null,
              media: const MeetingMediaState(),
              failure: failure,
              statusMessage: null,
              networkQuality: NetworkQuality.unknown,
            ),
          );
          return;
      }

      _activeSessionIdentity = ++_lastSessionIdentity;
      final result = await operation();

      if (_leaveRequestedDuringBootstrap) {
        if (result is MeetingSuccess<MeetingId>) {
          await _leaveAfterCancelledBootstrap();
        }
        return;
      }

      switch (result) {
        case MeetingSuccess<MeetingId>(:final value):
          if (state.status == MeetingStatus.disconnected ||
              state.status == MeetingStatus.failed) {
            return;
          }

          final alreadyConnected = state.status == MeetingStatus.connected;

          emit(
            state.copyWith(
              meetingId: value,
              failure: null,
              statusMessage: alreadyConnected
                  ? 'Connected'
                  : 'Connecting to meeting…',
            ),
          );

          if (!alreadyConnected && state.status == MeetingStatus.joining) {
            _armSessionStartTimeout();
          }

        case MeetingError<MeetingId>(:final failure):
          _clearSessionOwnership();

          emit(
            state.copyWith(
              status: _statusForBootstrapFailure(failure),
              meetingId: null,
              media: const MeetingMediaState(),
              failure: failure,
              statusMessage: null,
              networkQuality: NetworkQuality.unknown,
            ),
          );
      }
    } on Object {
      _clearSessionOwnership();

      if (_leaveRequestedDuringBootstrap) {
        return;
      }

      emit(
        state.copyWith(
          status: MeetingStatus.disconnected,
          meetingId: null,
          media: const MeetingMediaState(),
          failure: const MeetingFailure(MeetingFailureType.unexpected),
          statusMessage: null,
          networkQuality: NetworkQuality.unknown,
        ),
      );
    } finally {
      _bootstrapInFlight = false;
    }
  }

  /// Maps bootstrap/media-start failures to the required terminal state.
  MeetingStatus _statusForBootstrapFailure(MeetingFailure failure) {
    switch (failure.type) {
      case MeetingFailureType.unsupportedRuntime:
      case MeetingFailureType.missingMediaConfiguration:
      case MeetingFailureType.invalidAttendeeCredentials:
      case MeetingFailureType.nativeInitialization:
      case MeetingFailureType.meetingStart:
      case MeetingFailureType.platformBridge:
      case MeetingFailureType.sessionAlreadyActive:
        return MeetingStatus.failed;
      default:
        return MeetingStatus.disconnected;
    }
  }

  void _armSessionStartTimeout() {
    _cancelSessionStartTimeout();

    final sessionIdentity = _activeSessionIdentity;
    if (sessionIdentity == null) {
      return;
    }

    _sessionStartTimer = Timer(_sessionStartTimeout, () {
      if (!isClosed) {
        add(MeetingSessionStartTimedOut(sessionIdentity));
      }
    });
  }

  void _cancelSessionStartTimeout() {
    _sessionStartTimer?.cancel();
    _sessionStartTimer = null;
  }

  /// Starts one watchdog for the current SDK-managed reconnect episode.
  void _armReconnectWatchdog() {
    if (_reconnectWatchdogTimer != null) {
      return;
    }

    final sessionIdentity = _activeSessionIdentity;
    if (sessionIdentity == null) {
      return;
    }

    final episode = ++_lastReconnectEpisode;
    final generation = _activeSessionGeneration;
    _activeReconnectEpisode = episode;
    _reconnectWatchdogTimer = Timer(_reconnectTimeout, () {
      if (!isClosed) {
        add(
          MeetingReconnectTimedOut(
            sessionIdentity: sessionIdentity,
            episode: episode,
            generation: generation,
          ),
        );
      }
    });
  }

  void _cancelReconnectWatchdog() {
    _reconnectWatchdogTimer?.cancel();
    _reconnectWatchdogTimer = null;
    _activeReconnectEpisode = null;
  }

  /// Invalidates timers and async work owned by the current meeting session.
  void _clearSessionOwnership() {
    _cancelSessionStartTimeout();
    _cancelReconnectWatchdog();
    _activeSessionGeneration = null;
    _activeSessionIdentity = null;
    _resetLifecycleCameraFlags();
  }

  bool _ownsSession(int sessionIdentity) =>
      _activeSessionIdentity == sessionIdentity;

  void _resetLifecycleCameraFlags() {
    _lifecycleBackgrounded = false;
    _restoreCameraOnResume = false;
  }

  Future<void> _onSessionStartTimedOut(
    MeetingSessionStartTimedOut event,
    Emitter<MeetingState> emit,
  ) async {
    if (state.status != MeetingStatus.joining ||
        !_ownsSession(event.sessionIdentity)) {
      return;
    }

    _clearSessionOwnership();

    final occurredAt = DateTime.now();

    emit(
      state.copyWith(
        status: MeetingStatus.failed,
        media: const MeetingMediaState(),
        networkQuality: NetworkQuality.unknown,
        eventLog: _appendLog(
          state,
          MeetingLogEventType.sessionFailed,
          occurredAt,
        ),
        failure: const MeetingFailure(MeetingFailureType.meetingStart),
        statusMessage: 'Meeting connection timed out.',
      ),
    );

    await _leaveAfterSessionError();
  }

  /// Terminates one stuck SDK reconnect without creating a replacement session.
  Future<void> _onReconnectTimedOut(
    MeetingReconnectTimedOut event,
    Emitter<MeetingState> emit,
  ) async {
    if (state.status != MeetingStatus.reconnecting ||
        !_ownsSession(event.sessionIdentity) ||
        _activeReconnectEpisode != event.episode ||
        (event.generation != null &&
            event.generation != _activeSessionGeneration)) {
      return;
    }

    _clearSessionOwnership();
    final occurredAt = DateTime.now();
    emit(
      state.copyWith(
        status: MeetingStatus.failed,
        media: const MeetingMediaState(),
        networkQuality: NetworkQuality.unknown,
        eventLog: _appendLog(
          state,
          MeetingLogEventType.sessionFailed,
          occurredAt,
        ),
        failure: const MeetingFailure(MeetingFailureType.reconnectTimeout),
        statusMessage: 'Reconnection timed out.',
      ),
    );

    await _leaveAfterSessionError();
  }

  /// Applies a microphone request only while a native session is connected.
  Future<void> _onMicrophoneChanged(
    MeetingMicrophoneChanged event,
    Emitter<MeetingState> emit,
  ) async {
    if (state.status != MeetingStatus.connected &&
        state.status != MeetingStatus.reconnecting) {
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.sessionUnavailable),
          statusMessage: null,
        ),
      );
      return;
    }
    try {
      final result = await _mediaGateway.setMicrophoneEnabled(event.enabled);
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      switch (result) {
        case MeetingSuccess<bool>(:final value):
          emit(_withMicrophoneState(state, value, DateTime.now()));
        case MeetingError<bool>(:final failure):
          emit(state.copyWith(failure: failure, statusMessage: null));
      }
    } on Object {
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.microphoneOperation),
          statusMessage: null,
        ),
      );
    }
  }

  /// Requests camera state while leaving native video callbacks authoritative.
  Future<void> _onCameraChanged(
    MeetingCameraChanged event,
    Emitter<MeetingState> emit,
  ) async {
    if (state.status != MeetingStatus.connected &&
        state.status != MeetingStatus.reconnecting) {
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.sessionUnavailable),
          statusMessage: null,
        ),
      );
      return;
    }
    try {
      final result = await _mediaGateway.setCameraEnabled(event.enabled);
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      switch (result) {
        case MeetingSuccess<bool>():
          // Camera state is updated only by native Chime media callbacks.
          emit(state.copyWith(failure: null));
        case MeetingError<bool>(:final failure):
          emit(state.copyWith(failure: failure, statusMessage: null));
      }
    } on Object {
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.cameraOperation),
          statusMessage: null,
        ),
      );
    }
  }

  /// Leaves or cancels the current session while suppressing duplicate taps.
  Future<void> _onLeaveRequested(
    MeetingLeaveRequested event,
    Emitter<MeetingState> emit,
  ) async {
    if (_leaveInFlight) {
      return;
    }
    if (state.status != MeetingStatus.connected &&
        state.status != MeetingStatus.joining &&
        state.status != MeetingStatus.reconnecting) {
      return;
    }

    _leaveInFlight = true;
    _clearSessionOwnership();
    try {
      if (_bootstrapInFlight) {
        _leaveRequestedDuringBootstrap = true;
        final wasConnected = state.status == MeetingStatus.connected;
        emit(
          state.copyWith(
            status: MeetingStatus.disconnected,
            media: const MeetingMediaState(),
            eventLog: wasConnected
                ? _appendLog(
                    state,
                    MeetingLogEventType.meetingEnded,
                    DateTime.now(),
                  )
                : state.eventLog,
            failure: null,
            statusMessage: 'Meeting ended.',
            networkQuality: NetworkQuality.unknown,
          ),
        );
        // Best-effort immediate cleanup covers a session constructed while the
        // Dart start call is still pending. A late success triggers it again.
        await _leaveAfterCancelledBootstrap();
        return;
      }

      final result = await _mediaGateway.leave();
      if (state.status == MeetingStatus.disconnected) {
        return;
      }
      switch (result) {
        case MeetingSuccess<MeetingStatus>():
          emit(_withSessionStopped(state, DateTime.now()));
        case MeetingError<MeetingStatus>(:final failure):
          emit(
            _withSessionStopped(
              state,
              DateTime.now(),
            ).copyWith(failure: failure),
          );
      }
    } on Object {
      if (state.status == MeetingStatus.disconnected) {
        return;
      }
      emit(
        _withSessionStopped(state, DateTime.now()).copyWith(
          failure: const MeetingFailure(MeetingFailureType.sessionUnavailable),
        ),
      );
    } finally {
      _leaveInFlight = false;
    }
  }

  /// Performs idempotent native cleanup after a leave/start race.
  Future<void> _leaveAfterCancelledBootstrap() async {
    try {
      await _mediaGateway.leave();
    } on Object {
      // The original bootstrap still owns completion. A missing session is an
      // expected race here; any later accepted start repeats cleanup above.
    }
  }

  /// Requests a camera-facing switch from the active native session.
  Future<void> _onSwitchCameraRequested(
    MeetingSwitchCameraRequested event,
    Emitter<MeetingState> emit,
  ) async {
    if (state.status != MeetingStatus.connected &&
        state.status != MeetingStatus.reconnecting) {
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.sessionUnavailable),
          statusMessage: null,
        ),
      );
      return;
    }
    if (!state.media.isCameraEnabled ||
        state.media.localVideo != VideoAvailability.available) {
      return;
    }

    try {
      final result = await _mediaGateway.switchCamera();
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      switch (result) {
        case MeetingSuccess<bool>():
          // No immediate state change; tile callbacks are authoritative.
          return;
        case MeetingError<bool>(:final failure):
          emit(state.copyWith(failure: failure, statusMessage: null));
          return;
      }
    } on Object {
      if (state.status != MeetingStatus.connected &&
          state.status != MeetingStatus.reconnecting) {
        return;
      }
      emit(
        state.copyWith(
          failure: const MeetingFailure(MeetingFailureType.cameraOperation),
          statusMessage: null,
        ),
      );
    }
  }

  /// Reduces normalized native media callbacks into immutable presentation state.
  Future<void> _onMediaEventReceived(
    MeetingMediaEventReceived event,
    Emitter<MeetingState> emit,
  ) async {
    final mediaEvent = event.mediaEvent;
    final eventType = mediaEvent.type;
    final generation = mediaEvent.generation;

    // The first session-start callback establishes the native generation. Every
    // later session-owned callback must match it.
    final isFirstSessionStart =
        eventType == MeetingMediaEventType.sessionStarted &&
        _activeSessionGeneration == null &&
        state.status == MeetingStatus.joining;

    if (!isFirstSessionStart &&
        generation != null &&
        generation != _activeSessionGeneration) {
      // Reject callbacks owned by an older native session.
      return;
    }

    final isActive =
        state.status == MeetingStatus.joining ||
        state.status == MeetingStatus.connected ||
        state.status == MeetingStatus.reconnecting;
    if (!isActive) {
      return;
    }
    if (eventType == MeetingMediaEventType.sessionStarted &&
        state.status != MeetingStatus.joining) {
      return;
    }
    if (eventType == MeetingMediaEventType.sessionStopped &&
        state.status == MeetingStatus.failed) {
      return;
    }

    if (eventType == MeetingMediaEventType.sessionStopped ||
        eventType == MeetingMediaEventType.sessionError) {
      _clearSessionOwnership();
    }

    final occurredAt = mediaEvent.occurredAt;
    var nextState = switch (eventType) {
      MeetingMediaEventType.sessionStarted => () {
        if (generation != null) {
          _activeSessionGeneration = generation;
        }

        _cancelSessionStartTimeout();
        _cancelReconnectWatchdog();
        _reconnectAttempts = 0;

        return state.copyWith(
          status: MeetingStatus.connected,
          failure: null,
          statusMessage: 'Connected',
          reconnectAttempts: 0,
          networkQuality: NetworkQuality.good,
          eventLog: _appendLog(
            state,
            MeetingLogEventType.meetingStarted,
            occurredAt,
          ),
        );
      }(),
      MeetingMediaEventType.sessionStopped => _withSessionStopped(
        state,
        occurredAt,
      ),
      // Audio-session semantic events: preserve distinction but perform no
      // immediate presentation-state mutation here. The legacy sessionStarted
      // event is still emitted for backward compatibility above.
      MeetingMediaEventType.audioSessionStarted => () {
        final audioPlaybackRecovered =
            mediaEvent.failure == null &&
            state.failure?.type == MeetingFailureType.audioPlaybackBlocked;
        return state.copyWith(
          failure: audioPlaybackRecovered ? null : state.failure,
          statusMessage: audioPlaybackRecovered
              ? 'Connected'
              : state.statusMessage,
          eventLog: _appendLog(
            state,
            MeetingLogEventType.audioSessionStarted,
            occurredAt,
          ),
        );
      }(),
      MeetingMediaEventType.audioSessionStopped => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.audioSessionStopped,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.reconnecting => () {
        final wasReconnecting = state.status == MeetingStatus.reconnecting;

        if (!wasReconnecting) {
          _reconnectAttempts += 1;
          _armReconnectWatchdog();
        }

        return state.copyWith(
          status: MeetingStatus.reconnecting,
          networkQuality: NetworkQuality.poor,
          failure: null,
          statusMessage: 'Connection unstable. Reconnecting…',
          reconnectAttempts: _reconnectAttempts,
          eventLog: wasReconnecting
              ? state.eventLog
              : _appendLog(
                  state,
                  MeetingLogEventType.reconnectAttempt,
                  occurredAt,
                ),
        );
      }(),
      MeetingMediaEventType.connectionRecovered => () {
        final shouldLogRecovery =
            state.status == MeetingStatus.reconnecting ||
            state.networkQuality == NetworkQuality.poor;
        _cancelReconnectWatchdog();

        return state.copyWith(
          status: MeetingStatus.connected,
          networkQuality: NetworkQuality.good,
          failure: null,
          statusMessage: 'Connected',
          reconnectAttempts: _reconnectAttempts,
          eventLog: shouldLogRecovery
              ? _appendLog(
                  state,
                  MeetingLogEventType.connectionRecovered,
                  occurredAt,
                )
              : state.eventLog,
        );
      }(),
      MeetingMediaEventType.connectionPoor => state.copyWith(
        networkQuality: NetworkQuality.poor,
        eventLog: _appendLog(
          state,
          MeetingLogEventType.connectionPoor,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.participantJoined => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.participantJoined,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.participantLeft => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.participantLeft,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.localVideoAvailable =>
        _withVideoAvailability(
          state,
          isLocal: true,
          isAvailable: true,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.localVideoAvailable,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.localVideoRemoved =>
        _withVideoAvailability(
          state,
          isLocal: true,
          isAvailable: false,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.localVideoRemoved,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.remoteVideoAvailable =>
        _withVideoAvailability(
          state,
          isLocal: false,
          isAvailable: true,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.remoteVideoAvailable,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.remoteVideoRemoved =>
        _withVideoAvailability(
          state,
          isLocal: false,
          isAvailable: false,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.remoteVideoRemoved,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.localVideoPaused =>
        _withVideoAvailability(
          state,
          isLocal: true,
          isAvailable: false,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.localVideoPaused,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.localVideoResumed =>
        _withVideoAvailability(
          state,
          isLocal: true,
          isAvailable: true,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.localVideoResumed,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.remoteVideoPaused =>
        _withVideoAvailability(
          state,
          isLocal: false,
          isAvailable: false,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.remoteVideoPaused,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.remoteVideoResumed =>
        _withVideoAvailability(
          state,
          isLocal: false,
          isAvailable: true,
        ).copyWith(
          eventLog: _appendLog(
            state,
            MeetingLogEventType.remoteVideoResumed,
            occurredAt,
          ),
        ),
      MeetingMediaEventType.activeSpeaker => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.activeSpeaker,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.volumeLevel => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.volumeLevel,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.audioDeviceChanged => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.audioDeviceChanged,
          occurredAt,
        ),
      ),
      // Semantic mute/unmute events preserved separately. Presentation state
      // still relies on microphoneEnabled/microphoneDisabled events.
      MeetingMediaEventType.localMuted => state.copyWith(
        eventLog: _appendLog(state, MeetingLogEventType.localMuted, occurredAt),
      ),
      MeetingMediaEventType.localUnmuted => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.localUnmuted,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.remoteMuted => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.remoteMuted,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.remoteUnmuted => state.copyWith(
        eventLog: _appendLog(
          state,
          MeetingLogEventType.remoteUnmuted,
          occurredAt,
        ),
      ),
      MeetingMediaEventType.microphoneEnabled => _withMicrophoneState(
        state,
        true,
        occurredAt,
      ),
      MeetingMediaEventType.microphoneDisabled => _withMicrophoneState(
        state,
        false,
        occurredAt,
      ),
      MeetingMediaEventType.cameraEnabled => _withCameraState(
        state,
        true,
        occurredAt,
      ),
      MeetingMediaEventType.cameraDisabled => _withCameraState(
        state,
        false,
        occurredAt,
      ),
      MeetingMediaEventType.sessionError => _withSessionError(
        state,
        occurredAt,
        mediaEvent.failure,
      ),
    };
    if (eventType != MeetingMediaEventType.sessionError &&
        mediaEvent.failure != null) {
      // Browser device failures can be recoverable: camera denial remains
      // audio-only and microphone denial remains listen-only where possible.
      nextState = nextState.copyWith(
        failure: mediaEvent.failure,
        statusMessage: null,
      );
    }
    if (nextState != state) {
      emit(nextState);
    }
    if (eventType == MeetingMediaEventType.sessionError) {
      await _leaveAfterSessionError();
    }
  }

  Future<void> _onVideoSurfaceAttached(
    MeetingVideoSurfaceAttached event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      await _videoSurfaceCoordinator?.attachVideoSurface(
        event.role,
        event.elementId,
      );
    } on Object {
      // Surface/tile order is nondeterministic. The adapter retries binding on
      // later callbacks without turning a render race into a session failure.
    }
  }

  Future<void> _onVideoSurfaceDetached(
    MeetingVideoSurfaceDetached event,
    Emitter<MeetingState> emit,
  ) async {
    try {
      await _videoSurfaceCoordinator?.detachVideoSurface(
        event.role,
        event.elementId,
      );
    } on Object {
      // Route disposal must continue even if the browser element already left.
    }
  }

  /// Attempts native cleanup without replacing the original session failure.
  Future<void> _leaveAfterSessionError() async {
    try {
      await _mediaGateway.leave();
    } on Object {
      // Preserve the original typed session failure. Cleanup is best effort
      // because the native session may already have stopped itself.
    }
  }

  /// Handles lifecycle notifications without recreating or rejoining a session.
  Future<void> _onLifecycleChanged(
    MeetingLifecycleChanged event,
    Emitter<MeetingState> emit,
  ) async {
    final hasActiveSession =
        state.status == MeetingStatus.connected ||
        state.status == MeetingStatus.reconnecting;
    final sessionIdentity = _activeSessionIdentity;

    switch (event.state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (!hasActiveSession ||
            sessionIdentity == null ||
            _lifecycleBackgrounded) {
          return;
        }

        _lifecycleBackgrounded = true;
        _restoreCameraOnResume = state.media.isCameraEnabled;

        if (!_restoreCameraOnResume) {
          return;
        }

        final result = await _mediaGateway.setCameraEnabled(false);

        if (!_ownsSession(sessionIdentity) ||
            (state.status != MeetingStatus.connected &&
                state.status != MeetingStatus.reconnecting)) {
          return;
        }

        if (result is MeetingError<bool>) {
          emit(state.copyWith(failure: result.failure, statusMessage: null));
        }

        // Native callback remains authority for camera=false.
        return;

      case AppLifecycleState.resumed:
        if (!_lifecycleBackgrounded || sessionIdentity == null) {
          return;
        }

        _lifecycleBackgrounded = false;

        final shouldRestoreCamera = _restoreCameraOnResume;
        _restoreCameraOnResume = false;

        if (!shouldRestoreCamera ||
            (state.status != MeetingStatus.connected &&
                state.status != MeetingStatus.reconnecting)) {
          return;
        }

        final result = await _mediaGateway.setCameraEnabled(true);

        if (!_ownsSession(sessionIdentity) ||
            (state.status != MeetingStatus.connected &&
                state.status != MeetingStatus.reconnecting)) {
          return;
        }

        if (result is MeetingError<bool>) {
          emit(state.copyWith(failure: result.failure, statusMessage: null));
        }

        // Never optimistically set camera=true.
        // Wait for the native callback.
        return;

      case AppLifecycleState.detached:
        _resetLifecycleCameraFlags();
        return;

      case AppLifecycleState.hidden:
        return;
    }
  }

  /// Produces the terminal disconnected state and appends one meeting-end event.
  MeetingState _withSessionStopped(MeetingState current, DateTime occurredAt) {
    if (current.status == MeetingStatus.disconnected ||
        current.status == MeetingStatus.failed) {
      return current;
    }
    final log = _appendLog(
      current,
      MeetingLogEventType.meetingEnded,
      occurredAt,
    );
    return current.copyWith(
      status: MeetingStatus.disconnected,
      media: const MeetingMediaState(),
      eventLog: log,
      failure: null,
      statusMessage: 'Meeting ended.',
      networkQuality: NetworkQuality.unknown,
    );
  }

  MeetingState _withSessionError(
    MeetingState current,
    DateTime occurredAt,
    MeetingFailure? failure,
  ) {
    return current.copyWith(
      status: MeetingStatus.failed,
      media: const MeetingMediaState(),
      networkQuality: NetworkQuality.unknown,
      eventLog: _appendLog(
        current,
        MeetingLogEventType.sessionFailed,
        occurredAt,
      ),
      failure:
          failure ?? const MeetingFailure(MeetingFailureType.platformBridge),
      statusMessage: 'Meeting failed.',
    );
  }

  /// Applies confirmed microphone state and suppresses duplicate log entries.
  MeetingState _withMicrophoneState(
    MeetingState current,
    bool enabled,
    DateTime occurredAt,
  ) {
    if (current.media.isMicrophoneEnabled == enabled) {
      return current;
    }
    return current.copyWith(
      media: MeetingMediaState(
        isMicrophoneEnabled: enabled,
        isCameraEnabled: current.media.isCameraEnabled,
        localVideo: current.media.localVideo,
        remoteVideo: current.media.remoteVideo,
      ),
      eventLog: _appendLog(
        current,
        enabled
            ? MeetingLogEventType.microphoneEnabled
            : MeetingLogEventType.microphoneDisabled,
        occurredAt,
      ),
      failure: null,
    );
  }

  /// Applies callback-confirmed camera state and suppresses duplicate logs.
  MeetingState _withCameraState(
    MeetingState current,
    bool enabled,
    DateTime occurredAt,
  ) {
    if (current.media.isCameraEnabled == enabled) {
      return current;
    }
    return current.copyWith(
      media: MeetingMediaState(
        isMicrophoneEnabled: current.media.isMicrophoneEnabled,
        isCameraEnabled: enabled,
        localVideo: current.media.localVideo,
        remoteVideo: current.media.remoteVideo,
      ),
      eventLog: _appendLog(
        current,
        enabled
            ? MeetingLogEventType.cameraEnabled
            : MeetingLogEventType.cameraDisabled,
        occurredAt,
      ),
      failure: null,
    );
  }

  /// Applies local or remote tile availability without changing control state.
  MeetingState _withVideoAvailability(
    MeetingState current, {
    required bool isLocal,
    required bool isAvailable,
  }) {
    final availability = isAvailable
        ? VideoAvailability.available
        : VideoAvailability.unavailable;
    final nextMedia = MeetingMediaState(
      isMicrophoneEnabled: current.media.isMicrophoneEnabled,
      isCameraEnabled: current.media.isCameraEnabled,
      localVideo: isLocal ? availability : current.media.localVideo,
      remoteVideo: isLocal ? current.media.remoteVideo : availability,
    );
    return nextMedia == current.media
        ? current
        : current.copyWith(media: nextMedia);
  }

  /// Returns a new immutable-ready event list with one appended safe entry.
  /// Ensures only the newest [_maxEventLogEntries] are retained to avoid
  /// unbounded memory growth.
  List<MeetingLogEntry> _appendLog(
    MeetingState current,
    MeetingLogEventType type,
    DateTime occurredAt, {
    Map<String, String>? metadata,
  }) {
    final message = _labelFor(type);
    final next = <MeetingLogEntry>[...current.eventLog];
    // Append new entry at the end (newest last) and trim oldest if needed.
    next.add(
      MeetingLogEntry(
        type: type,
        occurredAt: occurredAt,
        message: message,
        metadata: metadata,
      ),
    );
    if (next.length <= _maxEventLogEntries) {
      return List<MeetingLogEntry>.unmodifiable(next);
    }
    // Keep only the newest [_maxEventLogEntries] entries.
    final trimmed = next.sublist(next.length - _maxEventLogEntries);
    return List<MeetingLogEntry>.unmodifiable(trimmed);
  }

  String _labelFor(MeetingLogEventType type) => switch (type) {
    MeetingLogEventType.meetingStarted => 'Meeting started',
    MeetingLogEventType.meetingEnded => 'Meeting ended',
    MeetingLogEventType.audioSessionStarted => 'Audio session started',
    MeetingLogEventType.audioSessionStopped => 'Audio session stopped',
    MeetingLogEventType.participantJoined => 'Participant joined',
    MeetingLogEventType.participantLeft => 'Participant left',
    MeetingLogEventType.localVideoAvailable => 'Local video available',
    MeetingLogEventType.localVideoRemoved => 'Local video removed',
    MeetingLogEventType.remoteVideoAvailable => 'Remote video available',
    MeetingLogEventType.remoteVideoRemoved => 'Remote video removed',
    MeetingLogEventType.localVideoPaused => 'Local video paused',
    MeetingLogEventType.localVideoResumed => 'Local video resumed',
    MeetingLogEventType.remoteVideoPaused => 'Remote video paused',
    MeetingLogEventType.remoteVideoResumed => 'Remote video resumed',
    MeetingLogEventType.microphoneEnabled => 'Microphone enabled',
    MeetingLogEventType.microphoneDisabled => 'Microphone disabled',
    MeetingLogEventType.localMuted => 'Local muted',
    MeetingLogEventType.localUnmuted => 'Local unmuted',
    MeetingLogEventType.remoteMuted => 'Remote muted',
    MeetingLogEventType.remoteUnmuted => 'Remote unmuted',
    MeetingLogEventType.cameraEnabled => 'Camera enabled',
    MeetingLogEventType.cameraDisabled => 'Camera disabled',
    MeetingLogEventType.reconnectAttempt => 'Reconnect attempt',
    MeetingLogEventType.connectionRecovered => 'Connection recovered',
    MeetingLogEventType.connectionPoor => 'Connection poor',
    MeetingLogEventType.activeSpeaker => 'Active speaker change',
    MeetingLogEventType.volumeLevel => 'Volume indication',
    MeetingLogEventType.audioDeviceChanged => 'Audio device changed',
    MeetingLogEventType.sessionFailed => 'Meeting failed',
  };

  /// Cancels only the presentation subscription; GetIt owns gateway disposal.
  @override
  Future<void> close() async {
    _clearSessionOwnership();
    await _mediaSubscription.cancel();
    return super.close();
  }
}

MeetingVideoSurfaceCoordinator? _coordinatorFrom(
  MeetingMediaGateway mediaGateway,
) {
  return switch (mediaGateway) {
    MeetingVideoSurfaceCoordinator coordinator => coordinator,
    _ => null,
  };
}
