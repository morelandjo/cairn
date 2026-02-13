import type {
  FastifyInstance,
  FastifyRequest,
  FastifyReply,
} from "fastify";
import fp from "fastify-plugin";
import { config } from "./config.js";

async function authPluginImpl(app: FastifyInstance): Promise<void> {
  app.addHook(
    "onRequest",
    async (request: FastifyRequest, reply: FastifyReply) => {
      // Skip auth for health endpoint
      if (request.url === "/health") return;

      const authHeader = request.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        return reply.code(401).send({ error: "Missing authorization" });
      }

      const token = authHeader.slice(7);
      if (token !== config.authSecret) {
        return reply.code(403).send({ error: "Invalid authorization" });
      }
    }
  );
}

// Use fastify-plugin to avoid encapsulation (hook applies globally)
export const authPlugin = fp(authPluginImpl);
