export type RiskLevel = "low" | "medium" | "high";

export type DeepReadonly<T> = T extends (...args: never[]) => unknown
  ? T
  : T extends readonly (infer U)[]
    ? readonly DeepReadonly<U>[]
    : T extends object
      ? { readonly [K in keyof T]: DeepReadonly<T[K]> }
      : T;

export type RawResult = DeepReadonly<Record<string, unknown>>;

interface ResultBase {
  readonly uniqueTrxId: string;
  readonly filename: string;
  readonly contentType: string;
  readonly statusCode: number;
  readonly billable: boolean;
  readonly aiThreatSignals: readonly string[];
  readonly raw: RawResult;
}

export interface ImageSuccess extends ResultBase {
  readonly status: "success";
  readonly scored: true;
  readonly rejected: false;
  readonly riskScore: number;
  readonly riskLevel: RiskLevel;
  readonly message: string;
}

export interface ImageRejected extends ResultBase {
  readonly status: "rejected";
  readonly scored: false;
  readonly rejected: true;
  readonly riskScore: null;
  readonly riskLevel: null;
  readonly message: string;
}

export interface ImageUnknown extends ResultBase {
  readonly status: "unknown";
  readonly scored: false;
  readonly rejected: false;
  readonly originalStatus: string;
  readonly originalRiskLevel: string | null;
  readonly riskScore: number | null;
  readonly riskLevel: RiskLevel | null;
  readonly message: string;
}

export type ImageResult = ImageSuccess | ImageRejected | ImageUnknown;

interface VideoResultBase extends ResultBase {
  readonly videoMessage: string;
  readonly audioMessage: string | null;
}

export interface VideoSuccessWithAudio extends VideoResultBase {
  readonly status: "success";
  readonly scored: true;
  readonly rejected: false;
  readonly hasAudio: true;
  readonly videoRiskScore: number;
  readonly videoRiskLevel: RiskLevel;
  readonly audioRiskScore: number;
  readonly audioRiskLevel: RiskLevel;
  readonly overallRiskScore: number;
}

export interface VideoSuccessWithoutAudio extends VideoResultBase {
  readonly status: "success";
  readonly scored: true;
  readonly rejected: false;
  readonly hasAudio: false;
  readonly videoRiskScore: number;
  readonly videoRiskLevel: RiskLevel;
  readonly audioRiskScore: null;
  readonly audioRiskLevel: null;
  readonly overallRiskScore: number;
}

export interface VideoRejected extends VideoResultBase {
  readonly status: "rejected";
  readonly scored: false;
  readonly rejected: true;
  readonly hasAudio: false;
  readonly videoRiskScore: null;
  readonly videoRiskLevel: null;
  readonly audioRiskScore: null;
  readonly audioRiskLevel: null;
  readonly overallRiskScore: null;
}

export interface VideoUnknown extends VideoResultBase {
  readonly status: "unknown";
  readonly scored: false;
  readonly rejected: false;
  readonly hasAudio: boolean;
  readonly originalStatus: string;
  readonly originalVideoRiskLevel: string | null;
  readonly originalAudioRiskLevel: string | null;
  readonly videoRiskScore: number | null;
  readonly videoRiskLevel: RiskLevel | null;
  readonly audioRiskScore: number | null;
  readonly audioRiskLevel: RiskLevel | null;
  readonly overallRiskScore: number | null;
}

export type VideoResult =
  | VideoSuccessWithAudio
  | VideoSuccessWithoutAudio
  | VideoRejected
  | VideoUnknown;

export interface DetectionOptions {
  readonly filename?: string;
  readonly signal?: AbortSignal;
}

export interface VideoDetectionOptions extends DetectionOptions {
  readonly maxFrames?: number;
  readonly sampleRate?: number;
}

export interface ValidationWarning {
  readonly code: "unsupported_extension";
  readonly message: string;
  readonly filename: string;
}
