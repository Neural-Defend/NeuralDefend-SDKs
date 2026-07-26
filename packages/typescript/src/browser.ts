import {
  NeuroVerifyClientBase,
  type NeuroVerifyClientOptions,
} from "./client.js";
import { browserPlatform } from "./platform/browser.js";

export type BrowserMediaInput = File | Blob;

export class NeuroVerifyClient extends NeuroVerifyClientBase<BrowserMediaInput> {
  constructor(options: NeuroVerifyClientOptions) {
    super(options, browserPlatform);
  }

  static staging(options: NeuroVerifyClientOptions): NeuroVerifyClient {
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
