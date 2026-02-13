import { useEffect, useState } from "react";

interface VoiceSettingsProps {
  onClose: () => void;
}

export default function VoiceSettings({ onClose }: VoiceSettingsProps) {
  const [audioInputs, setAudioInputs] = useState<MediaDeviceInfo[]>([]);
  const [audioOutputs, setAudioOutputs] = useState<MediaDeviceInfo[]>([]);
  const [videoInputs, setVideoInputs] = useState<MediaDeviceInfo[]>([]);
  const [selectedAudioInput, setSelectedAudioInput] = useState<string>("");
  const [selectedAudioOutput, setSelectedAudioOutput] = useState<string>("");
  const [selectedVideoInput, setSelectedVideoInput] = useState<string>("");

  useEffect(() => {
    async function loadDevices() {
      try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        setAudioInputs(devices.filter((d) => d.kind === "audioinput"));
        setAudioOutputs(devices.filter((d) => d.kind === "audiooutput"));
        setVideoInputs(devices.filter((d) => d.kind === "videoinput"));
      } catch {
        // Permission denied or no devices
      }
    }
    loadDevices();
  }, []);

  return (
    <div className="voice-settings-overlay">
      <div className="voice-settings">
        <div className="voice-settings-header">
          <h3>Voice &amp; Video Settings</h3>
          <button onClick={onClose}>X</button>
        </div>

        <div className="voice-settings-section">
          <label>Input Device (Microphone)</label>
          <select
            value={selectedAudioInput}
            onChange={(e) => setSelectedAudioInput(e.target.value)}
          >
            {audioInputs.map((d) => (
              <option key={d.deviceId} value={d.deviceId}>
                {d.label || `Microphone ${d.deviceId.slice(0, 8)}`}
              </option>
            ))}
          </select>
        </div>

        <div className="voice-settings-section">
          <label>Output Device (Speakers)</label>
          <select
            value={selectedAudioOutput}
            onChange={(e) => setSelectedAudioOutput(e.target.value)}
          >
            {audioOutputs.map((d) => (
              <option key={d.deviceId} value={d.deviceId}>
                {d.label || `Speaker ${d.deviceId.slice(0, 8)}`}
              </option>
            ))}
          </select>
        </div>

        <div className="voice-settings-section">
          <label>Camera</label>
          <select
            value={selectedVideoInput}
            onChange={(e) => setSelectedVideoInput(e.target.value)}
          >
            <option value="">None</option>
            {videoInputs.map((d) => (
              <option key={d.deviceId} value={d.deviceId}>
                {d.label || `Camera ${d.deviceId.slice(0, 8)}`}
              </option>
            ))}
          </select>
        </div>

        <div className="voice-settings-actions">
          <button className="btn-primary" onClick={onClose}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
