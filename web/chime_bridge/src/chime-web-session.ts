import type AudioVideoObserver from 'amazon-chime-sdk-js/build/audiovideoobserver/AudioVideoObserver';
import DefaultActiveSpeakerPolicy from 'amazon-chime-sdk-js/build/activespeakerpolicy/DefaultActiveSpeakerPolicy';
import DefaultDeviceController from 'amazon-chime-sdk-js/build/devicecontroller/DefaultDeviceController';
import type DeviceChangeObserver from 'amazon-chime-sdk-js/build/devicechangeobserver/DeviceChangeObserver';
import ConsoleLogger from 'amazon-chime-sdk-js/build/logger/ConsoleLogger';
import LogLevel from 'amazon-chime-sdk-js/build/logger/LogLevel';
import DefaultMeetingSession from 'amazon-chime-sdk-js/build/meetingsession/DefaultMeetingSession';
import MeetingSessionConfiguration from 'amazon-chime-sdk-js/build/meetingsession/MeetingSessionConfiguration';
import type MeetingSessionStatus from 'amazon-chime-sdk-js/build/meetingsession/MeetingSessionStatus';
import MeetingSessionStatusCode from 'amazon-chime-sdk-js/build/meetingsession/MeetingSessionStatusCode';
import type VolumeIndicatorCallback from 'amazon-chime-sdk-js/build/realtimecontroller/VolumeIndicatorCallback';
import type VideoTileState from 'amazon-chime-sdk-js/build/videotile/VideoTileState';

import type {
  BridgeEvent,
  BridgeEventHandler,
  BridgeFailureCode,
  ChimeWebBridge,
  StartSessionRequest,
  VideoRole,
} from './bridge-types';
import {
  BridgeError,
  cloneAttendeePayload,
  cloneMeetingPayload,
  mapDeviceError,
  mapSessionError,
  validateStartSessionRequest,
} from './error-mapper';
import {
  AudioPlaybackGestureRetry,
  DeferredMediaEvents,
  isMicrophoneEnabled,
  LifecycleEventCoordinator,
  nextCameraDevice,
  RemoteAttendeeCoordinator,
  type TileAction,
  VideoTileCoordinator,
} from './session-state';

export function isBrowserRuntimeSupported(): boolean {
  if (
    typeof window === 'undefined' ||
    typeof document === 'undefined' ||
    typeof navigator === 'undefined' ||
    typeof globalThis.RTCPeerConnection === 'undefined' ||
    !navigator.mediaDevices
  ) {
    return false;
  }
  const host = window.location.hostname.toLowerCase();
  const loopback = host === 'localhost' || host === '127.0.0.1' || host === '[::1]';
  return window.isSecureContext || loopback;
}

export class ChimeWebSession implements ChimeWebBridge {
  private eventHandler: BridgeEventHandler | null = null;
  private activeGeneration: number | null = null;
  private disposed = false;
  private session: DefaultMeetingSession | null = null;
  private deviceController: DefaultDeviceController | null = null;
  private audioElement: HTMLAudioElement | null = null;
  private audioGestureRetry: AudioPlaybackGestureRetry | null = null;
  private observer: AudioVideoObserver | null = null;
  private deviceObserver: DeviceChangeObserver | null = null;
  private presenceCallback: ((attendeeId: string, present: boolean) => void) | null = null;
  private localMuteCallback: ((muted: boolean) => void) | null = null;
  private fatalCallback: ((error: Error) => void) | null = null;
  private activeSpeakerCallback: ((attendeeIds: string[]) => void) | null = null;
  private readonly volumeCallbacks = new Map<string, VolumeIndicatorCallback>();
  private lifecycle: LifecycleEventCoordinator | null = null;
  private attendees: RemoteAttendeeCoordinator | null = null;
  private tiles: VideoTileCoordinator | null = null;
  private selectedCameraId: string | null = null;
  private cameraInputActive = false;
  private cameraRequested = true;
  private readonly deferredMediaEvents = new DeferredMediaEvents();

  isSupported(): boolean {
    return !this.disposed && isBrowserRuntimeSupported();
  }

  setEventHandler(handler: BridgeEventHandler | null): void {
    if (!this.disposed) {
      this.eventHandler = handler;
    }
  }

