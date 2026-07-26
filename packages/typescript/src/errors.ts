import type { RawResult } from "./models.js";

export interface ErrorContext {
  readonly statusCode?: number;
  readonly detail?: string;
  readonly requestId?: string;
}

export class NeuroVerifyError extends Error {
  readonly statusCode: number | undefined;
  readonly detail: string;
  readonly requestId: string | undefined;

  constructor(message: string, context: ErrorContext = {}) {
    super(message);
    this.name = new.target.name;
    this.statusCode = context.statusCode;
    this.detail = context.detail ?? message;
    this.requestId = context.requestId;
  }
}

export class HttpError extends NeuroVerifyError {}

export class AuthenticationError extends HttpError {}

export class ScopeError extends HttpError {}

export class RateLimitError extends HttpError {
  readonly retryAfter: number | undefined;
  readonly limit: string | undefined;
  readonly remaining: string | undefined;
  readonly reset: string | undefined;

  constructor(
    message: string,
    context: ErrorContext & {
      retryAfter?: number;
      limit?: string;
      remaining?: string;
      reset?: string;
    } = {},
  ) {
    super(message, context);
    this.retryAfter = context.retryAfter;
    this.limit = context.limit;
    this.remaining = context.remaining;
    this.reset = context.reset;
  }
}

export class ServerError extends HttpError {
  readonly raw: RawResult | undefined;

  constructor(
    message: string,
    context: ErrorContext & { raw?: RawResult } = {},
  ) {
    super(message, context);
    this.raw = context.raw;
  }
}

export class TimeoutError extends NeuroVerifyError {}

export class AbortError extends NeuroVerifyError {}

export class NetworkError extends NeuroVerifyError {
  constructor(message: string) {
    super(message);
  }
}

export class ValidationError extends NeuroVerifyError {
  readonly code:
    | "api_key_required"
    | "custom_base_url_requires_opt_in"
    | "empty_file"
    | "file_too_large"
    | "filename_required"
    | "invalid_base_url"
    | "invalid_max_frames"
    | "invalid_sample_rate"
    | "invalid_timeout"
    | "invalid_retries"
    | "unsupported_input";

  constructor(code: ValidationError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

export class ProtocolError extends NeuroVerifyError {}
