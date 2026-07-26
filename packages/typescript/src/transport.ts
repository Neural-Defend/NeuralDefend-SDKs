import type { DetectionKind } from "./platform/types.js";

export interface TransportRequest {
  readonly kind: DetectionKind;
  readonly file: Blob;
  readonly filename: string;
  readonly apiKey: string;
  readonly baseUrl: string;
  readonly signal: AbortSignal;
  readonly userAgent?: string;
  readonly maxFrames?: number;
  readonly sampleRate?: number;
}

export interface Transport {
  execute(request: TransportRequest): Promise<Response>;
}

export class FetchTransport implements Transport {
  constructor(
    private readonly fetchApi: typeof globalThis.fetch = globalThis.fetch,
  ) {}

  async execute(request: TransportRequest): Promise<Response> {
    const form = new FormData();
    form.append("file", request.file, request.filename);

    const url = new URL(
      request.kind === "image" ? "/detect/image" : "/detect/video",
      `${request.baseUrl}/`,
    );
    if (request.kind === "video") {
      if (request.maxFrames !== undefined) {
        url.searchParams.set("max_frames", String(request.maxFrames));
      }
      if (request.sampleRate !== undefined) {
        url.searchParams.set("sample_rate", String(request.sampleRate));
      }
    }

    const headers: Record<string, string> = { "x-api-key": request.apiKey };
    if (request.userAgent) headers["user-agent"] = request.userAgent;

    return this.fetchApi(url, {
      method: "POST",
      headers,
      body: form,
      redirect: "error",
      signal: request.signal,
    });
  }
}

interface RawApiResponse {
  readonly raw: Response;
}

export interface GeneratedImageApi {
  detectImageRaw(
    request: { file: Blob },
    initOverrides?: RequestInit,
  ): Promise<RawApiResponse>;
}

export interface GeneratedVideoApi {
  detectVideoRaw(
    request: { file: Blob; maxFrames?: number; sampleRate?: number },
    initOverrides?: RequestInit,
  ): Promise<RawApiResponse>;
}

/**
 * Adapter for the generated typescript-fetch core. It intentionally uses only
 * the stable raw-method shape so generated models never enter the public API.
 */
export class GeneratedCoreTransport implements Transport {
  constructor(
    private readonly imageApi: GeneratedImageApi,
    private readonly videoApi: GeneratedVideoApi,
  ) {}

  async execute(request: TransportRequest): Promise<Response> {
    try {
      const init: RequestInit = {
        redirect: "error",
        signal: request.signal,
      };
      const result =
        request.kind === "image"
          ? await this.imageApi.detectImageRaw({ file: request.file }, init)
          : await this.videoApi.detectVideoRaw(
              {
                file: request.file,
                ...(request.maxFrames === undefined
                  ? {}
                  : { maxFrames: request.maxFrames }),
                ...(request.sampleRate === undefined
                  ? {}
                  : { sampleRate: request.sampleRate }),
              },
              init,
            );
      return result.raw;
    } catch (error) {
      // runtime.ResponseError exposes its untouched Response publicly.
      if (
        error instanceof Error &&
        error.name === "ResponseError" &&
        "response" in error &&
        error.response instanceof Response
      ) {
        return error.response;
      }
      throw error;
    }
  }
}
