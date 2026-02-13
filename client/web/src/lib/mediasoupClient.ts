/**
 * MediasoupManager — wraps mediasoup-client Device, Transports, Producers, Consumers.
 */

import { Device } from "mediasoup-client";
import type { Transport, Producer, Consumer, RtpCapabilities } from "mediasoup-client/types";
import { pushVoiceEvent } from "../api/voiceSocket.ts";

/* eslint-disable @typescript-eslint/no-explicit-any */

export class MediasoupManager {
  #device: Device;
  #sendTransport: Transport | null = null;
  #recvTransport: Transport | null = null;
  #producers = new Map<string, Producer>();
  #consumers = new Map<string, Consumer>();

  constructor() {
    this.#device = new Device();
  }

  async loadDevice(rtpCapabilities: RtpCapabilities): Promise<void> {
    if (!this.#device.loaded) {
      await this.#device.load({ routerRtpCapabilities: rtpCapabilities });
    }
  }

  get rtpCapabilities(): RtpCapabilities {
    return this.#device.rtpCapabilities;
  }

  get loaded(): boolean {
    return this.#device.loaded;
  }

  createSendTransport(params: {
    id: string;
    iceParameters: any;
    iceCandidates: any[];
    dtlsParameters: any;
  }): Transport {
    this.#sendTransport = this.#device.createSendTransport(params);

    this.#sendTransport.on(
      "connect",
      ({ dtlsParameters }: any, callback: any, errback: any) => {
        pushVoiceEvent("connect_transport", {
          transportId: this.#sendTransport!.id,
          dtlsParameters,
        })
          .then(() => callback())
          .catch(errback);
      },
    );

    this.#sendTransport.on(
      "produce",
      ({ kind, rtpParameters, appData }: any, callback: any, errback: any) => {
        pushVoiceEvent("produce", {
          kind,
          rtpParameters,
          appData,
        })
          .then((resp: { id: string }) => callback({ id: resp.id }))
          .catch(errback);
      },
    );

    return this.#sendTransport;
  }

  createRecvTransport(params: {
    id: string;
    iceParameters: any;
    iceCandidates: any[];
    dtlsParameters: any;
  }): Transport {
    this.#recvTransport = this.#device.createRecvTransport(params);

    this.#recvTransport.on(
      "connect",
      ({ dtlsParameters }: any, callback: any, errback: any) => {
        pushVoiceEvent("connect_transport", {
          transportId: this.#recvTransport!.id,
          dtlsParameters,
        })
          .then(() => callback())
          .catch(errback);
      },
    );

    return this.#recvTransport;
  }

  async produce(
    track: MediaStreamTrack,
    appData?: Record<string, unknown>,
  ): Promise<Producer> {
    if (!this.#sendTransport) {
      throw new Error("Send transport not created");
    }

    const producer = await this.#sendTransport.produce({
      track,
      appData,
      ...(track.kind === "audio"
        ? {
            codecOptions: {
              opusStereo: true,
              opusDtx: true,
            },
          }
        : {
            encodings: [
              { maxBitrate: 100_000, scaleResolutionDownBy: 4 },
              { maxBitrate: 300_000, scaleResolutionDownBy: 2 },
              { maxBitrate: 900_000 },
            ],
            codecOptions: {
              videoGoogleStartBitrate: 1000,
            },
          }),
    });

    this.#producers.set(producer.id, producer);
    return producer;
  }

  async consume(params: {
    producerId: string;
    rtpCapabilities: RtpCapabilities;
  }): Promise<Consumer> {
    const resp = await pushVoiceEvent("consume", {
      producerId: params.producerId,
      rtpCapabilities: params.rtpCapabilities,
    });

    if (!this.#recvTransport) {
      throw new Error("Recv transport not created");
    }

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

  getProducer(id: string): Producer | undefined {
    return this.#producers.get(id);
  }

  getProducerByKind(kind: string): Producer | undefined {
    for (const producer of this.#producers.values()) {
      if (producer.kind === kind && !producer.closed) {
        return producer;
      }
    }
    return undefined;
  }

  closeProducer(id: string): void {
    const producer = this.#producers.get(id);
    if (producer) {
      producer.close();
      this.#producers.delete(id);
    }
  }

  closeConsumer(id: string): void {
    const consumer = this.#consumers.get(id);
    if (consumer) {
      consumer.close();
      this.#consumers.delete(id);
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

  get allConsumers(): Map<string, Consumer> {
    return this.#consumers;
  }
}

/* eslint-enable @typescript-eslint/no-explicit-any */
