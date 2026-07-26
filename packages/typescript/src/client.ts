import {
  AbortError,
  AuthenticationError,
  HttpError,
  NetworkError,
  ProtocolError,
  RateLimitError,
  ScopeError,
  ServerError,
  TimeoutError,
  ValidationError,
} from "./errors.js";
import { validateMedia, validateVideoOptions } from "./media.js";
import type {
  DetectionOptions,
  ImageResult,
  RawResult,
  RiskLevel,
  ValidationWarning,
  VideoDetectionOptions,
  VideoResult,
} from "./models.js";
import type {
  DetectionKind,
  PlatformAdapter,
  PreparedMedia,
} from "./platform/types.js";
import { FetchTransport, type Transport } from "./transport.js";

const PRODUCTION_URL = "https://deepscan.neuraldefend.com";
const STAGING_URL = "https://stage.deepscan.neuraldefend.com";
const RISK_LEVELS = new Set<RiskLevel>(["low", "medium", "high"]);

export interface NeuroVerifyClientOptions {
  readonly apiKey?: string;
  readonly baseUrl?: string;
  readonly allowCustomBaseUrl?: boolean;
  readonly timeoutMs?: number;
  readonly maxRetries?: number;
  readonly retryAfterCapMs?: number;
  readonly userAgent?: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly onWarning?: (warning: ValidationWarning) => void;
}

export interface ClientRuntime {
  readonly transport?: Transport;
  readonly sleep?: (
    milliseconds: number,
    signal?: AbortSignal,
  ) => Promise<void>;
  readonly random?: () => number;
  readonly now?: () => number;
}

interface WireParsed {
  readonly raw: RawResult;
  readonly originalStatus: string;
  readonly uniqueTrxId: string;
  readonly filename: string;
  readonly contentType: string;
  readonly statusCode: number;
  readonly billable: boolean;
  readonly aiThreatSignals: readonly string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    for (const nested of Object.values(value)) deepFreeze(nested);
    Object.freeze(value);
  }
  return value;
}

function deepRedact(value: unknown, secret: string): unknown {
  if (typeof value === "string") {
    return value.split(secret).join("[REDACTED]");
  }
  if (Array.isArray(value)) {
    return value.map((nested) => deepRedact(nested, secret));
  }
  if (isRecord(value)) {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        deepRedact(nested, secret),
      ]),
    );
  }
  return value;
}

function attachRaw<T>(result: T, raw: RawResult): T & { raw: RawResult } {
  Object.defineProperty(result, "raw", {
    value: raw,
    writable: false,
    enumerable: false,
    configurable: false,
  });
  return result as T & { raw: RawResult };
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new ProtocolError(
      `The response field "${field}" was missing or invalid.`,
    );
  }
  return value;
}

function requiredNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new ProtocolError(
      `The response field "${field}" was missing or invalid.`,
    );
  }
  return value;
}

function riskLevel(value: unknown): RiskLevel | null {
  return typeof value === "string" && RISK_LEVELS.has(value as RiskLevel)
    ? (value as RiskLevel)
    : null;
}

function requiredNullableNumber(
  value: Record<string, unknown>,
  field: string,
): number | null {
  if (!(field in value)) {
    throw new ProtocolError(`The response field "${field}" was missing.`);
  }
  const candidate = value[field];
  if (
    candidate !== null &&
    (typeof candidate !== "number" ||
      !Number.isFinite(candidate) ||
      candidate < 0.1 ||
      candidate > 10)
  ) {
    throw new ProtocolError(`The response field "${field}" was invalid.`);
  }
  return candidate;
}

function requiredNullableString(
  value: Record<string, unknown>,
  field: string,
): string | null {
  if (!(field in value)) {
    throw new ProtocolError(`The response field "${field}" was missing.`);
  }
  const candidate = value[field];
  if (candidate !== null && typeof candidate !== "string") {
    throw new ProtocolError(`The response field "${field}" was invalid.`);
  }
  return candidate;
}

function parseBillable(value: unknown): boolean {
  if (value === "Y") return true;
  if (value === "N") return false;
  throw new ProtocolError(
    'The response field "billable" must be exactly "Y" or "N".',
  );
}

