declare module "mediasoup-client" {
  import type {
    RtpCapabilities,
    Transport,
    Producer,
    Consumer,
  } from "mediasoup-client/lib/types";

  export class Device {
    constructor(opts?: { handlerFactory?: unknown });
    readonly loaded: boolean;
    readonly rtpCapabilities: RtpCapabilities;
    load(opts: { routerRtpCapabilities: RtpCapabilities }): Promise<void>;
    createSendTransport(params: {
      id: string;
      iceParameters: unknown;
      iceCandidates: unknown[];
      dtlsParameters: unknown;
    }): Transport;
    createRecvTransport(params: {
      id: string;
      iceParameters: unknown;
      iceCandidates: unknown[];
      dtlsParameters: unknown;
    }): Transport;
  }
}

declare module "mediasoup-client/lib/types" {
  export interface RtpCapabilities {
    codecs?: unknown[];
    headerExtensions?: unknown[];
  }

  export interface Transport {
    readonly id: string;
    readonly closed: boolean;
    close(): void;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    on(event: string, listener: (...args: any[]) => void): void;
    produce(opts: {
      track: MediaStreamTrack;
      appData?: Record<string, unknown>;
      codecOptions?: Record<string, unknown>;
    }): Promise<Producer>;
    consume(opts: {
      id: string;
      producerId: string;
      kind: string;
      rtpParameters: unknown;
    }): Promise<Consumer>;
  }

  export interface Producer {
    readonly id: string;
    readonly kind: string;
    readonly closed: boolean;
    close(): void;
  }

  export interface Consumer {
    readonly id: string;
    readonly kind: string;
    readonly closed: boolean;
    close(): void;
    readonly track: MediaStreamTrack;
  }

  export type HandlerFactory = () => unknown;
}

declare module "mediasoup-client/lib/handlers/ReactNativeUnifiedPlan" {
  import type { HandlerFactory } from "mediasoup-client/lib/types";
  export class ReactNativeUnifiedPlan {
    static createFactory(): HandlerFactory;
  }
}
