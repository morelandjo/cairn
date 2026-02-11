/**
 * VoiceEncryptionManager — attaches encrypt/decrypt transforms to
 * RTCRtpSenders/Receivers for E2E encrypted voice/video.
 */

import {
  deriveVoiceKey,
  createEncryptTransform,
  createDecryptTransform,
  supportsInsertableStreams,
} from "@murmuring/proto";

/* eslint-disable @typescript-eslint/no-explicit-any */

const KEY_ROTATION_GRACE_MS = 2000;

export class VoiceEncryptionManager {
  #currentKey: CryptoKey | null = null;
  #previousKey: CryptoKey | null = null;
  #rotationTimer: ReturnType<typeof setTimeout> | null = null;

  get supported(): boolean {
    return supportsInsertableStreams();
  }

  async setEpochSecret(epochSecret: Uint8Array): Promise<void> {
    const newKey = await deriveVoiceKey(epochSecret);

    // Keep previous key for transition window
    this.#previousKey = this.#currentKey;
    this.#currentKey = newKey;

    // Clear old key after grace period
    if (this.#rotationTimer) {
      clearTimeout(this.#rotationTimer);
    }
    this.#rotationTimer = setTimeout(() => {
      this.#previousKey = null;
      this.#rotationTimer = null;
    }, KEY_ROTATION_GRACE_MS);
  }

  /**
   * Attach encryption transform to an RTCRtpSender.
   */
  attachSenderTransform(sender: RTCRtpSender): void {
    if (!this.#currentKey || !this.supported) return;

    const transform = createEncryptTransform(this.#currentKey);

    if ("transform" in sender) {
      (sender as any).transform = transform;
    }
  }

  /**
   * Attach decryption transform to an RTCRtpReceiver.
   */
  attachReceiverTransform(receiver: RTCRtpReceiver): void {
    if (!this.#currentKey || !this.supported) return;

    const transform = createDecryptTransform(
      this.#currentKey,
      this.#previousKey ?? undefined,
    );

    if ("transform" in receiver) {
      (receiver as any).transform = transform;
    }
  }

  clear(): void {
    if (this.#rotationTimer) {
      clearTimeout(this.#rotationTimer);
    }
    this.#currentKey = null;
    this.#previousKey = null;
  }
}

/* eslint-enable @typescript-eslint/no-explicit-any */
