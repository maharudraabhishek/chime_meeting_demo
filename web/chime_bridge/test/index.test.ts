import assert from 'node:assert/strict';
import test from 'node:test';

import { BridgeError, mapDeviceError, validateStartSessionRequest } from '../src/error-mapper';
import {
  AudioPlaybackGestureRetry,
  DeferredMediaEvents,
  isMicrophoneEnabled,
  LifecycleEventCoordinator,
  nextCameraDevice,
  RemoteAttendeeCoordinator,
  VideoTileCoordinator,
} from '../src/session-state';

const validRequest = {
  generation: 7,
  meeting: {
    MeetingId: 'meeting',
    MediaPlacement: {
      AudioHostUrl: 'audio',
      AudioFallbackUrl: 'fallback',
      SignalingUrl: 'signal',
      TurnControlUrl: 'turn',
    },
  },
  attendee: {
    AttendeeId: 'local',
    ExternalUserId: 'external',
    JoinToken: 'token',
  },
};

test('validates required bootstrap fields without changing the payload', () => {
  assert.equal(validateStartSessionRequest(validRequest), validRequest);
  assert.throws(
    () =>
      validateStartSessionRequest({
        ...validRequest,
        meeting: { MeetingId: 'meeting', MediaPlacement: {} },
      }),
    error =>
      error instanceof BridgeError && error.failureCode === 'missing_media_configuration',
  );
  assert.throws(
    () => validateStartSessionRequest({ ...validRequest, attendee: {} }),
    error =>
      error instanceof BridgeError && error.failureCode === 'invalid_attendee_credentials',
  );
});

test('maps browser media errors into stable safe failure codes', () => {
  assert.equal(mapDeviceError({ name: 'NotAllowedError' }, 'microphone'), 'microphone_permission_denied');
  assert.equal(mapDeviceError({ name: 'NotAllowedError' }, 'camera'), 'camera_permission_denied');
  assert.equal(mapDeviceError({ name: 'NotFoundError' }, 'camera'), 'device_not_found');
  assert.equal(mapDeviceError({ name: 'NotReadableError' }, 'camera'), 'device_not_readable');
  assert.equal(mapDeviceError({ name: 'OverconstrainedError' }, 'camera'), 'device_constraints');
});

test('emits one initial start and one event per reconnect episode', () => {
  const lifecycle = new LifecycleEventCoordinator(5);
  assert.equal(lifecycle.onDidStart()?.type, 'sessionStarted');
  assert.equal(lifecycle.onDidStart(), null);
  assert.equal(lifecycle.onStartConnecting(true)?.type, 'sessionReconnecting');
  assert.equal(lifecycle.onStartConnecting(true), null);
  assert.equal(lifecycle.onDidStart()?.type, 'connectionRecovered');
  assert.equal(lifecycle.onDidStart(), null);
});

test('defers media state until after the initial session-start event', () => {
  const deferred = new DeferredMediaEvents();
  assert.deepEqual(
    deferred.record({ type: 'microphoneDisabled', generation: 5 }, false),
    [],
  );
  assert.deepEqual(deferred.record({ type: 'cameraEnabled', generation: 5 }, false), []);
  assert.deepEqual(deferred.flush().map(event => event.type), [
    'microphoneDisabled',
    'cameraEnabled',
  ]);
  assert.deepEqual(deferred.record({ type: 'cameraDisabled', generation: 5 }, true), [
    { type: 'cameraDisabled', generation: 5 },
  ]);
});

test('mute return semantics report whether the microphone is enabled', () => {
  assert.equal(isMicrophoneEnabled(true), false);
  assert.equal(isMicrophoneEnabled(false), true);
});

test('autoplay gesture retry is one-shot, disposable, and generation safe', async () => {
  const target = new EventTarget();
  let active = true;
  let retries = 0;
  let recoveries = 0;
  const retry = new AudioPlaybackGestureRetry(
    target,
    () => active,
    async () => {
      retries += 1;
    },
    () => {
      recoveries += 1;
    },
  );
  retry.install();
  target.dispatchEvent(new Event('pointerdown'));
  await Promise.resolve();
  assert.equal(retries, 1);
  assert.equal(recoveries, 1);
  target.dispatchEvent(new Event('keydown'));
  assert.equal(retries, 1);

  const stale = new AudioPlaybackGestureRetry(
    target,
    () => active,
    async () => {
      retries += 1;
    },
    () => {
      recoveries += 1;
    },
  );
  stale.install();
  active = false;
  target.dispatchEvent(new Event('pointerdown'));
  await Promise.resolve();
  assert.equal(retries, 1);
  assert.equal(recoveries, 1);

  active = true;
  const disposed = new AudioPlaybackGestureRetry(
    target,
    () => active,
    async () => {
      retries += 1;
    },
    () => {
      recoveries += 1;
    },
  );
  disposed.install();
  disposed.dispose();
  target.dispatchEvent(new Event('keydown'));
  assert.equal(retries, 1);
});

