/**
 * AudioAnalyser — uses Web Audio AnalyserNode for speaking detection.
 */

const THRESHOLD = -40; // dBFS
const SILENCE_FRAMES = 15; // ~250ms at 60fps before stopping speaking

export class AudioAnalyser {
  #audioContext: AudioContext | null = null;
  #analyser: AnalyserNode | null = null;
  #source: MediaStreamAudioSourceNode | null = null;
  #dataArray: Uint8Array | null = null;
  #animFrameId: number | null = null;
  #speaking = false;
  #silenceCount = 0;
  #onSpeakingChange: (speaking: boolean) => void;

  constructor(onSpeakingChange: (speaking: boolean) => void) {
    this.#onSpeakingChange = onSpeakingChange;
  }

  start(stream: MediaStream): void {
    this.stop();

    this.#audioContext = new AudioContext();
    this.#analyser = this.#audioContext.createAnalyser();
    this.#analyser.fftSize = 512;
    this.#analyser.smoothingTimeConstant = 0.3;

    this.#source = this.#audioContext.createMediaStreamSource(stream);
    this.#source.connect(this.#analyser);

    this.#dataArray = new Uint8Array(this.#analyser.frequencyBinCount);
    this.#poll();
  }

  #poll = (): void => {
    if (!this.#analyser || !this.#dataArray) return;

    this.#analyser.getByteFrequencyData(this.#dataArray as Uint8Array<ArrayBuffer>);

    // Calculate RMS volume in dBFS
    let sum = 0;
    for (let i = 0; i < this.#dataArray.length; i++) {
      const normalized = (this.#dataArray[i] ?? 0) / 255;
      sum += normalized * normalized;
    }
    const rms = Math.sqrt(sum / this.#dataArray.length);
    const dBFS = rms > 0 ? 20 * Math.log10(rms) : -100;

    const isSpeaking = dBFS > THRESHOLD;

    if (isSpeaking) {
      this.#silenceCount = 0;
      if (!this.#speaking) {
        this.#speaking = true;
        this.#onSpeakingChange(true);
      }
    } else {
      this.#silenceCount++;
      if (this.#speaking && this.#silenceCount > SILENCE_FRAMES) {
        this.#speaking = false;
        this.#onSpeakingChange(false);
      }
    }

    this.#animFrameId = requestAnimationFrame(this.#poll);
  };

  stop(): void {
    if (this.#animFrameId !== null) {
      cancelAnimationFrame(this.#animFrameId);
      this.#animFrameId = null;
    }
    this.#source?.disconnect();
    this.#source = null;
    this.#analyser = null;
    if (this.#audioContext?.state !== "closed") {
      this.#audioContext?.close();
    }
    this.#audioContext = null;
    this.#speaking = false;
    this.#silenceCount = 0;
  }
}