function parseBase(value: Record<string, unknown>, secret: string): WireParsed {
  const candidateSignals = value.ai_threat_signals ?? [];
  if (
    !Array.isArray(candidateSignals) ||
    !candidateSignals.every((item) => typeof item === "string")
  ) {
    throw new ProtocolError(
      'The response field "ai_threat_signals" was invalid.',
    );
  }
  const signals = candidateSignals as string[];
  return {
    raw: deepFreeze(deepRedact(value, secret)) as RawResult,
    originalStatus: requiredString(value.status, "status"),
    uniqueTrxId: requiredString(value.unique_trx_id, "unique_trx_id"),
    filename: requiredString(value.filename, "filename"),
    contentType: requiredString(value.content_type, "content_type"),
    statusCode: requiredNumber(value.status_code, "status_code"),
    billable: parseBillable(value.billable),
    aiThreatSignals: Object.freeze(signals),
  };
}

function parseImage(
  value: Record<string, unknown>,
  httpStatus: number,
  requestId: string | undefined,
  redact: (value: string) => string,
  secret: string,
): ImageResult {
  const { raw, originalStatus, ...fields } = parseBase(value, secret);
  const message = requiredString(value.message, "message");
  const score = requiredNullableNumber(value, "risk_score");
  const originalLevel = requiredNullableString(value, "risk_level");
  const level = riskLevel(originalLevel);

  if (originalStatus === "error") {
    const detail = redact(message);
    throw new ServerError(detail, {
      statusCode: httpStatus,
      detail,
      raw: deepFreeze(deepRedact(value, secret)) as RawResult,
      ...(requestId === undefined ? {} : { requestId }),
    });
  }
  if (originalStatus === "success" && score !== null && level !== null) {
    return attachRaw(
      {
        ...fields,
        status: "success" as const,
        scored: true as const,
        rejected: false as const,
        riskScore: score,
        riskLevel: level,
        message,
      },
      raw,
    );
  }
  if (originalStatus === "rejected") {
    return attachRaw(
      {
        ...fields,
        status: "rejected" as const,
        scored: false as const,
        rejected: true as const,
        riskScore: null,
        riskLevel: null,
        message,
      },
      raw,
    );
  }
  return attachRaw(
    {
      ...fields,
      status: "unknown" as const,
      scored: false as const,
      rejected: false as const,
      originalStatus,
      originalRiskLevel: originalLevel,
      riskScore: score,
      riskLevel: level,
      message,
    },
    raw,
  );
}

