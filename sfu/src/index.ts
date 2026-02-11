import Fastify from "fastify";
import { config } from "./config.js";
import { WorkerPool } from "./workers.js";
import { RoomManager } from "./rooms.js";
import { authPlugin } from "./auth.js";
import { registerRoutes } from "./routes.js";

export { config } from "./config.js";
export { WorkerPool } from "./workers.js";
export { RoomManager } from "./rooms.js";

export async function buildApp(opts?: { skipWorkers?: boolean }) {
  const app = Fastify({ logger: true });

  const workerPool = new WorkerPool();
  if (!opts?.skipWorkers) {
    await workerPool.init();
  }

  const roomManager = new RoomManager(workerPool);

  await app.register(authPlugin);
  registerRoutes(app, roomManager, workerPool);

  // Attach to app for cleanup
  app.addHook("onClose", async () => {
    await workerPool.close();
  });

  return app;
}

async function main() {
  const app = await buildApp();

  try {
    await app.listen({ port: config.port, host: config.host });
    console.log(`SFU listening on ${config.host}:${config.port}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

// Only start when run directly (not imported in tests)
const isMainModule =
  import.meta.url === `file://${process.argv[1]}` ||
  process.argv[1]?.endsWith("/dist/index.js");

if (isMainModule) {
  main();
}