  async startSession(unvalidatedRequest: StartSessionRequest): Promise<void> {
    if (this.disposed) {
      throw new BridgeError('bridge_unavailable', 'The browser media bridge is disposed.');
    }
    const request = validateStartSessionRequest(unvalidatedRequest);
    await this.cleanupSession();
    if (!isBrowserRuntimeSupported()) {
      throw new BridgeError('unsupported_runtime', 'This browser cannot start meeting media.');
    }

    const generation = request.generation;
    this.activeGeneration = generation;
    this.lifecycle = new LifecycleEventCoordinator(generation);
    this.attendees = new RemoteAttendeeCoordinator(generation, request.attendee.AttendeeId);
    this.tiles = new VideoTileCoordinator(generation);
    this.cameraRequested = true;

    try {
      const logger = new ConsoleLogger(
        'ChimeWeb',
        request.debugLogging === true ? LogLevel.INFO : LogLevel.ERROR,
      );
      const deviceController = new DefaultDeviceController(logger);
      // Avoid the SDK's default combined microphone-and-camera label request so
      // either device can fail without preventing partial participation.
      deviceController.setDeviceLabelTrigger(async () => new MediaStream());
      const configuration = new MeetingSessionConfiguration(
        cloneMeetingPayload(request.meeting),
        cloneAttendeePayload(request.attendee),
      );
      const session = new DefaultMeetingSession(configuration, logger, deviceController);
      if (!this.isActive(generation)) {
        await this.destroyDetachedSession(session, deviceController);
        return;
      }
      this.deviceController = deviceController;
      this.session = session;

      await this.createAndBindAudioElement(generation);
      if (!this.isActive(generation)) return;
      this.registerObservers(generation);
      await this.selectMicrophone(generation);
      if (!this.isActive(generation)) return;
      await this.selectCamera(generation);
      if (!this.isActive(generation)) return;
      session.audioVideo.start();
    } catch (error) {
      if (!this.isActive(generation)) return;
      const failureCode = mapSessionError(error);
      this.emit({ type: 'sessionError', generation, failureCode });
      await this.cleanupSession();
      throw new BridgeError(failureCode, 'The browser meeting session could not start.');
    }
  }

  async stopSession(generation: number): Promise<void> {
    if (!this.isActive(generation)) return;
    await this.cleanupSession();
  }

  async muteLocalAudio(generation: number): Promise<boolean> {
    const session = this.requireSession(generation);
    session.audioVideo.realtimeMuteLocalAudio();
    return isMicrophoneEnabled(session.audioVideo.realtimeIsLocalAudioMuted());
  }

  async unmuteLocalAudio(generation: number): Promise<boolean> {
    const session = this.requireSession(generation);
    const accepted = session.audioVideo.realtimeUnmuteLocalAudio();
    return accepted && !session.audioVideo.realtimeIsLocalAudioMuted();
  }

  async startLocalVideo(generation: number): Promise<void> {
    this.requireSession(generation);
    this.cameraRequested = true;
    await this.selectCamera(generation, true);
    if (!this.isActive(generation) || !this.cameraInputActive) return;
    if (this.lifecycle?.hasStarted) {
      this.session?.audioVideo.startLocalVideoTile();
    }
  }

  async stopLocalVideo(generation: number): Promise<void> {
    const session = this.requireSession(generation);
    this.cameraRequested = false;
    session.audioVideo.stopLocalVideoTile();
    session.audioVideo.removeLocalVideoTile();
    await session.audioVideo.stopVideoInput();
    if (!this.isActive(generation)) return;
    this.cameraInputActive = false;
    this.emit({ type: 'cameraDisabled', generation });
  }

  async switchCamera(generation: number): Promise<boolean> {
    const session = this.requireSession(generation);
    let devices: MediaDeviceInfo[];
    try {
      devices = await session.audioVideo.listVideoInputDevices(true);
    } catch (error) {
      if (this.isActive(generation)) {
        this.emit({
          type: 'cameraDisabled',
          generation,
          failureCode: mapDeviceError(error, 'camera'),
        });
      }
      return false;
    }
    if (!this.isActive(generation) || devices.length < 2) return false;
    const next = nextCameraDevice(devices, this.selectedCameraId);
    if (!next) return false;
    try {
      await session.audioVideo.startVideoInput(next.deviceId);
      if (!this.isActive(generation)) return false;
      this.selectedCameraId = next.deviceId;
      this.cameraInputActive = true;
      this.cameraRequested = true;
      if (this.lifecycle?.hasStarted) session.audioVideo.startLocalVideoTile();
      this.emit({ type: 'cameraEnabled', generation });
      return true;
    } catch (error) {
      if (this.isActive(generation)) {
        this.emit({
          type: 'cameraDisabled',
          generation,
          failureCode: mapDeviceError(error, 'camera'),
        });
      }
      return false;
    }
  }

