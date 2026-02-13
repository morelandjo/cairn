import { useEffect, useState } from "react";

interface ConnectionQualityProps {
  peerConnection?: RTCPeerConnection | null;
}

type QualityLevel = "good" | "fair" | "poor";

export default function ConnectionQuality({
  peerConnection,
}: ConnectionQualityProps) {
  const [quality, setQuality] = useState<QualityLevel>("good");

  useEffect(() => {
    if (!peerConnection) return;

    const interval = setInterval(async () => {
      try {
        const stats = await peerConnection.getStats();
        let totalPacketsLost = 0;
        let totalPacketsReceived = 0;
        let roundTripTime = 0;

        stats.forEach((report) => {
          if (report.type === "inbound-rtp") {
            totalPacketsLost += report.packetsLost || 0;
            totalPacketsReceived += report.packetsReceived || 0;
          }
          if (
            report.type === "candidate-pair" &&
            report.state === "succeeded"
          ) {
            roundTripTime = report.currentRoundTripTime || 0;
          }
        });

        const lossRate =
          totalPacketsReceived > 0
            ? totalPacketsLost / (totalPacketsReceived + totalPacketsLost)
            : 0;

        if (lossRate > 0.1 || roundTripTime > 0.3) {
          setQuality("poor");
        } else if (lossRate > 0.03 || roundTripTime > 0.15) {
          setQuality("fair");
        } else {
          setQuality("good");
        }
      } catch {
        // Stats polling failed, keep current quality
      }
    }, 2000);

    return () => clearInterval(interval);
  }, [peerConnection]);

  const colors: Record<QualityLevel, string> = {
    good: "#43b581",
    fair: "#faa61a",
    poor: "#f04747",
  };

  return (
    <span
      className="connection-quality"
      title={`Connection: ${quality}`}
      style={{ color: colors[quality] }}
    >
      {quality === "good" ? "|||" : quality === "fair" ? "|| " : "|  "}
    </span>
  );
}
