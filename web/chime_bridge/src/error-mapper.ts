import type {
  AttendeePayload,
  BridgeFailureCode,
  MeetingPayload,
  StartSessionRequest,
} from './bridge-types';

export type MediaDeviceKind = 'microphone' | 'camera';

export class BridgeError extends Error {
  constructor(
    readonly failureCode: BridgeFailureCode,
    message: string,
  ) {
    super(message);
    this.name = 'BridgeError';
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function hasText(record: Record<string, unknown>, key: string): boolean {
  const value = record[key];
  return typeof value === 'string' && value.trim().length > 0;
}

export function validateStartSessionRequest(value: unknown): StartSessionRequest {
  if (!isRecord(value) || !Number.isSafeInteger(value['generation'])) {
    throw new BridgeError('interop_failure', 'Invalid session generation.');
  }

  const generation = value['generation'] as number;
  if (generation < 0) {
    throw new BridgeError('interop_failure', 'Invalid session generation.');
  }

  const meeting = value['meeting'];
  if (!isRecord(meeting) || !hasText(meeting, 'MeetingId')) {
    throw new BridgeError('missing_media_configuration', 'Meeting configuration is incomplete.');
  }

  const placement = meeting['MediaPlacement'];
  const requiredPlacement = [
    'AudioHostUrl',
    'AudioFallbackUrl',
    'SignalingUrl',
    'TurnControlUrl',
  ] as const;
  if (!isRecord(placement) || requiredPlacement.some(key => !hasText(placement, key))) {
    throw new BridgeError('missing_media_configuration', 'Meeting configuration is incomplete.');
  }

  const attendee = value['attendee'];
  const requiredAttendee = ['AttendeeId', 'ExternalUserId', 'JoinToken'] as const;
  if (!isRecord(attendee) || requiredAttendee.some(key => !hasText(attendee, key))) {
    throw new BridgeError('invalid_attendee_credentials', 'Attendee credentials are incomplete.');
  }

  return value as unknown as StartSessionRequest;
}

export function mapDeviceError(error: unknown, kind: MediaDeviceKind): BridgeFailureCode {
  const name = errorName(error);
  if (
    name === 'NotAllowedError' ||
    name === 'PermissionDeniedError' ||
    name === 'SecurityError'
  ) {
    return kind === 'microphone'
      ? 'microphone_permission_denied'
      : 'camera_permission_denied';
  }
  if (name === 'NotFoundError' || name === 'DevicesNotFoundError') {
    return 'device_not_found';
  }
  if (name === 'NotReadableError' || name === 'TrackStartError' || name === 'AbortError') {
    return 'device_not_readable';
  }
  if (name === 'OverconstrainedError' || name === 'ConstraintNotSatisfiedError' || name === 'TypeError') {
    return 'device_constraints';
  }
  return 'device_not_readable';
}

export function mapSessionError(error: unknown): BridgeFailureCode {
  if (error instanceof BridgeError) {
    return error.failureCode;
  }
  return 'session_start';
}

function errorName(error: unknown): string {
  if (isRecord(error) && typeof error['name'] === 'string') {
    return error['name'];
  }
  return '';
}

export function cloneMeetingPayload(meeting: MeetingPayload): MeetingPayload {
  const eventIngestionUrl = meeting.MediaPlacement.EventIngestionUrl;
  const mediaPlacement: MeetingPayload['MediaPlacement'] = {
    AudioHostUrl: meeting.MediaPlacement.AudioHostUrl,
    AudioFallbackUrl: meeting.MediaPlacement.AudioFallbackUrl,
    SignalingUrl: meeting.MediaPlacement.SignalingUrl,
    TurnControlUrl: meeting.MediaPlacement.TurnControlUrl,
    ...(eventIngestionUrl ? { EventIngestionUrl: eventIngestionUrl } : {}),
  };
  return { MeetingId: meeting.MeetingId, MediaPlacement: mediaPlacement };
}

export function cloneAttendeePayload(attendee: AttendeePayload): AttendeePayload {
  return {
    AttendeeId: attendee.AttendeeId,
    ExternalUserId: attendee.ExternalUserId,
    JoinToken: attendee.JoinToken,
  };
}