  attachLocalVideoElement(generation: number, elementId: string): void {
    this.attachVideoElement(generation, 'local', elementId);
  }

  attachRemoteVideoElement(generation: number, elementId: string): void {
    this.attachVideoElement(generation, 'remote', elementId);
  }

  detachVideoElement(generation: number, role: VideoRole): void {
    if (!this.isActive(generation)) return;
    this.applyTileActions(this.tiles?.detach(role) ?? []);
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    await this.cleanupSession();
    this.disposed = true;
    this.eventHandler = null;
  }

  private registerObservers(generation: number): void {
    const session = this.requireSession(generation);
    const audioVideo = session.audioVideo;

    this.observer = {
      audioVideoDidStartConnecting: reconnecting =>
        this.guardCallback(generation, () => this.emitOptional(this.lifecycle?.onStartConnecting(reconnecting))),
      audioVideoDidStart: () =>
        this.guardCallback(generation, () => {
          const event = this.lifecycle?.onDidStart() ?? null;
          this.emitOptional(event);
          if (event?.type === 'sessionStarted') {
            for (const deferred of this.deferredMediaEvents.flush()) this.emit(deferred);
          }
          if (this.cameraInputActive && this.cameraRequested) {
            audioVideo.startLocalVideoTile();
          }
          void this.startAudioPlayback(generation);
        }),
      audioVideoDidStop: status =>
        this.guardCallback(generation, () => this.handleSessionStopped(generation, status)),
      connectionDidBecomePoor: () =>
        this.guardCallback(generation, () => this.emitOptional(this.lifecycle?.onPoor())),
      connectionDidBecomeGood: () =>
        this.guardCallback(generation, () => this.emitOptional(this.lifecycle?.onGood())),
      videoTileDidUpdate: tileState =>
        this.guardCallback(generation, () => this.handleVideoTileUpdate(tileState)),
      videoTileWasRemoved: tileId =>
        this.guardCallback(generation, () => this.applyTileActions(this.tiles?.remove(tileId) ?? [])),
    };
    audioVideo.addObserver(this.observer);

    this.presenceCallback = (attendeeId, present) =>
      this.guardCallback(generation, () => this.handlePresence(attendeeId, present));
    audioVideo.realtimeSubscribeToAttendeeIdPresence(this.presenceCallback);

    this.localMuteCallback = muted =>
      this.guardCallback(generation, () =>
        this.emit({ type: muted ? 'localMuted' : 'localUnmuted', generation }),
      );
    audioVideo.realtimeSubscribeToMuteAndUnmuteLocalAudio(this.localMuteCallback);

    this.fatalCallback = () =>
      this.guardCallback(generation, () => {
        this.emit({ type: 'sessionError', generation, failureCode: 'session_stopped_fatal' });
        void this.cleanupSession();
      });
    audioVideo.realtimeSubscribeToFatalError(this.fatalCallback);

    this.activeSpeakerCallback = attendeeIds =>
      this.guardCallback(generation, () => {
        const attendeeId = attendeeIds.find(id => !id.includes('#content'));
        if (attendeeId) this.emit({ type: 'activeSpeaker', generation, attendeeId });
      });
    audioVideo.subscribeToActiveSpeakerDetector(
      new DefaultActiveSpeakerPolicy(),
      this.activeSpeakerCallback,
    );

    this.deviceObserver = {
      audioInputsChanged: () =>
        this.guardCallback(generation, () =>
          this.emit({ type: 'audioDeviceChanged', generation }),
        ),
      videoInputsChanged: () =>
        this.guardCallback(generation, () =>
          this.emit({ type: 'audioDeviceChanged', generation }),
        ),
      audioInputStreamEnded: () =>
        this.guardCallback(generation, () => void this.useListenOnlyInput(generation, 'device_not_readable')),
      videoInputStreamEnded: () =>
        this.guardCallback(generation, () => {
          this.cameraInputActive = false;
          this.emit({ type: 'cameraDisabled', generation, failureCode: 'device_not_readable' });
        }),
    };
    audioVideo.addDeviceChangeObserver(this.deviceObserver);
  }

