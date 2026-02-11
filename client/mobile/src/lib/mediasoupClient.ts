/**
 * mediasoup-client wrapper for React Native.
 * Uses react-native-webrtc handler for WebRTC primitives.
 */

import { Device } from "mediasoup-client";
import type {
  Transport,
  Producer,
  Consumer,
  RtpCapabilities,
} from "mediasoup-client/lib/types";

// React Native handler for mediasoup
import { ReactNativeUnifiedPlan } from "mediasoup-client/lib/handlers/ReactNativeUnifiedPlan";

export class MediasoupManager {
  #device: Device;
  #sendTransport: Transport | null = null;
  #recvTransport: Transport | null = null;
  #producers = new Map<string, Producer>();
  #consumers = new Map<string, Consumer>();

  constructor() {
    this.#device = new Device({ handlerFactory: ReactNativeUnifiedPlan.createFactory() });
  }

  get loaded(): boolean {
    return this.#device.loaded;
  }

  get rtpCapabilities(): RtpCapabilities {
    return this.#device.rtpCapabilities;
  }

  get allConsumers(): Map<string, Consumer> {
    return this.#consumers;
  }

  async loadDevice(rtpCapabilities: RtpCapabilities): Promise<void> {
    if (!this.#device.loaded) {
      await this.#device.load({ routerRtpCapabilities: rtpCapabilities });
    }
  }

  createSendTransport(params: {
    id: string;
    iceParameters: unknown;
    iceCandidates: unknown[];
    dtlsParameters: unknown;
  }): void {
    this.#sendTransport = this.#device.createSendTransport({
      id: params.id,
      iceParameters: params.iceParameters as any,
      iceCandidates: params.iceCandidates as any,
      dtlsParameters: params.dtlsParameters as any,
    });

    this.#sendTransport.on(
      "connect",
      ({ dtlsParameters }: any, callback: () => void) => {
        import("../api/voiceSocket").then(({ pushVoiceEvent }) => {
          pushVoiceEvent("connect_transport", {
            transportId: this.#sendTransport!.id,
            dtlsParameters,
          })
            .then(() => callback())
            .catch(() => callback());
        });
      },
    );

    this.#sendTransport.on(
      "produce",
      ({ kind, rtpParameters, appData }: any, callback: (arg: { id: string }) => void) => {
        import("../api/voiceSocket").then(({ pushVoiceEvent }) => {
          pushVoiceEvent("produce", { kind, rtpParameters, appData })
            .then((resp: any) => callback({ id: resp.id }))
            .catch(() => {});
        });
      },
    );
  }

  createRecvTransport(params: {
    id: string;
    iceParameters: unknown;
    iceCandidates: unknown[];
    dtlsParameters: unknown;
  }): void {
    this.#recvTransport = this.#device.createRecvTransport({
      id: params.id,
      iceParameters: params.iceParameters as any,
      iceCandidates: params.iceCandidates as any,
      dtlsParameters: params.dtlsParameters as any,
    });

    this.#recvTransport.on(
      "connect",
      ({ dtlsParameters }: any, callback: () => void) => {
        import("../api/voiceSocket").then(({ pushVoiceEvent }) => {
          pushVoiceEvent("connect_transport", {
            transportId: this.#recvTransport!.id,
            dtlsParameters,
          })
            .then(() => callback())
            .catch(() => callback());
        });
      },
    );
  }

  async produce(
    track: MediaStreamTrack,
    appData: Record<string, unknown> = {},
  ): Promise<Producer> {
    if (!this.#sendTransport) throw new Error("No send transport");

    const producer = await this.#sendTransport.produce({
      track,
      appData,
      codecOptions: {
        opusStereo: false,
        opusDtx: true,
      },
    });

    this.#producers.set(producer.id, producer);
    return producer;
  }

  async consume(params: {
    producerId: string;
    rtpCapabilities: RtpCapabilities;
  }): Promise<Consumer> {
    if (!this.#recvTransport) throw new Error("No recv transport");

    const { pushVoiceEvent } = await import("../api/voiceSocket");
    const resp = await pushVoiceEvent("consume", {
      producerId: params.producerId,
      rtpCapabilities: params.rtpCapabilities,
    }) as any;

    const consumer = await this.#recvTransport.consume({
      id: resp.id,
      producerId: resp.producerId,
      kind: resp.kind,
      rtpParameters: resp.rtpParameters,
    });

    this.#consumers.set(consumer.id, consumer);

    // Resume consumer on server
    await pushVoiceEvent("resume_consumer", { consumerId: consumer.id });

    return consumer;
  }

  getProducerByKind(kind: string): Producer | undefined {
    for (const producer of this.#producers.values()) {
      if (producer.kind === kind) return producer;
    }
    return undefined;
  }

  closeProducer(producerId: string): void {
    const producer = this.#producers.get(producerId);
    if (producer) {
      producer.close();
      this.#producers.delete(producerId);
    }
  }

  closeConsumer(consumerId: string): void {
    const consumer = this.#consumers.get(consumerId);
    if (consumer) {
      consumer.close();
      this.#consumers.delete(consumerId);
    }
  }

  close(): void {
    for (const producer of this.#producers.values()) {
      producer.close();
    }
    this.#producers.clear();

    for (const consumer of this.#consumers.values()) {
      consumer.close();
    }
    this.#consumers.clear();

    this.#sendTransport?.close();
    this.#recvTransport?.close();
    this.#sendTransport = null;
    this.#recvTransport = null;
  }
}
