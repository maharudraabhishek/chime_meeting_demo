export type BridgeFailureCode =
  | 'bridge_unavailable'
  | 'unsupported_runtime'
  | 'missing_media_configuration'
  | 'invalid_attendee_credentials'
  | 'microphone_permission_denied'
  | 'camera_permission_denied'
  | 'device_not_found'
  | 'device_not_readable'
  | 'device_constraints'
  | 'session_start'
  | 'session_stopped_fatal'
  | 'audio_playback_blocked'
  | 'interop_failure';

export type BridgeEventType =
  | 'sessionStarted'
  | 'sessionStopped'
  | 'audioSessionStarted'
  | 'audioSessionStopped'
  | 'sessionReconnecting'
  | 'connectionPoor'
  | 'connectionRecovered'
  | 'participantJoined'
  | 'participantLeft'
  | 'localVideoAvailable'
  | 'localVideoRemoved'
  | 'remoteVideoAvailable'
  | 'remoteVideoRemoved'
  | 'localVideoPaused'
  | 'localVideoResumed'
  | 'remoteVideoPaused'
  | 'remoteVideoResumed'
  | 'localMuted'
  | 'localUnmuted'
  | 'remoteMuted'
  | 'remoteUnmuted'
  | 'microphoneEnabled'
  | 'microphoneDisabled'
  | 'cameraEnabled'
  | 'cameraDisabled'
  | 'activeSpeaker'
  | 'volumeLevel'
  | 'audioDeviceChanged'
  | 'sessionError';

export interface BridgeEvent {
  readonly type: BridgeEventType;
  readonly generation: number;
  readonly attendeeId?: string;
  readonly volume?: number;
  readonly failureCode?: BridgeFailureCode;
  readonly statusCode?: number;
}

export type BridgeEventHandler = (event: BridgeEvent) => void;

export interface MeetingMediaPlacementPayload {
  readonly AudioHostUrl: string;
  readonly AudioFallbackUrl: string;
  readonly SignalingUrl: string;
  readonly TurnControlUrl: string;
  readonly EventIngestionUrl?: string;
}

export interface MeetingPayload {
  readonly MeetingId: string;
  readonly MediaPlacement: MeetingMediaPlacementPayload;
}

export interface AttendeePayload {
  readonly AttendeeId: string;
  readonly ExternalUserId: string;
  readonly JoinToken: string;
}

export interface StartSessionRequest {
  readonly generation: number;
  readonly meeting: MeetingPayload;
  readonly attendee: AttendeePayload;
  readonly debugLogging?: boolean;
}

export type VideoRole = 'local' | 'remote';

export interface ChimeWebBridge {
  isSupported(): boolean;
  setEventHandler(handler: BridgeEventHandler | null): void;
  startSession(request: StartSessionRequest): Promise<void>;
  stopSession(generation: number): Promise<void>;
  muteLocalAudio(generation: number): Promise<boolean>;
  unmuteLocalAudio(generation: number): Promise<boolean>;
  startLocalVideo(generation: number): Promise<void>;
  stopLocalVideo(generation: number): Promise<void>;
  switchCamera(generation: number): Promise<boolean>;
  attachLocalVideoElement(generation: number, elementId: string): void;
  attachRemoteVideoElement(generation: number, elementId: string): void;
  detachVideoElement(generation: number, role: VideoRole): void;
  dispose(): Promise<void>;
}