  private async selectMicrophone(generation: number): Promise<void> {
    const session = this.requireSession(generation);
    try {
      const devices = await session.audioVideo.listAudioInputDevices();
      if (!this.isActive(generation)) return;
      const device = devices[0];
      if (!device) {
        await this.useListenOnlyInput(generation, 'device_not_found');
        return;
      }
      await session.audioVideo.startAudioInput(device.deviceId || 'default');
      if (this.isActive(generation)) this.emitMediaState({ type: 'microphoneEnabled', generation });
    } catch (error) {
      await this.useListenOnlyInput(generation, mapDeviceError(error, 'microphone'));
    }
  }

  private async useListenOnlyInput(
    generation: number,
    failureCode: BridgeFailureCode,
  ): Promise<void> {
    if (!this.isActive(generation)) return;
    try {
      await this.session?.audioVideo.startAudioInput(null);
    } catch {
      // Session startup still proceeds so remote audio can remain available.
    }
    if (this.isActive(generation)) {
      this.emitMediaState({ type: 'microphoneDisabled', generation, failureCode });
    }
  }

  private async selectCamera(generation: number, forceUpdate = false): Promise<void> {
    const session = this.requireSession(generation);
    try {
      const devices = await session.audioVideo.listVideoInputDevices(forceUpdate);
      if (!this.isActive(generation)) return;
      const selected =
        devices.find(device => device.deviceId === this.selectedCameraId) ?? devices[0];
      if (!selected) {
        this.cameraInputActive = false;
        this.emitMediaState({ type: 'cameraDisabled', generation, failureCode: 'device_not_found' });
        return;
      }
      await session.audioVideo.startVideoInput(selected.deviceId || 'default');
      if (!this.isActive(generation)) return;
      this.selectedCameraId = selected.deviceId;
      this.cameraInputActive = true;
      this.emitMediaState({ type: 'cameraEnabled', generation });
    } catch (error) {
      if (!this.isActive(generation)) return;
      this.cameraInputActive = false;
      this.emitMediaState({
        type: 'cameraDisabled',
        generation,
        failureCode: mapDeviceError(error, 'camera'),
      });
    }
  }

  private handlePresence(attendeeId: string, present: boolean): void {
    const event = this.attendees?.presence(attendeeId, present) ?? null;
    this.emitOptional(event);
    if (attendeeId.includes('#content')) return;
    const session = this.session;
    if (!session) return;
    if (present && this.attendees?.has(attendeeId) && !this.volumeCallbacks.has(attendeeId)) {
      const generation = this.activeGeneration;
      if (generation === null) return;
      const callback: VolumeIndicatorCallback = (id, volume, muted) =>
        this.guardCallback(generation, () => {
          const events = this.attendees?.volume(id, volume, muted, Date.now()) ?? [];
          for (const next of events) this.emit(next);
        });
      this.volumeCallbacks.set(attendeeId, callback);
      session.audioVideo.realtimeSubscribeToVolumeIndicator(attendeeId, callback);
    } else if (!present) {
      const callback = this.volumeCallbacks.get(attendeeId);
      if (callback) {
        session.audioVideo.realtimeUnsubscribeFromVolumeIndicator(attendeeId, callback);
        this.volumeCallbacks.delete(attendeeId);
      }
    }
  }

  private handleVideoTileUpdate(tileState: VideoTileState): void {
    this.applyTileActions(
      this.tiles?.update({
        tileId: tileState.tileId,
        localTile: tileState.localTile,
        isContent: tileState.isContent,
        boundAttendeeId: tileState.boundAttendeeId,
        paused: tileState.paused,
      }) ?? [],
    );
  }

