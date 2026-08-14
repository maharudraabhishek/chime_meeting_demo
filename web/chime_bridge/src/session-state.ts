import type { BridgeEvent, VideoRole } from './bridge-types';

export class DeferredMediaEvents {
  private readonly events: BridgeEvent[] = [];

  record(event: BridgeEvent, sessionStarted: boolean): BridgeEvent[] {
    if (sessionStarted) return [event];
    this.events.push(event);
    return [];
  }

  flush(): BridgeEvent[] {
    return this.events.splice(0);
  }

  clear(): void {
    this.events.length = 0;
  }
}

export class AudioPlaybackGestureRetry {
  private listener: EventListener | null = null;

  constructor(
    private readonly target: EventTarget,
    private readonly isActive: () => boolean,
    private readonly retry: () => Promise<void>,
    private readonly recovered: () => void,
  ) {}

  install(): void {
    if (this.listener) return;
    this.listener = () => {
      this.dispose();
      if (!this.isActive()) return;
      void this.retry()
        .then(() => {
          if (this.isActive()) this.recovered();
        })
        .catch(() => undefined);
    };
    this.target.addEventListener('pointerdown', this.listener, { capture: true });
    this.target.addEventListener('keydown', this.listener, { capture: true });
  }

  dispose(): void {
    if (!this.listener) return;
    this.target.removeEventListener('pointerdown', this.listener, { capture: true });
    this.target.removeEventListener('keydown', this.listener, { capture: true });
    this.listener = null;
  }
}

export function isMicrophoneEnabled(muted: boolean): boolean {
  return !muted;
}

export class LifecycleEventCoordinator {
  private started = false;
  private reconnecting = false;
  private poor = false;

  constructor(private readonly generation: number) {}

  get hasStarted(): boolean {
    return this.started;
  }

  onStartConnecting(reconnecting: boolean): BridgeEvent | null {
    if (!reconnecting || this.reconnecting) {
      return null;
    }
    this.reconnecting = true;
    return { type: 'sessionReconnecting', generation: this.generation };
  }

  onDidStart(): BridgeEvent | null {
    if (this.reconnecting) {
      this.started = true;
      this.reconnecting = false;
      this.poor = false;
      return { type: 'connectionRecovered', generation: this.generation };
    }
    if (this.started) {
      return null;
    }
    this.started = true;
    return { type: 'sessionStarted', generation: this.generation };
  }

  onPoor(): BridgeEvent | null {
    if (this.poor) {
      return null;
    }
    this.poor = true;
    return { type: 'connectionPoor', generation: this.generation };
  }

  onGood(): BridgeEvent | null {
    if (!this.poor || this.reconnecting) {
      return null;
    }
    this.poor = false;
    return { type: 'connectionRecovered', generation: this.generation };
  }

  reset(): void {
    this.started = false;
    this.reconnecting = false;
    this.poor = false;
  }
}

export interface TileSnapshot {
  readonly tileId: number | null;
  readonly localTile: boolean;
  readonly isContent: boolean;
  readonly boundAttendeeId: string | null;
  readonly paused: boolean;
}

export type TileAction =
  | { readonly kind: 'bind'; readonly role: VideoRole; readonly tileId: number; readonly elementId: string }
  | { readonly kind: 'unbind'; readonly role: VideoRole; readonly tileId: number }
  | { readonly kind: 'event'; readonly event: BridgeEvent };

interface SelectedTile {
  tileId: number;
  attendeeId: string | null;
  paused: boolean;
}

export class VideoTileCoordinator {
  private readonly elements: Partial<Record<VideoRole, string>> = {};
  private readonly tiles: Partial<Record<VideoRole, SelectedTile>> = {};

  constructor(private readonly generation: number) {}

  attach(role: VideoRole, elementId: string): TileAction[] {
    this.elements[role] = elementId;
    const tile = this.tiles[role];
    return tile ? [{ kind: 'bind', role, tileId: tile.tileId, elementId }] : [];
  }

  detach(role: VideoRole): TileAction[] {
    delete this.elements[role];
    const tile = this.tiles[role];
    return tile ? [{ kind: 'unbind', role, tileId: tile.tileId }] : [];
  }

  update(snapshot: TileSnapshot): TileAction[] {
    if (snapshot.tileId === null || snapshot.isContent) {
      return [];
    }
    const role: VideoRole = snapshot.localTile ? 'local' : 'remote';
    if (role === 'remote' && !snapshot.boundAttendeeId) {
      return [];
    }

    const actions: TileAction[] = [];
    const previous = this.tiles[role];
    if (previous?.tileId === snapshot.tileId) {
      if (previous.paused !== snapshot.paused) {
        previous.paused = snapshot.paused;
        actions.push({ kind: 'event', event: this.pauseEvent(role, snapshot.paused) });
      }
      return actions;
    }

    if (previous) {
      actions.push({ kind: 'unbind', role, tileId: previous.tileId });
    }
    this.tiles[role] = {
      tileId: snapshot.tileId,
      attendeeId: snapshot.boundAttendeeId,
      paused: snapshot.paused,
    };
    actions.push({ kind: 'event', event: this.availableEvent(role, snapshot.boundAttendeeId) });
    const elementId = this.elements[role];
    if (elementId) {
      actions.push({ kind: 'bind', role, tileId: snapshot.tileId, elementId });
    }
    if (snapshot.paused) {
      actions.push({ kind: 'event', event: this.pauseEvent(role, true) });
    }
    return actions;
  }

