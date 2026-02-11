import type {
  Router,
  WebRtcTransport,
  WebRtcTransportOptions,
  Producer,
  ProducerOptions,
  Consumer,
  ConsumerOptions,
  DtlsParameters,
  RtpCapabilities,
  MediaKind,
  RtpParameters,
} from "mediasoup/types";
import type { WorkerPool } from "./workers.js";
import { config } from "./config.js";

export interface Peer {
  userId: string;
  sendTransport?: WebRtcTransport;
  recvTransport?: WebRtcTransport;
  producers: Map<string, Producer>;
  consumers: Map<string, Consumer>;
}

export interface Room {
  channelId: string;
  router: Router;
  peers: Map<string, Peer>;
}

export class RoomManager {
  private rooms = new Map<string, Room>();

  constructor(private workerPool: WorkerPool) {}

  async createRoom(channelId: string): Promise<Room> {
    if (this.rooms.has(channelId)) {
      return this.rooms.get(channelId)!;
    }

    const worker = this.workerPool.getNextWorker();
    const router = await worker.createRouter({
      mediaCodecs: config.mediaCodecs,
    });

    const room: Room = { channelId, router, peers: new Map() };
    this.rooms.set(channelId, room);
    return room;
  }

  getRoom(channelId: string): Room | undefined {
    return this.rooms.get(channelId);
  }

  async destroyRoom(channelId: string): Promise<boolean> {
    const room = this.rooms.get(channelId);
    if (!room) return false;

    for (const peer of room.peers.values()) {
      this.closePeer(peer);
    }

    room.router.close();
    this.rooms.delete(channelId);
    return true;
  }

  getRtpCapabilities(channelId: string): RtpCapabilities | undefined {
    return this.rooms.get(channelId)?.router.rtpCapabilities;
  }

  addPeer(channelId: string, userId: string): Peer | undefined {
    const room = this.rooms.get(channelId);
    if (!room) return undefined;

    if (room.peers.has(userId)) {
      return room.peers.get(userId)!;
    }

    const peer: Peer = {
      userId,
      producers: new Map(),
      consumers: new Map(),
    };
    room.peers.set(userId, peer);
    return peer;
  }

  removePeer(channelId: string, userId: string): boolean {
    const room = this.rooms.get(channelId);
    if (!room) return false;

    const peer = room.peers.get(userId);
    if (!peer) return false;

    this.closePeer(peer);
    room.peers.delete(userId);

    // Auto-destroy empty rooms
    if (room.peers.size === 0) {
      room.router.close();
      this.rooms.delete(channelId);
    }

    return true;
  }

  private closePeer(peer: Peer): void {
    for (const consumer of peer.consumers.values()) {
      consumer.close();
    }
    for (const producer of peer.producers.values()) {
      producer.close();
    }
    peer.sendTransport?.close();
    peer.recvTransport?.close();
  }

  async createWebRtcTransport(
    channelId: string,
    userId: string,
    direction: "send" | "recv"
  ): Promise<WebRtcTransport | undefined> {
    const room = this.rooms.get(channelId);
    if (!room) return undefined;

    const peer = room.peers.get(userId);
    if (!peer) return undefined;

    const transportOptions: WebRtcTransportOptions = {
      listenInfos: [
        {
          protocol: "udp",
          ip: config.mediasoup.listenIp,
          announcedAddress: config.mediasoup.announcedIp,
        },
        {
          protocol: "tcp",
          ip: config.mediasoup.listenIp,
          announcedAddress: config.mediasoup.announcedIp,
        },
      ],
      initialAvailableOutgoingBitrate:
        config.webRtcTransport.initialAvailableOutgoingBitrate,
    };

    const transport = await room.router.createWebRtcTransport(transportOptions);

    if (config.webRtcTransport.maxIncomingBitrate) {
      await transport.setMaxIncomingBitrate(
        config.webRtcTransport.maxIncomingBitrate
      );
    }

    if (direction === "send") {
      peer.sendTransport = transport;
    } else {
      peer.recvTransport = transport;
    }

    return transport;
  }

