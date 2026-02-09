import Fastify from "fastify";

const PORT = Number(process.env["SFU_PORT"]) || 3478;
const HOST = process.env["SFU_HOST"] || "0.0.0.0";

export function buildApp() {
  const app = Fastify({ logger: true });

  app.get("/health", async () => {
    return {
      status: "healthy",
      version: "0.1.0",
      services: {
        mediasoup: { status: "up" },
      },
    };
  });

  return app;
}

async function main() {
  const app = buildApp();

  try {
    await app.listen({ port: PORT, host: HOST });
    console.log(`SFU listening on ${HOST}:${PORT}`);
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