  private applyTileActions(actions: TileAction[]): void {
    const session = this.session;
    if (!session) return;
    for (const action of actions) {
      if (action.kind === 'event') {
        this.emit(action.event);
      } else if (action.kind === 'unbind') {
        try {
          session.audioVideo.unbindVideoElement(action.tileId, true);
        } catch {
          // A concurrent SDK tile removal can make unbinding a no-op.
        }
      } else {
        this.bindVideoElement(action, false);
      }
    }
  }

  private bindVideoElement(
    action: Extract<TileAction, { readonly kind: 'bind' }>,
    retrying: boolean,
  ): void {
    const generation = this.activeGeneration;
    const session = this.session;
    if (generation === null || !session) return;
    const element = document.getElementById(action.elementId);
    if (!(element instanceof HTMLVideoElement)) return;
    element.autoplay = true;
    element.muted = true;
    element.playsInline = true;
    element.controls = false;
    try {
      session.audioVideo.bindVideoElement(action.tileId, element);
    } catch {
      if (retrying) return;
      setTimeout(() => {
        if (
          this.isActive(generation) &&
          this.session === session &&
          this.tiles?.selectedTileId(action.role) === action.tileId &&
          this.tiles.attachedElementId(action.role) === action.elementId
        ) {
          this.bindVideoElement(action, true);
        }
      }, 0);
    }
  }

  private attachVideoElement(generation: number, role: VideoRole, elementId: string): void {
    if (!this.isActive(generation) || elementId.trim().length === 0) return;
    this.applyTileActions(this.tiles?.attach(role, elementId) ?? []);
  }

  private handleSessionStopped(generation: number, status: MeetingSessionStatus): void {
    const statusCode = status.statusCode();
    if (statusCode === MeetingSessionStatusCode.Left) {
      this.emit({ type: 'audioSessionStopped', generation, statusCode });
      this.emit({ type: 'sessionStopped', generation, statusCode });
      void this.cleanupSession();
      return;
    }
    this.emit({
      type: 'sessionError',
      generation,
      statusCode,
      failureCode: 'session_stopped_fatal',
    });
    void this.cleanupSession();
  }

  private async createAndBindAudioElement(generation: number): Promise<void> {
    const session = this.requireSession(generation);
    const element = document.createElement('audio');
    element.autoplay = true;
    element.controls = false;
    element.hidden = true;
    element.setAttribute('aria-hidden', 'true');
    document.body.appendChild(element);
    this.audioElement = element;
    await session.audioVideo.bindAudioElement(element);
  }

  private async startAudioPlayback(generation: number): Promise<void> {
    const element = this.audioElement;
    if (!element || !this.isActive(generation)) return;
    try {
      await element.play();
      if (this.isActive(generation)) {
        this.audioGestureRetry?.dispose();
        this.audioGestureRetry = null;
        this.emit({ type: 'audioSessionStarted', generation });
      }
    } catch {
      if (this.isActive(generation)) {
        this.emit({
          type: 'audioSessionStarted',
          generation,
          failureCode: 'audio_playback_blocked',
        });
        this.audioGestureRetry?.dispose();
        this.audioGestureRetry = new AudioPlaybackGestureRetry(
          document,
          () => this.isActive(generation),
          () => element.play(),
          () => {
            this.audioGestureRetry = null;
            this.emit({ type: 'audioSessionStarted', generation });
          },
        );
        this.audioGestureRetry.install();
      }
    }
  }

  private requireSession(generation: number): DefaultMeetingSession {
    if (!this.isActive(generation) || !this.session) {
      throw new BridgeError('interop_failure', 'The requested meeting session is not active.');
    }
    return this.session;
  }

  private isActive(generation: number): boolean {
    return !this.disposed && this.activeGeneration === generation;
  }

  private emitOptional(event: BridgeEvent | null | undefined): void {
    if (event) this.emit(event);
  }

  private emitMediaState(event: BridgeEvent): void {
    const events = this.deferredMediaEvents.record(event, this.lifecycle?.hasStarted === true);
    for (const next of events) this.emit(next);
  }

  private emit(event: BridgeEvent): void {
    if (!this.isActive(event.generation)) return;
    try {
      this.eventHandler?.(event);
    } catch {
      // Dart handler failures must never escape into Chime realtime callbacks.
    }
  }

  private guardCallback(generation: number | null, callback: () => void): void {
    if (generation === null || !this.isActive(generation)) return;
    try {
      callback();
    } catch {
      this.emit({ type: 'sessionError', generation, failureCode: 'interop_failure' });
    }
  }

