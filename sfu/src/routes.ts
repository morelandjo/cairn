import type { FastifyInstance } from "fastify";
import type { RoomManager } from "./rooms.js";
import type { WorkerPool } from "./workers.js";

export function registerRoutes(
  app: FastifyInstance,
  roomManager: RoomManager,
  workerPool: WorkerPool
): void {
  // --- Health ---
  app.get("/health", async () => {
    const stats = roomManager.stats;
    return {
      status: "healthy",
      version: "0.1.0",
      workers: workerPool.count,
      rooms: stats.rooms,
      peers: stats.peers,
    };
  });

  // --- Rooms ---
  app.post<{ Body: { channelId: string } }>("/rooms", async (request, reply) => {
    const { channelId } = request.body;
    if (!channelId) {
      return reply.code(400).send({ error: "channelId required" });
    }

    const room = await roomManager.createRoom(channelId);
    return {
      channelId: room.channelId,
      rtpCapabilities: room.router.rtpCapabilities,
    };
  });

  app.delete<{ Params: { channelId: string } }>(
    "/rooms/:channelId",
    async (request, reply) => {
      const destroyed = await roomManager.destroyRoom(request.params.channelId);
      if (!destroyed) {
        return reply.code(404).send({ error: "Room not found" });
      }
      return { ok: true };
    }
  );

  app.get<{ Params: { channelId: string } }>(
    "/rooms/:channelId/rtp-capabilities",
    async (request, reply) => {
      const caps = roomManager.getRtpCapabilities(request.params.channelId);
      if (!caps) {
        return reply.code(404).send({ error: "Room not found" });
      }
      return caps;
    }
  );

  // --- Peers ---
  app.post<{ Params: { channelId: string }; Body: { userId: string } }>(
    "/rooms/:channelId/peers",
    async (request, reply) => {
      const { channelId } = request.params;
      const { userId } = request.body;
      if (!userId) {
        return reply.code(400).send({ error: "userId required" });
      }

      const peer = roomManager.addPeer(channelId, userId);
      if (!peer) {
        return reply.code(404).send({ error: "Room not found" });
      }
      return { userId: peer.userId };
    }
  );

  app.delete<{ Params: { channelId: string; userId: string } }>(
    "/rooms/:channelId/peers/:userId",
    async (request, reply) => {
      const { channelId, userId } = request.params;
      const removed = roomManager.removePeer(channelId, userId);
      if (!removed) {
        return reply.code(404).send({ error: "Peer not found" });
      }
      return { ok: true };
    }
  );

  // --- Transports ---
  app.post<{ Params: { channelId: string; userId: string } }>(
    "/rooms/:channelId/peers/:userId/send-transport",
    async (request, reply) => {
      const { channelId, userId } = request.params;
      const transport = await roomManager.createWebRtcTransport(
        channelId,
        userId,
        "send"
      );
      if (!transport) {
        return reply.code(404).send({ error: "Peer not found" });
      }
      return {
        id: transport.id,
        iceParameters: transport.iceParameters,
        iceCandidates: transport.iceCandidates,
        dtlsParameters: transport.dtlsParameters,
      };
    }
  );

  app.post<{ Params: { channelId: string; userId: string } }>(
    "/rooms/:channelId/peers/:userId/recv-transport",
    async (request, reply) => {
      const { channelId, userId } = request.params;
      const transport = await roomManager.createWebRtcTransport(
        channelId,
        userId,
        "recv"
      );
      if (!transport) {
        return reply.code(404).send({ error: "Peer not found" });
      }
      return {
        id: transport.id,
        iceParameters: transport.iceParameters,
        iceCandidates: transport.iceCandidates,
        dtlsParameters: transport.dtlsParameters,
      };
    }
  );

  app.post<{
    Params: { channelId: string; transportId: string };
    Body: { dtlsParameters: unknown };
  }>(
    "/rooms/:channelId/transports/:transportId/connect",
    async (request, reply) => {
      const { channelId, transportId } = request.params;
      const { dtlsParameters } = request.body;
      if (!dtlsParameters) {
        return reply.code(400).send({ error: "dtlsParameters required" });
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const connected = await roomManager.connectTransport(
        channelId,
        transportId,
        dtlsParameters as any
      );
      if (!connected) {
        return reply.code(404).send({ error: "Transport not found" });
      }
      return { ok: true };
    }
  );

  // --- Producers ---
  app.post<{
    Params: { channelId: string; userId: string };
    Body: { kind: string; rtpParameters: unknown; appData?: Record<string, unknown> };
  }>(
    "/rooms/:channelId/peers/:userId/produce",
    async (request, reply) => {
      const { channelId, userId } = request.params;
      const { kind, rtpParameters, appData } = request.body;
      if (!kind || !rtpParameters) {
        return reply.code(400).send({ error: "kind and rtpParameters required" });
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const producer = await roomManager.produce(
        channelId,
        userId,
        kind as any,
        rtpParameters as any,
        appData
      );
      if (!producer) {
        return reply.code(404).send({ error: "Peer or send transport not found" });
      }
      return { id: producer.id, kind: producer.kind };
    }
  );

  app.post<{
    Params: { channelId: string; producerId: string };
    Body: { action: "pause" | "resume" | "close" };
  }>(
    "/rooms/:channelId/producers/:producerId/:action",
    async (request, reply) => {
      const { channelId, producerId, action } = request.params as {
        channelId: string;
        producerId: string;
        action: string;
      };
      const producer = roomManager.getProducer(channelId, producerId);
      if (!producer) {
        return reply.code(404).send({ error: "Producer not found" });
      }

      switch (action) {
        case "pause":
          await producer.pause();
          break;
        case "resume":
          await producer.resume();
          break;
        case "close":
          producer.close();
          break;
        default:
          return reply.code(400).send({ error: "Invalid action" });
      }

      return { ok: true };
    }
  );

  // --- Consumers ---
  app.post<{
    Params: { channelId: string };
    Body: {
      consumerUserId: string;
      producerId: string;
      rtpCapabilities: unknown;
    };
  }>("/rooms/:channelId/consumers", async (request, reply) => {
    const { channelId } = request.params;
    const { consumerUserId, producerId, rtpCapabilities } = request.body;
    if (!consumerUserId || !producerId || !rtpCapabilities) {
      return reply
        .code(400)
        .send({ error: "consumerUserId, producerId, rtpCapabilities required" });
    }

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const consumer = await roomManager.consume(
      channelId,
      consumerUserId,
      producerId,
      rtpCapabilities as any
    );
    if (!consumer) {
      return reply
        .code(404)
        .send({ error: "Cannot consume (peer/transport/compatibility)" });
    }

    return {
      id: consumer.id,
      producerId: consumer.producerId,
      kind: consumer.kind,
      rtpParameters: consumer.rtpParameters,
    };
  });

  app.post<{ Params: { channelId: string; consumerId: string } }>(
    "/rooms/:channelId/consumers/:consumerId/resume",
    async (request, reply) => {
      const { channelId, consumerId } = request.params;
      const resumed = await roomManager.resumeConsumer(channelId, consumerId);
      if (!resumed) {
        return reply.code(404).send({ error: "Consumer not found" });
      }
      return { ok: true };
    }
  );

  // --- Consumer preferred layers (bandwidth adaptation) ---
  app.post<{
    Params: { channelId: string; consumerId: string };
    Body: { spatialLayer: number; temporalLayer?: number };
  }>(
    "/rooms/:channelId/consumers/:consumerId/preferred-layers",
    async (request, reply) => {
      const { channelId, consumerId } = request.params;
      const { spatialLayer, temporalLayer } = request.body;
      if (spatialLayer === undefined) {
        return reply.code(400).send({ error: "spatialLayer required" });
      }

      const ok = await roomManager.setConsumerPreferredLayer(
        channelId,
        consumerId,
        spatialLayer,
        temporalLayer
      );
      if (!ok) {
        return reply.code(404).send({ error: "Consumer not found" });
      }
      return { ok: true };
    }
  );

  // --- Utility ---
  app.get<{ Params: { channelId: string } }>(
    "/rooms/:channelId/producers",
    async (request, reply) => {
      const { channelId } = request.params;
      const room = roomManager.getRoom(channelId);
      if (!room) {
        return reply.code(404).send({ error: "Room not found" });
      }

      const excludeUserId = (request.query as Record<string, string>)["excludeUserId"];
      return roomManager.listProducers(channelId, excludeUserId);
    }
  );
}