  async connectTransport(
    channelId: string,
    transportId: string,
    dtlsParameters: DtlsParameters
  ): Promise<boolean> {
    const room = this.rooms.get(channelId);
    if (!room) return false;

    for (const peer of room.peers.values()) {
      const transport =
        peer.sendTransport?.id === transportId
          ? peer.sendTransport
          : peer.recvTransport?.id === transportId
            ? peer.recvTransport
            : undefined;

      if (transport) {
        await transport.connect({ dtlsParameters });
        return true;
      }
    }

    return false;
  }

  async produce(
    channelId: string,
    userId: string,
    kind: MediaKind,
    rtpParameters: RtpParameters,
    appData?: Record<string, unknown>
  ): Promise<Producer | undefined> {
    const room = this.rooms.get(channelId);
    if (!room) return undefined;

    const peer = room.peers.get(userId);
    if (!peer?.sendTransport) return undefined;

    const producer = await peer.sendTransport.produce({
      kind,
      rtpParameters,
      appData: appData || {},
    } as ProducerOptions);

    peer.producers.set(producer.id, producer);
    return producer;
  }

  async consume(
    channelId: string,
    consumerUserId: string,
    producerId: string,
    rtpCapabilities: RtpCapabilities
  ): Promise<Consumer | undefined> {
    const room = this.rooms.get(channelId);
    if (!room) return undefined;

    const peer = room.peers.get(consumerUserId);
    if (!peer?.recvTransport) return undefined;

    if (!room.router.canConsume({ producerId, rtpCapabilities })) {
      return undefined;
    }

    const consumer = await peer.recvTransport.consume({
      producerId,
      rtpCapabilities,
      paused: true,
    } as ConsumerOptions);

    peer.consumers.set(consumer.id, consumer);
    return consumer;
  }

  async resumeConsumer(
    channelId: string,
    consumerId: string
  ): Promise<boolean> {
    const room = this.rooms.get(channelId);
    if (!room) return false;

    for (const peer of room.peers.values()) {
      const consumer = peer.consumers.get(consumerId);
      if (consumer) {
        await consumer.resume();
        return true;
      }
    }

    return false;
  }

  /**
   * Set the preferred spatial layer for a consumer based on bandwidth.
   * Layer 0 = lowest quality, layer 2 = highest quality (simulcast).
   */
  async setConsumerPreferredLayer(
    channelId: string,
    consumerId: string,
    spatialLayer: number,
    temporalLayer?: number
  ): Promise<boolean> {
    const room = this.rooms.get(channelId);
    if (!room) return false;

    for (const peer of room.peers.values()) {
      const consumer = peer.consumers.get(consumerId);
      if (consumer) {
        await consumer.setPreferredLayers({
          spatialLayer,
          temporalLayer: temporalLayer ?? spatialLayer,
        });
        return true;
      }
    }

    return false;
  }

  getProducer(
    channelId: string,
    producerId: string
  ): Producer | undefined {
    const room = this.rooms.get(channelId);
    if (!room) return undefined;

    for (const peer of room.peers.values()) {
      const producer = peer.producers.get(producerId);
      if (producer) return producer;
    }

    return undefined;
  }

  listProducers(
    channelId: string,
    excludeUserId?: string
  ): Array<{ producerId: string; userId: string; kind: MediaKind; appData: Record<string, unknown> }> {
    const room = this.rooms.get(channelId);
    if (!room) return [];

    const result: Array<{ producerId: string; userId: string; kind: MediaKind; appData: Record<string, unknown> }> = [];
    for (const [userId, peer] of room.peers) {
      if (excludeUserId && userId === excludeUserId) continue;
      for (const [producerId, producer] of peer.producers) {
        result.push({
          producerId,
          userId,
          kind: producer.kind,
          appData: producer.appData as Record<string, unknown>,
        });
      }
    }
    return result;
  }

  get roomCount(): number {
    return this.rooms.size;
  }

  get stats(): { rooms: number; peers: number } {
    let peers = 0;
    for (const room of this.rooms.values()) {
      peers += room.peers.size;
    }
    return { rooms: this.rooms.size, peers };
  }
}