  private async cleanupSession(): Promise<void> {
    const session = this.session;
    const deviceController = this.deviceController;
    const audioElement = this.audioElement;
    const audioGestureRetry = this.audioGestureRetry;
    const observer = this.observer;
    const deviceObserver = this.deviceObserver;
    const presenceCallback = this.presenceCallback;
    const localMuteCallback = this.localMuteCallback;
    const fatalCallback = this.fatalCallback;
    const activeSpeakerCallback = this.activeSpeakerCallback;
    const volumeCallbacks = [...this.volumeCallbacks.entries()];
    const localTileId = this.tiles?.selectedTileId('local') ?? null;
    const remoteTileId = this.tiles?.selectedTileId('remote') ?? null;

    // Invalidate first: observer and promise completions from this point cannot
    // update a replacement Flutter meeting generation.
    this.activeGeneration = null;
    this.session = null;
    this.deviceController = null;
    this.audioElement = null;
    this.audioGestureRetry = null;
    this.observer = null;
    this.deviceObserver = null;
    this.presenceCallback = null;
    this.localMuteCallback = null;
    this.fatalCallback = null;
    this.activeSpeakerCallback = null;
    this.volumeCallbacks.clear();
    this.selectedCameraId = null;
    this.cameraInputActive = false;
    this.cameraRequested = true;
    this.deferredMediaEvents.clear();

    if (!session) {
      this.resetCoordinators();
      return;
    }
    const audioVideo = session.audioVideo;
    const cleanupSteps: Array<() => void | Promise<void>> = [
      () => audioGestureRetry?.dispose(),
      () => {
        if (activeSpeakerCallback) audioVideo.unsubscribeFromActiveSpeakerDetector(activeSpeakerCallback);
      },
      () => {
        if (presenceCallback) audioVideo.realtimeUnsubscribeToAttendeeIdPresence(presenceCallback);
      },
      () => {
        for (const [attendeeId, callback] of volumeCallbacks) {
          audioVideo.realtimeUnsubscribeFromVolumeIndicator(attendeeId, callback);
        }
      },
      () => {
        if (localMuteCallback) audioVideo.realtimeUnsubscribeToMuteAndUnmuteLocalAudio(localMuteCallback);
      },
      () => {
        if (fatalCallback) audioVideo.realtimeUnsubscribeToFatalError(fatalCallback);
      },
      () => {
        if (observer) audioVideo.removeObserver(observer);
      },
      () => {
        if (deviceObserver) audioVideo.removeDeviceChangeObserver(deviceObserver);
      },
      () => {
        if (localTileId !== null) audioVideo.unbindVideoElement(localTileId, true);
      },
      () => {
        if (remoteTileId !== null) audioVideo.unbindVideoElement(remoteTileId, true);
      },
      () => audioVideo.stopLocalVideoTile(),
      () => audioVideo.removeLocalVideoTile(),
      () => audioVideo.stopVideoInput(),
      () => audioVideo.stopAudioInput(),
      () => audioVideo.unbindAudioElement(),
      () => audioVideo.stop(),
      () => deviceController?.destroy(),
      () => session.destroy(),
      () => {
        if (audioElement) {
          audioElement.pause();
          audioElement.srcObject = null;
          audioElement.remove();
        }
      },
    ];
    for (const step of cleanupSteps) {
      try {
        await step();
      } catch {
        // Cleanup is best effort and continues after individual SDK failures.
      }
    }
    this.resetCoordinators();
  }

  private resetCoordinators(): void {
    this.lifecycle?.reset();
    this.attendees?.reset();
    this.tiles?.reset();
    this.lifecycle = null;
    this.attendees = null;
    this.tiles = null;
  }

  private async destroyDetachedSession(
    session: DefaultMeetingSession,
    deviceController: DefaultDeviceController,
  ): Promise<void> {
    try {
      session.audioVideo.stop();
    } catch {
      // Continue destroying the detached session.
    }
    try {
      await deviceController.destroy();
    } catch {
      // Continue destroying the detached session.
    }
    try {
      await session.destroy();
    } catch {
      // The stale session is already detached from bridge state.
    }
  }
}