function parseVideo(
  value: Record<string, unknown>,
  httpStatus: number,
  requestId: string | undefined,
  redact: (value: string) => string,
  secret: string,
): VideoResult {
  const { raw, originalStatus, ...fields } = parseBase(value, secret);
  const videoMessage = requiredString(value.video_message, "video_message");
  const audioMessage = requiredNullableString(value, "audio_message");
  const videoScore = requiredNullableNumber(value, "video_risk_score");
  const originalVideoLevel = requiredNullableString(value, "video_risk_level");
  const videoLevel = riskLevel(originalVideoLevel);
  const audioScore = requiredNullableNumber(value, "audio_risk_score");
  const originalAudioLevel = requiredNullableString(value, "audio_risk_level");
  const audioLevel = riskLevel(originalAudioLevel);

  if (originalStatus === "error") {
    const detail = redact(videoMessage);
    throw new ServerError(detail, {
      statusCode: httpStatus,
      detail,
      raw: deepFreeze(deepRedact(value, secret)) as RawResult,
      ...(requestId === undefined ? {} : { requestId }),
    });
  }
  if (
    originalStatus === "success" &&
    videoScore !== null &&
    videoLevel !== null
  ) {
    if (audioScore !== null && audioLevel !== null) {
      return attachRaw(
        {
          ...fields,
          status: "success" as const,
          scored: true as const,
          rejected: false as const,
          hasAudio: true as const,
          videoRiskScore: videoScore,
          videoRiskLevel: videoLevel,
          videoMessage,
          audioRiskScore: audioScore,
          audioRiskLevel: audioLevel,
          audioMessage,
          overallRiskScore: Math.max(videoScore, audioScore),
        },
        raw,
      );
    }
    if (audioScore === null && audioLevel === null) {
      return attachRaw(
        {
          ...fields,
          status: "success" as const,
          scored: true as const,
          rejected: false as const,
          hasAudio: false as const,
          videoRiskScore: videoScore,
          videoRiskLevel: videoLevel,
          videoMessage,
          audioRiskScore: null,
          audioRiskLevel: null,
          audioMessage,
          overallRiskScore: videoScore,
        },
        raw,
      );
    }
  }
  if (originalStatus === "rejected") {
    return attachRaw(
      {
        ...fields,
        status: "rejected" as const,
        scored: false as const,
        rejected: true as const,
        hasAudio: false as const,
        videoRiskScore: null,
        videoRiskLevel: null,
        videoMessage,
        audioRiskScore: null,
        audioRiskLevel: null,
        audioMessage,
        overallRiskScore: null,
      },
      raw,
    );
  }
  return attachRaw(
    {
      ...fields,
      status: "unknown" as const,
      scored: false as const,
      rejected: false as const,
      hasAudio: audioScore !== null,
      originalStatus,
      originalVideoRiskLevel: originalVideoLevel,
      originalAudioRiskLevel: originalAudioLevel,
      videoRiskScore: videoScore,
      videoRiskLevel: videoLevel,
      videoMessage,
      audioRiskScore: audioScore,
      audioRiskLevel: audioLevel,
      audioMessage,
      overallRiskScore:
        videoScore === null ? null : Math.max(videoScore, audioScore ?? 0),
    },
    raw,
  );
}

async function parseJson(response: Response): Promise<Record<string, unknown>> {
  let value: unknown;
  try {
    value = await response.clone().json();
  } catch {
    throw new ProtocolError("The server returned malformed JSON.", {
      statusCode: response.status,
    });
  }
  if (!isRecord(value)) {
    throw new ProtocolError("The server returned an invalid JSON object.", {
      statusCode: response.status,
    });
  }
  return value;
}

async function defaultSleep(
  milliseconds: number,
  signal?: AbortSignal,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(new AbortError("The request was aborted."));
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      reject(new AbortError("The request was aborted."));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, milliseconds);
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

function validateBaseUrl(
  value: string,
  allowTestHttp: boolean,
  allowCustomBaseUrl: boolean,
): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new ValidationError(
      "invalid_base_url",
      "baseUrl must be a valid HTTPS origin.",
    );
  }
  const protocolAllowed =
    url.protocol === "https:" || (allowTestHttp && url.protocol === "http:");
  if (
    !protocolAllowed ||
    !url.hostname ||
    url.username !== "" ||
    url.password !== "" ||
    url.search !== "" ||
    url.hash !== "" ||
    (url.pathname !== "" && url.pathname !== "/")
  ) {
    throw new ValidationError(
      "invalid_base_url",
      "baseUrl must be an HTTPS origin without credentials, a path, query, or fragment.",
    );
  }
  const origin = url.origin;
  if (
    origin !== PRODUCTION_URL &&
    origin !== STAGING_URL &&
    !allowTestHttp &&
    !allowCustomBaseUrl
  ) {
    throw new ValidationError(
      "custom_base_url_requires_opt_in",
      "A non-Neural Defend baseUrl requires allowCustomBaseUrl: true because it receives the API key and uploaded media.",
    );
  }
  return origin;
}

function attemptSignal(caller: AbortSignal | undefined, timeoutMs: number) {
  const controller = new AbortController();
  let timedOut = false;
  const abortFromCaller = () => controller.abort(caller?.reason);
  if (caller?.aborted) abortFromCaller();
  else caller?.addEventListener("abort", abortFromCaller, { once: true });
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);
  return {
    signal: controller.signal,
    didTimeOut: () => timedOut,
    cleanup: () => {
      clearTimeout(timer);
      caller?.removeEventListener("abort", abortFromCaller);
    },
  };
}

