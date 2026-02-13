import * as mediasoup from "mediasoup";
import type { Worker } from "mediasoup/types";
import { config } from "./config.js";

export class WorkerPool {
  private workers: Worker[] = [];
  private nextIndex = 0;

  async init(): Promise<void> {
    const count = config.mediasoup.numWorkers;
    for (let i = 0; i < count; i++) {
      const worker = await mediasoup.createWorker({
        logLevel: config.mediasoup.logLevel,
        rtcMinPort: config.mediasoup.rtcMinPort,
        rtcMaxPort: config.mediasoup.rtcMaxPort,
      });

      worker.on("died", () => {
        console.error(`mediasoup Worker ${worker.pid} died, exiting`);
        process.exit(1);
      });

      this.workers.push(worker);
    }
  }

  getNextWorker(): Worker {
    if (this.workers.length === 0) {
      throw new Error("WorkerPool not initialized");
    }
    const worker = this.workers[this.nextIndex % this.workers.length]!;
    this.nextIndex++;
    return worker;
  }

  get count(): number {
    return this.workers.length;
  }

  async close(): Promise<void> {
    for (const worker of this.workers) {
      worker.close();
    }
    this.workers = [];
    this.nextIndex = 0;
  }
}
