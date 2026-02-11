import os from "node:os";
import type { RtpCodecCapability, WorkerLogLevel } from "mediasoup/types";

export const config = {
  port: Number(process.env["SFU_PORT"]) || 4001,
  host: process.env["SFU_HOST"] || "0.0.0.0",
  authSecret: process.env["SFU_AUTH_SECRET"] || "dev-sfu-secret",

  mediasoup: {
    numWorkers: Number(process.env["MEDIASOUP_WORKERS"]) || os.cpus().length,
    logLevel: (process.env["MEDIASOUP_LOG_LEVEL"] || "warn") as WorkerLogLevel,
    rtcMinPort: Number(process.env["MEDIASOUP_RTC_MIN_PORT"]) || 40000,
    rtcMaxPort: Number(process.env["MEDIASOUP_RTC_MAX_PORT"]) || 49999,
    listenIp: process.env["MEDIASOUP_LISTEN_IP"] || "0.0.0.0",
    announcedIp: process.env["MEDIASOUP_ANNOUNCED_IP"] || undefined,
  },

  mediaCodecs: [
    {
      kind: "audio",
      mimeType: "audio/opus",
      clockRate: 48000,
      channels: 2,
      parameters: {
        usedtx: 1,
        "sprop-stereo": 1,
        minptime: 10,
      },
    },
    {
      kind: "video",
      mimeType: "video/VP8",
      clockRate: 90000,
      parameters: {},
    },
    {
      kind: "video",
      mimeType: "video/VP9",
      clockRate: 90000,
      parameters: {
        "profile-id": 2,
      },
    },
  ] as RtpCodecCapability[],

  webRtcTransport: {
    maxIncomingBitrate: 1_500_000,
    initialAvailableOutgoingBitrate: 600_000,
  },
} as const;