  remove(tileId: number): TileAction[] {
    const role = this.roleForTile(tileId);
    if (!role) {
      return [];
    }
    const selected = this.tiles[role];
    if (!selected || selected.tileId !== tileId) {
      return [];
    }
    delete this.tiles[role];
    return [
      { kind: 'unbind', role, tileId },
      { kind: 'event', event: this.removedEvent(role, selected.attendeeId) },
    ];
  }

  selectedTileId(role: VideoRole): number | null {
    return this.tiles[role]?.tileId ?? null;
  }

  attachedElementId(role: VideoRole): string | null {
    return this.elements[role] ?? null;
  }

  reset(): void {
    delete this.elements.local;
    delete this.elements.remote;
    delete this.tiles.local;
    delete this.tiles.remote;
  }

  private roleForTile(tileId: number): VideoRole | null {
    if (this.tiles.local?.tileId === tileId) return 'local';
    if (this.tiles.remote?.tileId === tileId) return 'remote';
    return null;
  }

  private availableEvent(role: VideoRole, attendeeId: string | null): BridgeEvent {
    return {
      type: role === 'local' ? 'localVideoAvailable' : 'remoteVideoAvailable',
      generation: this.generation,
      ...(attendeeId ? { attendeeId } : {}),
    };
  }

  private removedEvent(role: VideoRole, attendeeId: string | null): BridgeEvent {
    return {
      type: role === 'local' ? 'localVideoRemoved' : 'remoteVideoRemoved',
      generation: this.generation,
      ...(attendeeId ? { attendeeId } : {}),
    };
  }

  private pauseEvent(role: VideoRole, paused: boolean): BridgeEvent {
    return {
      type:
        role === 'local'
          ? paused
            ? 'localVideoPaused'
            : 'localVideoResumed'
          : paused
            ? 'remoteVideoPaused'
            : 'remoteVideoResumed',
      generation: this.generation,
    };
  }
}

export class RemoteAttendeeCoordinator {
  private readonly present = new Set<string>();
  private readonly muted = new Map<string, boolean>();
  private readonly lastVolumeAt = new Map<string, number>();

  constructor(
    private readonly generation: number,
    private readonly localAttendeeId: string,
  ) {}

  presence(attendeeId: string, present: boolean): BridgeEvent | null {
    if (this.isIgnored(attendeeId)) {
      return null;
    }
    if (present) {
      if (this.present.has(attendeeId)) return null;
      this.present.add(attendeeId);
      return { type: 'participantJoined', generation: this.generation, attendeeId };
    }
    if (!this.present.delete(attendeeId)) return null;
    this.muted.delete(attendeeId);
    this.lastVolumeAt.delete(attendeeId);
    return { type: 'participantLeft', generation: this.generation, attendeeId };
  }

  volume(
    attendeeId: string,
    volume: number | null,
    muted: boolean | null,
    nowMs: number,
  ): BridgeEvent[] {
    if (!this.present.has(attendeeId) || this.isIgnored(attendeeId)) {
      return [];
    }
    const events: BridgeEvent[] = [];
    if (muted !== null) {
      const previousMuted = this.muted.get(attendeeId);
      this.muted.set(attendeeId, muted);
      if (previousMuted !== undefined && previousMuted !== muted) {
        events.push({
          type: muted ? 'remoteMuted' : 'remoteUnmuted',
          generation: this.generation,
          attendeeId,
        });
      }
    }
    const lastAt = this.lastVolumeAt.get(attendeeId);
    if (volume !== null && (lastAt === undefined || nowMs - lastAt >= 1000)) {
      this.lastVolumeAt.set(attendeeId, nowMs);
      events.push({ type: 'volumeLevel', generation: this.generation, attendeeId, volume });
    }
    return events;
  }

  has(attendeeId: string): boolean {
    return this.present.has(attendeeId);
  }

  reset(): void {
    this.present.clear();
    this.muted.clear();
    this.lastVolumeAt.clear();
  }

  private isIgnored(attendeeId: string): boolean {
    return attendeeId === this.localAttendeeId || attendeeId.includes('#content');
  }
}

export function nextCameraDevice(
  devices: readonly MediaDeviceInfo[],
  currentDeviceId: string | null,
): MediaDeviceInfo | null {
  if (devices.length < 2) return null;
  const currentIndex = devices.findIndex(device => device.deviceId === currentDeviceId);
  return devices[(currentIndex + 1 + devices.length) % devices.length] ?? null;
}