test('deduplicates poor and good connection transitions', () => {
  const lifecycle = new LifecycleEventCoordinator(3);
  assert.equal(lifecycle.onPoor()?.type, 'connectionPoor');
  assert.equal(lifecycle.onPoor(), null);
  assert.equal(lifecycle.onGood()?.type, 'connectionRecovered');
  assert.equal(lifecycle.onGood(), null);
});

test('tracks remote presence, mute changes, and throttled volume', () => {
  const attendees = new RemoteAttendeeCoordinator(9, 'local');
  assert.equal(attendees.presence('local', true), null);
  assert.equal(attendees.presence('remote#content', true), null);
  assert.equal(attendees.presence('remote', true)?.type, 'participantJoined');
  assert.equal(attendees.presence('remote', true), null);
  assert.deepEqual(
    attendees.volume('remote', 0.3, false, 1000).map(event => event.type),
    ['volumeLevel'],
  );
  assert.deepEqual(attendees.volume('remote', 0.5, false, 1500), []);
  assert.deepEqual(
    attendees.volume('remote', 0.6, true, 2000).map(event => event.type),
    ['remoteMuted', 'volumeLevel'],
  );
  assert.equal(attendees.presence('remote', false)?.type, 'participantLeft');
  assert.deepEqual(attendees.volume('remote', 0.7, false, 3000), []);
});

test('binds a tile that arrives before its Flutter video element', () => {
  const tiles = new VideoTileCoordinator(4);
  const update = tiles.update({
    tileId: 11,
    localTile: false,
    isContent: false,
    boundAttendeeId: 'remote',
    paused: false,
  });
  assert.deepEqual(update.map(action => action.kind), ['event']);
  assert.deepEqual(tiles.attach('remote', 'remote-video'), [
    { kind: 'bind', role: 'remote', tileId: 11, elementId: 'remote-video' },
  ]);
});

test('binds an element that arrives before its tile', () => {
  const tiles = new VideoTileCoordinator(4);
  assert.deepEqual(tiles.attach('local', 'local-video'), []);
  const update = tiles.update({
    tileId: 12,
    localTile: true,
    isContent: false,
    boundAttendeeId: 'local',
    paused: false,
  });
  assert.deepEqual(update.map(action => action.kind), ['event', 'bind']);
});

test('ignores content tiles and stale removal of a replaced remote tile', () => {
  const tiles = new VideoTileCoordinator(2);
  assert.deepEqual(
    tiles.update({
      tileId: 1,
      localTile: false,
      isContent: true,
      boundAttendeeId: 'remote#content',
      paused: false,
    }),
    [],
  );
  tiles.update({
    tileId: 2,
    localTile: false,
    isContent: false,
    boundAttendeeId: 'remote',
    paused: false,
  });
  tiles.update({
    tileId: 3,
    localTile: false,
    isContent: false,
    boundAttendeeId: 'remote',
    paused: false,
  });
  assert.deepEqual(tiles.remove(2), []);
  assert.equal(tiles.remove(3).find(action => action.kind === 'event')?.event.type, 'remoteVideoRemoved');
});

test('camera switching cycles and a single camera cannot switch', () => {
  const cameras = [
    { deviceId: 'a' },
    { deviceId: 'b' },
    { deviceId: 'c' },
  ] as MediaDeviceInfo[];
  assert.equal(nextCameraDevice(cameras, 'a')?.deviceId, 'b');
  assert.equal(nextCameraDevice(cameras, 'c')?.deviceId, 'a');
  assert.equal(nextCameraDevice(cameras, null)?.deviceId, 'a');
  assert.equal(nextCameraDevice(cameras.slice(0, 1), 'a'), null);
});