interface PendingResponse {
  readonly response: Response;
  readonly didTimeOut: () => boolean;
  readonly cleanup: () => void;
}

export class NeuroVerifyClientBase<MediaInput> {
  readonly baseUrl: string;
  readonly timeoutMs: number;
  readonly maxRetries: number;
  readonly retryAfterCapMs: number;

  readonly #apiKey: string;
  readonly #userAgent: string | undefined;
  readonly #platform: PlatformAdapter;
  readonly #transport: Transport;
  readonly #warning: (warning: ValidationWarning) => void;
  readonly #sleep: (
    milliseconds: number,
    signal?: AbortSignal,
  ) => Promise<void>;
  readonly #random: () => number;
  readonly #now: () => number;

  constructor(
    options: NeuroVerifyClientOptions,
    platform: PlatformAdapter,
    runtime: ClientRuntime = {},
  ) {
    const apiKey = options.apiKey ?? platform.env("NEURALDEFEND_API_KEY");
    if (!apiKey?.trim()) {
      throw new ValidationError(
        "api_key_required",
        platform.name === "browser"
          ? "apiKey is required in browser environments."
          : "apiKey is required; pass it explicitly or set NEURALDEFEND_API_KEY.",
      );
    }
    const timeoutMs = options.timeoutMs ?? 120_000;
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new ValidationError(
        "invalid_timeout",
        "timeoutMs must be greater than zero.",
      );
    }
    const maxRetries = options.maxRetries ?? 3;
    if (!Number.isInteger(maxRetries) || maxRetries < 0 || maxRetries > 3) {
      throw new ValidationError(
        "invalid_retries",
        "maxRetries must be an integer from 0 through 3.",
      );
    }

    this.#apiKey = apiKey.trim();
    this.#platform = platform;
    this.baseUrl = validateBaseUrl(
      options.baseUrl ??
        platform.env("NEURALDEFEND_BASE_URL") ??
        PRODUCTION_URL,
      runtime.transport !== undefined,
      options.allowCustomBaseUrl === true,
    );
    this.timeoutMs = timeoutMs;
    this.maxRetries = maxRetries;
    this.retryAfterCapMs = Math.max(0, options.retryAfterCapMs ?? 60_000);
    this.#userAgent =
      platform.name === "node"
        ? (options.userAgent ?? "@neuraldefend/sdk/1.0.2")
        : undefined;
    this.#transport =
      runtime.transport ??
      new FetchTransport(options.fetch ?? globalThis.fetch);
    this.#warning = options.onWarning ?? (() => undefined);
    this.#sleep = runtime.sleep ?? defaultSleep;
    this.#random = runtime.random ?? Math.random;
    this.#now = runtime.now ?? Date.now;
  }

  static stagingUrl(): string {
    return STAGING_URL;
  }

  toJSON(): Record<string, unknown> {
    return {
      apiKey: "[REDACTED]",
      baseUrl: this.baseUrl,
      timeoutMs: this.timeoutMs,
      maxRetries: this.maxRetries,
    };
  }

  toString(): string {
    return `NeuroVerifyClient(${JSON.stringify(this.toJSON())})`;
  }

  async detectImage(
    input: MediaInput,
    options: DetectionOptions = {},
  ): Promise<ImageResult> {
    const media = await this.#platform.prepare(
      input,
      options.filename,
      "image",
      options.signal,
    );
    try {
      validateMedia(media, "image", this.#warning);
      const pending = await this.#request("image", media, options);
      try {
        return (await this.#result(pending.response, "image")) as ImageResult;
      } catch (error) {
        if (options.signal?.aborted) {
          throw new AbortError("The request was aborted.");
        }
        if (pending.didTimeOut()) {
          throw new TimeoutError("The image request timed out.");
        }
        throw error;
      } finally {
        pending.cleanup();
      }
    } finally {
      await media.dispose?.();
    }
  }

  async detectVideo(
    input: MediaInput,
    options: VideoDetectionOptions = {},
  ): Promise<VideoResult> {
    validateVideoOptions(options.maxFrames, options.sampleRate);
    const media = await this.#platform.prepare(
      input,
      options.filename,
      "video",
      options.signal,
    );
    try {
      validateMedia(media, "video", this.#warning);
      const pending = await this.#request("video", media, options);
      try {
        return (await this.#result(pending.response, "video")) as VideoResult;
      } catch (error) {
        if (options.signal?.aborted) {
          throw new AbortError("The request was aborted.");
        }
        if (pending.didTimeOut()) {
          throw new TimeoutError("The video request timed out.");
        }
        throw error;
      } finally {
        pending.cleanup();
      }
    } finally {
      await media.dispose?.();
    }
  }

  async #request(
    kind: DetectionKind,
    media: PreparedMedia,
    options: VideoDetectionOptions,
  ): Promise<PendingResponse> {
    for (let attempt = 0; attempt <= this.maxRetries; attempt += 1) {
      if (options.signal?.aborted)
        throw new AbortError("The request was aborted.");
      const upload = await media.createUpload();
      const combined = attemptSignal(options.signal, this.timeoutMs);
      let response: Response;
      try {
        response = await this.#transport.execute({
          kind,
          file: upload,
          filename: media.filename,
          apiKey: this.#apiKey,
          baseUrl: this.baseUrl,
          signal: combined.signal,
          ...(this.#userAgent === undefined
            ? {}
            : { userAgent: this.#userAgent }),
          ...(options.maxFrames === undefined
            ? {}
            : { maxFrames: options.maxFrames }),
          ...(options.sampleRate === undefined
            ? {}
            : { sampleRate: options.sampleRate }),
        });
      } catch {
        combined.cleanup();
        if (options.signal?.aborted)
          throw new AbortError("The request was aborted.");
        if (combined.didTimeOut()) {
          throw new TimeoutError(`The ${kind} request timed out.`);
        }
        throw new NetworkError(
          `The ${kind} request failed before receiving a response.`,
        );
      }

      const retryable =
        response.status === 429 ||
        response.status === 500 ||
        response.status === 503;
      if (!retryable || attempt === this.maxRetries) {
        return {
          response,
          didTimeOut: combined.didTimeOut,
          cleanup: combined.cleanup,
        };
      }

      const delay =
        response.status === 429
          ? this.#retryAfter(response.headers.get("retry-after"), attempt)
          : 1000 * 2 ** attempt * (0.75 + this.#random() * 0.5);
      try {
        await response.body?.cancel();
      } finally {
        combined.cleanup();
      }
      await this.#sleep(delay, options.signal);
    }
    throw new Error("Unreachable retry state");
  }

  #retryAfter(value: string | null, attempt: number): number {
    if (value) {
      const seconds = Number(value);
      const parsed = Number.isFinite(seconds)
        ? seconds * 1000
        : Date.parse(value) - this.#now();
      if (Number.isFinite(parsed)) {
        return Math.min(this.retryAfterCapMs, Math.max(0, parsed));
      }
    }
    return Math.min(this.retryAfterCapMs, 1000 * 2 ** attempt);
  }

  async #result(
    response: Response,
    kind: DetectionKind,
  ): Promise<ImageResult | VideoResult> {
    const requestId =
      response.headers.get("x-request-id") ??
      response.headers.get("x-correlation-id") ??
      undefined;
    let json: Record<string, unknown>;
    try {
      json = await parseJson(response);
    } catch (error) {
      const detail = `HTTP ${response.status}`;
      const common = {
        statusCode: response.status,
        detail,
        ...(requestId === undefined ? {} : { requestId }),
      };
      if (response.status === 401) {
        throw new AuthenticationError(detail, common);
      }
      if (response.status === 403) {
        throw new ScopeError(detail, common);
      }
      if (response.status === 429) {
        throw new RateLimitError(detail, {
          ...common,
          retryAfter:
            this.#retryAfter(response.headers.get("retry-after"), 0) / 1000,
        });
      }
      if (response.status === 500 || response.status === 503) {
        throw new ServerError(detail, common);
      }
      throw error;
    }

    if (response.status === 401) {
      const detail =
        typeof json.detail === "string"
          ? this.#redact(json.detail)
          : "HTTP 401";
      throw new AuthenticationError(detail, {
        statusCode: 401,
        detail,
        ...(requestId === undefined ? {} : { requestId }),
      });
    }
    if (response.status === 403) {
      const detail =
        typeof json.detail === "string"
          ? this.#redact(json.detail)
          : "HTTP 403";
      throw new ScopeError(detail, {
        statusCode: 403,
        detail,
        ...(requestId === undefined ? {} : { requestId }),
      });
    }
    if (response.status === 429) {
      const detail =
        typeof json.detail === "string"
          ? this.#redact(json.detail)
          : "HTTP 429";
      const retryAfterMs = this.#retryAfter(
        response.headers.get("retry-after"),
        0,
      );
      throw new RateLimitError(detail, {
        statusCode: 429,
        detail,
        retryAfter: retryAfterMs / 1000,
        ...(response.headers.get("x-ratelimit-limit") === null
          ? {}
          : { limit: response.headers.get("x-ratelimit-limit")! }),
        ...(response.headers.get("x-ratelimit-remaining") === null
          ? {}
          : { remaining: response.headers.get("x-ratelimit-remaining")! }),
        ...(response.headers.get("x-ratelimit-reset") === null
          ? {}
          : { reset: response.headers.get("x-ratelimit-reset")! }),
        ...(requestId === undefined ? {} : { requestId }),
      });
    }
    if (
      response.status !== 200 &&
      response.status !== 400 &&
      response.status !== 500 &&
      response.status !== 503
    ) {
      const detail =
        typeof json.detail === "string"
          ? this.#redact(json.detail)
          : `Unexpected HTTP ${response.status}.`;
      throw new HttpError(detail, {
        statusCode: response.status,
        detail,
        ...(requestId === undefined ? {} : { requestId }),
      });
    }

    const envelopeKey =
      kind === "image"
        ? "unified_face_authenticity_score"
        : "unified_video_authenticity_score";
    const envelope = json[envelopeKey];
    if (response.status === 500 || response.status === 503) {
      if (!isRecord(envelope)) {
        const detail = `HTTP ${response.status}`;
        throw new ServerError(detail, {
          statusCode: response.status,
          detail,
          ...(requestId === undefined ? {} : { requestId }),
        });
      }
      const effectiveRequestId =
        requestId ??
        (typeof envelope.unique_trx_id === "string"
          ? envelope.unique_trx_id
          : undefined);
      const message =
        kind === "image" ? envelope.message : envelope.video_message;
      const detail =
        typeof message === "string"
          ? this.#redact(message)
          : `HTTP ${response.status}`;
      const raw = deepFreeze(deepRedact(envelope, this.#apiKey)) as RawResult;
      throw new ServerError(detail, {
        statusCode: response.status,
        detail,
        raw,
        ...(effectiveRequestId === undefined
          ? {}
          : { requestId: effectiveRequestId }),
      });
    }
    if (!isRecord(envelope)) {
      throw new ProtocolError(`The response was missing "${envelopeKey}".`, {
        statusCode: response.status,
        ...(requestId === undefined ? {} : { requestId }),
      });
    }
    const effectiveRequestId =
      requestId ??
      (typeof envelope.unique_trx_id === "string"
        ? envelope.unique_trx_id
        : undefined);

    const result =
      kind === "image"
        ? parseImage(
            envelope,
            response.status,
            effectiveRequestId,
            (value) => this.#redact(value),
            this.#apiKey,
          )
        : parseVideo(
            envelope,
            response.status,
            effectiveRequestId,
            (value) => this.#redact(value),
            this.#apiKey,
          );
    if (response.status === 400 && result.status !== "rejected") {
      throw new HttpError("HTTP 400 response was not a rejection.", {
        statusCode: 400,
        ...(effectiveRequestId === undefined
          ? {}
          : { requestId: effectiveRequestId }),
      });
    }
    return result;
  }

  #redact(value: string): string {
    return value.split(this.#apiKey).join("[REDACTED]");
  }
}
