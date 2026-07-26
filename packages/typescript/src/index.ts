import {
  NeuroVerifyClientBase,
  type NeuroVerifyClientOptions,
} from "./client.js";
import { nodePlatform } from "./platform/node.js";
import type { Readable } from "node:stream";

export type NodeMediaInput = string | Uint8Array | Blob | Readable;

export class NeuroVerifyClient extends NeuroVerifyClientBase<NodeMediaInput> {
  constructor(options: NeuroVerifyClientOptions = {}) {
    super(options, nodePlatform);
  }

  static staging(options: NeuroVerifyClientOptions = {}): NeuroVerifyClient {
    return new NeuroVerifyClient({
      ...options,
      baseUrl: NeuroVerifyClientBase.stagingUrl(),
    });
  }
}

export type { NeuroVerifyClientOptions } from "./client.js";
export {
  AbortError,
  AuthenticationError,
  HttpError,
  NetworkError,
  NeuroVerifyError,
  ProtocolError,
  RateLimitError,
  ScopeError,
  ServerError,
  TimeoutError,
  ValidationError,
} from "./errors.js";
export type {
  DeepReadonly,
  DetectionOptions,
  ImageRejected,
  ImageResult,
  ImageSuccess,
  ImageUnknown,
  RawResult,
  RiskLevel,
  ValidationWarning,
  VideoDetectionOptions,
  VideoRejected,
  VideoResult,
  VideoSuccessWithAudio,
  VideoSuccessWithoutAudio,
  VideoUnknown,
} from "./models.js";
