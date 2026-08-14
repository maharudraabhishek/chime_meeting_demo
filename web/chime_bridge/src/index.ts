import type { ChimeWebBridge } from './bridge-types';
import { ChimeWebSession } from './chime-web-session';

const bridge: ChimeWebBridge = new ChimeWebSession();

Object.defineProperty(globalThis, 'chimeWebBridge', {
  value: bridge,
  configurable: false,
  enumerable: false,
  writable: false,
});

