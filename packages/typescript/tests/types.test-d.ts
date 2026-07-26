import type { ImageResult, RiskLevel, VideoResult } from "../src/index.js";

declare const image: ImageResult;
if (image.status === "success") {
  const score: number = image.riskScore;
  const level: RiskLevel = image.riskLevel;
  void score;
  void level;
} else if (image.status === "rejected") {
  const score: null = image.riskScore;
  void score;
} else {
  const original: string = image.originalStatus;
  void original;
}

declare const video: VideoResult;
if (video.status === "success" && video.hasAudio) {
  const audio: number = video.audioRiskScore;
  void audio;
} else if (video.status === "success") {
  const audio: null = video.audioRiskScore;
  void audio;
}
