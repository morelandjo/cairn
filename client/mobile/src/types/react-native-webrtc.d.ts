declare module "react-native-webrtc" {
  export const AudioSession: {
    configure(config: {
      category: string;
      mode: string;
      options: string[];
    }): Promise<void>;
  };
  export * from "react-native-webrtc";
}
