import { inspect } from "node:util";
import { Readable } from "node:stream";
import { describe, expect, it, vi } from "vitest";
import { NeuroVerifyClientBase } from "../src/client.js";
import {
  AbortError,
  AuthenticationError,
  HttpError,
  NetworkError,
  ProtocolError,
  ServerError,
  TimeoutError,
  ValidationError,
} from "../src/errors.js";
import { NeuroVerifyClient } from "../src/index.js";
import { browserPlatform } from "../src/platform/browser.js";
import { nodePlatform } from "../src/platform/node.js";
import type { PlatformAdapter } from "../src/platform/types.js";
import { GeneratedCoreTransport, type Transport } from "../src/transport.js";

const imageSuccess = {
  unified_face_authenticity_score: {
    unique_trx_id: "trx_test",
    filename: "photo.jpg",
    content_type: "image/jpeg",
    status: "success",
    status_code: 1,
    billable: "Y",
    risk_score: 2.2,
    risk_level: "low",
    message: "Scored",
    ai_threat_signals: [],
  },
};

const imageServerError = {
  unified_face_authenticity_score: {
    unique_trx_id: "trx_test",
    filename: "photo.jpg",
    content_type: "image/jpeg",
    status: "error",
    status_code: 5,
    billable: "N",
    risk_score: null,
    risk_level: null,
    message: "Unavailable",
    ai_threat_signals: [],
  },
};

function jsonResponse(
  body: unknown,
  status = 200,
  headers?: HeadersInit,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

describe("requests", () => {
  it("sends the API key, named multipart file, and video query parameters", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>().mockResolvedValue(
      jsonResponse({
        unified_video_authenticity_score: {
          unique_trx_id: "trx_video",
          filename: "clip.mp4",
          content_type: "video/mp4",
          status: "success",
          status_code: 1,
          billable: "Y",
          video_risk_score: 2,
          video_risk_level: "low",
          video_message: "Scored",
          audio_risk_score: null,
          audio_risk_level: null,
          audio_message: "No audio",
          ai_threat_signals: [],
        },
      }),
    );
    const client = new NeuroVerifyClient({ apiKey: "secret", fetch });

    await client.detectVideo(new Uint8Array([1, 2]), {
      filename: "clip.mp4",
      maxFrames: 24,
      sampleRate: 3,
    });

    const [url, init] = fetch.mock.calls[0]!;
    expect(String(url)).toContain("/detect/video?max_frames=24&sample_rate=3");
    expect(new Headers(init?.headers).get("x-api-key")).toBe("secret");
    expect(new Headers(init?.headers).get("content-type")).toBeNull();
    expect(init?.redirect).toBe("error");
    const form = init?.body as FormData;
    const file = form.get("file") as File;
    expect(file.name).toBe("clip.mp4");
    expect((await file.arrayBuffer()).byteLength).toBe(2);
  });

  it("uses the Node environment fallback without exposing the key", () => {
    const previous = process.env.NEURALDEFEND_API_KEY;
    process.env.NEURALDEFEND_API_KEY = "test_key";
    try {
      const client = new NeuroVerifyClient();
      expect(JSON.stringify(client)).not.toContain("test_key");
      expect(inspect(client)).not.toContain("test_key");
      expect(client.toString()).toContain("[REDACTED]");
    } finally {
      if (previous === undefined) delete process.env.NEURALDEFEND_API_KEY;
      else process.env.NEURALDEFEND_API_KEY = previous;
    }
  });

  it("requires explicit browser credentials", () => {
    expect(
      () => new NeuroVerifyClientBase<Blob>({}, browserPlatform),
    ).toThrowError(ValidationError);
  });

  it("accepts Blob objects from another browser realm", async () => {
    const foreignBlob = new Blob(["cross-realm"], { type: "image/png" });
    const size = Object.getOwnPropertyDescriptor(Blob.prototype, "size")!.get!;
    const type = Object.getOwnPropertyDescriptor(Blob.prototype, "type")!.get!;
    Object.setPrototypeOf(foreignBlob, {
      [Symbol.toStringTag]: "Blob",
      get size() {
        return size.call(this);
      },
      get type() {
        return type.call(this);
      },
      arrayBuffer: Blob.prototype.arrayBuffer,
      slice: Blob.prototype.slice,
      stream: Blob.prototype.stream,
      text: Blob.prototype.text,
    });

    expect(foreignBlob).not.toBeInstanceOf(Blob);
    const prepared = await browserPlatform.prepare(
      foreignBlob,
      "photo.jpg",
      "image",
    );
    const upload = await prepared.createUpload();
    expect(await upload.text()).toBe("cross-realm");
  });

  it("rejects objects that spoof Blob metadata", async () => {
    const spoof = {
      [Symbol.toStringTag]: "Blob",
      size: 1,
      type: "image/jpeg",
      arrayBuffer: async () => new ArrayBuffer(0),
      slice: () => new Blob(),
      stream: () => new Blob().stream(),
      text: async () => "x",
      toString: () => "x".repeat(11 * 1024 * 1024),
    };

    await expect(
      browserPlatform.prepare(spoof as unknown as Blob, "photo.jpg", "image"),
    ).rejects.toMatchObject({ code: "unsupported_input" });
  });

  it("requires an HTTPS origin and trims explicit credentials", async () => {
    expect(
      () =>
        new NeuroVerifyClient({
          apiKey: "key",
          baseUrl: "http://example.com",
        }),
    ).toThrowError(ValidationError);

    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "  secret  ", fetch });
    await client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" });
    expect(new Headers(fetch.mock.calls[0]![1]?.headers).get("x-api-key")).toBe(
      "secret",
    );
  });

  it("requires explicit opt-in before sending secrets to a custom origin", () => {
    expect(
      () =>
        new NeuroVerifyClient({
          apiKey: "key",
          baseUrl: "https://api.example.com",
        }),
    ).toThrowError(/allowCustomBaseUrl/);

    const client = new NeuroVerifyClient({
      apiKey: "key",
      baseUrl: "https://api.example.com",
      allowCustomBaseUrl: true,
    });
    expect(client.baseUrl).toBe("https://api.example.com");
  });

  it("snapshots a validated path before creating the upload", async () => {
    const [{ mkdtemp, rm, writeFile }, { tmpdir }, { join }] =
      await Promise.all([
        import("node:fs/promises"),
        import("node:os"),
        import("node:path"),
      ]);
    const directory = await mkdtemp(join(tmpdir(), "neuraldefend-test-"));
    const path = join(directory, "photo.jpg");
    await writeFile(path, "original");

    try {
      const prepared = await nodePlatform.prepare(path, undefined, "image");
      await writeFile(path, "replacement");
      try {
        const upload = await prepared.createUpload();
        expect(await upload.text()).toBe("original");
      } finally {
        await prepared.dispose?.();
      }
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  it("spools Node streams for bounded, retryable uploads", async () => {
    let uploaded = "";
    const transport: Transport = {
      async execute(request) {
        uploaded = new TextDecoder().decode(await request.file.arrayBuffer());
        return jsonResponse(imageSuccess);
      },
    };
    const client = new NeuroVerifyClientBase<Readable>(
      { apiKey: "key" },
      nodePlatform,
      { transport },
    );

    const result = await client.detectImage(
      Readable.from(["streamed", "-media"]),
      {
        filename: "photo.jpg",
      },
    );

    expect(result.scored).toBe(true);
    expect(uploaded).toBe("streamed-media");
  });

  it("cancels stalled Node streams before transport", async () => {
    const transport: Transport = { execute: vi.fn() };
    const client = new NeuroVerifyClientBase<Readable>(
      { apiKey: "key" },
      nodePlatform,
      { transport },
    );
    const stream = new Readable({ read() {} });
    const controller = new AbortController();
    const pending = client.detectImage(stream, {
      filename: "photo.jpg",
      signal: controller.signal,
    });

    controller.abort();

    await expect(pending).rejects.toBeInstanceOf(AbortError);
    expect(stream.destroyed).toBe(true);
    expect(transport.execute).not.toHaveBeenCalled();
  });

  it("releases Node streams after chunk validation fails", async () => {
    const transport: Transport = { execute: vi.fn() };
    const client = new NeuroVerifyClientBase<Readable>(
      { apiKey: "key" },
      nodePlatform,
      { transport },
    );
    const stream = Readable.from([{ invalid: true }]);

    await expect(
      client.detectImage(stream, { filename: "photo.jpg" }),
    ).rejects.toMatchObject({ code: "unsupported_input" });
    expect(stream.destroyed).toBe(true);
    expect(transport.execute).not.toHaveBeenCalled();
  });
});

describe("retries", () => {
  it("retries 500/503 three times with server-only jitter and fresh uploads", async () => {
    const statuses = [500, 503, 500, 200];
    const files: Blob[] = [];
    const transport: Transport = {
      async execute(request) {
        files.push(request.file);
        const status = statuses.shift()!;
        return jsonResponse(
          status === 200 ? imageSuccess : imageServerError,
          status,
        );
      },
    };
    const delays: number[] = [];
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key" },
      nodePlatform,
      {
        transport,
        random: () => 0.5,
        sleep: async (delay) => {
          delays.push(delay);
        },
      },
    );

    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });
    expect(result.status).toBe("success");
    expect(delays).toEqual([1000, 2000, 4000]);
    expect(new Set(files).size).toBe(4);
  });

  it("honors Retry-After dates, caps them, and adds no jitter", async () => {
    const transport: Transport = {
      execute: vi
        .fn()
        .mockResolvedValueOnce(
          jsonResponse({ detail: "Wait" }, 429, {
            "retry-after": "Thu, 01 Jan 2026 00:02:00 GMT",
          }),
        )
        .mockResolvedValueOnce(jsonResponse(imageSuccess)),
    };
    const delays: number[] = [];
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key", maxRetries: 1, retryAfterCapMs: 30_000 },
      nodePlatform,
      {
        transport,
        now: () => Date.parse("Thu, 01 Jan 2026 00:00:00 GMT"),
        random: () => 0,
        sleep: async (delay) => {
          delays.push(delay);
        },
      },
    );

    await client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" });
    expect(delays).toEqual([30_000]);
  });

  it("does not retry network failures", async () => {
    const transport: Transport = {
      execute: vi.fn().mockRejectedValue(new TypeError("offline")),
    };
    const sleep = vi.fn();
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key" },
      nodePlatform,
      { transport, sleep },
    );
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(NetworkError);
    expect(transport.execute).toHaveBeenCalledOnce();
    expect(sleep).not.toHaveBeenCalled();
  });
});

describe("abort and timeout", () => {
  const waitingTransport: Transport = {
    async execute(request) {
      await new Promise<never>((_resolve, reject) => {
        request.signal.addEventListener(
          "abort",
          () => reject(new DOMException("Aborted", "AbortError")),
          { once: true },
        );
      });
      throw new Error("unreachable");
    },
  };

  it("distinguishes timeout", async () => {
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key", timeoutMs: 5 },
      nodePlatform,
      { transport: waitingTransport },
    );
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(TimeoutError);
  });

  it("keeps timeout active while reading the response body", async () => {
    const transport: Transport = {
      async execute(request) {
        const body = new ReadableStream({
          start(controller) {
            request.signal.addEventListener(
              "abort",
              () => controller.error(new Error("aborted")),
              { once: true },
            );
          },
        });
        return new Response(body, {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      },
    };
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key", timeoutMs: 5 },
      nodePlatform,
      { transport },
    );
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(TimeoutError);
  });

  it("distinguishes caller cancellation", async () => {
    const controller = new AbortController();
    const client = new NeuroVerifyClientBase<Uint8Array>(
      { apiKey: "key" },
      nodePlatform,
      { transport: waitingTransport },
    );
    const pending = client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
      signal: controller.signal,
    });
    controller.abort();
    await expect(pending).rejects.toBeInstanceOf(AbortError);
  });
});

describe("validation and protocol handling", () => {
  it.each([
    [{ maxFrames: 0 }, "invalid_max_frames"],
    [{ maxFrames: 101 }, "invalid_max_frames"],
    [{ maxFrames: 1.5 }, "invalid_max_frames"],
    [{ sampleRate: 0 }, "invalid_sample_rate"],
    [{ sampleRate: 1.5 }, "invalid_sample_rate"],
  ] as const)("rejects invalid video options", async (options, code) => {
    const client = new NeuroVerifyClient({ apiKey: "key" });
    await expect(
      client.detectVideo(new Uint8Array([1]), {
        filename: "clip.mp4",
        ...options,
      }),
    ).rejects.toMatchObject({ code });
  });

  it("rejects empty uploads and unnamed byte arrays", async () => {
    const client = new NeuroVerifyClient({ apiKey: "key" });
    await expect(client.detectImage(new Uint8Array())).rejects.toMatchObject({
      code: "filename_required",
    });
    await expect(
      client.detectImage(new Uint8Array(), { filename: "empty.jpg" }),
    ).rejects.toMatchObject({ code: "empty_file" });
  });

  it("warns rather than rejects an unusual extension", async () => {
    const warning = vi.fn();
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({
      apiKey: "key",
      fetch,
      onWarning: warning,
    });
    await client.detectImage(new Uint8Array([1]), { filename: "photo.bin" });
    expect(warning).toHaveBeenCalledWith(
      expect.objectContaining({ code: "unsupported_extension" }),
    );
  });

  it.each([
    [
      "invalid billable",
      { ...imageSuccess.unified_face_authenticity_score, billable: "maybe" },
    ],
    [
      "missing nullable field",
      (() => {
        const value = { ...imageSuccess.unified_face_authenticity_score };
        delete (value as Partial<typeof value>).risk_score;
        return value;
      })(),
    ],
    [
      "score below contract range",
      { ...imageSuccess.unified_face_authenticity_score, risk_score: 0 },
    ],
    [
      "score above contract range",
      { ...imageSuccess.unified_face_authenticity_score, risk_score: 10.1 },
    ],
  ])("rejects %s response data", async (_name, envelope) => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(
        jsonResponse({ unified_face_authenticity_score: envelope }),
      );
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(ProtocolError);
  });

  it("maps an unexpected status to HttpError and rejects a non-rejection HTTP 400", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(jsonResponse({ detail: "Missing" }, 404))
      .mockResolvedValueOnce(jsonResponse(imageSuccess, 400));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(HttpError);
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toBeInstanceOf(HttpError);
  });

  it("redacts the API key from server-supplied error text", async () => {
    const body = {
      unified_face_authenticity_score: {
        ...imageServerError.unified_face_authenticity_score,
        message: "failure for secret-key",
        future: { echo: "secret-key" },
      },
    };
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(body));
    const client = new NeuroVerifyClient({ apiKey: "secret-key", fetch });
    const error = await client
      .detectImage(new Uint8Array([1]), { filename: "photo.jpg" })
      .catch((caught: unknown) => caught);
    expect(error).toMatchObject({ statusCode: 200, requestId: "trx_test" });
    expect(String(error)).not.toContain("secret-key");
    expect(JSON.stringify((error as { raw?: unknown }).raw)).not.toContain(
      "secret-key",
    );
  });

  it.each([
    [new Response("{", { status: 200 }), "malformed JSON"],
    [jsonResponse({ status: "success" }), "missing"],
  ])("rejects malformed protocol responses", async (response, message) => {
    const fetch = vi.fn<typeof globalThis.fetch>().mockResolvedValue(response);
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    await expect(
      client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
    ).rejects.toThrowError(ProtocolError);
    await expect(Promise.reject(new ProtocolError(message))).rejects.toThrow(
      message,
    );
  });

  it.each([
    [401, "authentication"],
    [503, "server"],
  ])(
    "preserves typed HTTP errors for malformed HTTP %i bodies",
    async (status, kind) => {
      const fetch = vi
        .fn<typeof globalThis.fetch>()
        .mockResolvedValue(
          new Response("<html>unavailable</html>", { status }),
        );
      const client = new NeuroVerifyClient({
        apiKey: "key",
        fetch,
        maxRetries: 0,
      });
      const pending = client.detectImage(new Uint8Array([1]), {
        filename: "photo.jpg",
      });
      if (kind === "authentication") {
        await expect(pending).rejects.toBeInstanceOf(AuthenticationError);
      } else {
        await expect(pending).rejects.toBeInstanceOf(ServerError);
      }
    },
  );

  it.each([
    [401, {}, AuthenticationError],
    [503, {}, ServerError],
    [503, { unified_face_authenticity_score: {} }, ServerError],
  ] as const)(
    "preserves typed HTTP %i errors for structurally malformed JSON",
    async (status, body, ErrorClass) => {
      const fetch = vi
        .fn<typeof globalThis.fetch>()
        .mockResolvedValue(jsonResponse(body, status));
      const client = new NeuroVerifyClient({
        apiKey: "key",
        fetch,
        maxRetries: 0,
      });
      await expect(
        client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" }),
      ).rejects.toBeInstanceOf(ErrorClass);
    },
  );

  it("enforces size limits before transport", async () => {
    const oversizedPlatform: PlatformAdapter = {
      name: "browser",
      env: () => undefined,
      prepare: async () => ({
        filename: "huge.jpg",
        size: 10 * 1024 * 1024 + 1,
        createUpload: async () => new Blob(["x"]),
      }),
    };
    const transport: Transport = { execute: vi.fn() };
    const client = new NeuroVerifyClientBase<Blob>(
      { apiKey: "key" },
      oversizedPlatform,
      { transport },
    );
    await expect(client.detectImage(new Blob(["x"]))).rejects.toMatchObject({
      code: "file_too_large",
    });
    expect(transport.execute).not.toHaveBeenCalled();
  });
});

describe("MIME type resolution", () => {
  it.each([
    ["photo.jpg", "image/jpeg"],
    ["photo.jpeg", "image/jpeg"],
    ["photo.png", "image/png"],
    ["photo.bmp", "image/bmp"],
    ["photo.tif", "image/tiff"],
    ["photo.tiff", "image/tiff"],
    ["photo.webp", "image/webp"],
    ["photo.heic", "image/heic"],
    ["photo.heif", "image/heif"],
    ["clip.mp4", "video/mp4"],
    ["clip.avi", "video/vnd.avi"],
    ["clip.mov", "video/quicktime"],
    ["clip.mkv", "video/matroska"],
    ["clip.wmv", "video/x-ms-wmv"],
    ["clip.flv", "video/x-flv"],
    ["clip.webm", "video/webm"],
    ["clip.ogg", "video/ogg"],
    ["clip.ogv", "video/ogg"],
    ["unknown.xyz", "application/octet-stream"],
  ])("resolves %s to %s", async (filename, expectedMime) => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    await client.detectImage(new Uint8Array([1]), { filename });
    const form = fetch.mock.calls[0]![1]?.body as FormData;
    const file = form.get("file") as File;
    expect(file.type).toBe(expectedMime);
  });

  it("uses canonical extension MIME over conflicting Blob metadata", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });

    await client.detectImage(new Blob(["x"], { type: "image/png" }), {
      filename: "photo.jpg",
    });

    const form = fetch.mock.calls[0]![1]?.body as FormData;
    expect((form.get("file") as File).type).toBe("image/jpeg");
  });

  it("preserves explicit Blob MIME for an unknown extension", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });

    await client.detectImage(new Blob(["x"], { type: "image/png" }), {
      filename: "photo.custom",
    });

    const form = fetch.mock.calls[0]![1]?.body as FormData;
    expect((form.get("file") as File).type).toBe("image/png");
  });
});

describe("normalized JSON serialization", () => {
  it("excludes raw and originalStatus from JSON.stringify on success", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });

    const serialized = JSON.parse(JSON.stringify(result));
    expect(serialized).not.toHaveProperty("raw");
    expect(serialized).not.toHaveProperty("originalStatus");
    expect(serialized.uniqueTrxId).toBe("trx_test");
    expect(serialized.status).toBe("success");
    expect(serialized.riskScore).toBe(2.2);
    expect(serialized.riskLevel).toBe("low");
  });

  it("preserves raw as a directly accessible frozen object", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValue(jsonResponse(imageSuccess));
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });

    expect(result.raw).toBeDefined();
    expect(Object.isFrozen(result.raw)).toBe(true);
    expect(result.raw.unique_trx_id).toBe("trx_test");
  });

  it("excludes raw from video success JSON", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>().mockResolvedValue(
      jsonResponse({
        unified_video_authenticity_score: {
          unique_trx_id: "trx_video",
          filename: "clip.mp4",
          content_type: "video/mp4",
          status: "success",
          status_code: 1,
          billable: "Y",
          video_risk_score: 9,
          video_risk_level: "high",
          video_message: "Deepfake",
          audio_risk_score: null,
          audio_risk_level: null,
          audio_message: null,
          ai_threat_signals: [],
        },
      }),
    );
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    const result = await client.detectVideo(new Uint8Array([1]), {
      filename: "clip.mp4",
    });

    const serialized = JSON.parse(JSON.stringify(result));
    expect(serialized).not.toHaveProperty("raw");
    expect(serialized).not.toHaveProperty("originalStatus");
    expect(serialized.videoRiskScore).toBe(9);
    expect(result.raw).toBeDefined();
  });

  it("includes originalStatus in unknown result JSON", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>().mockResolvedValue(
      jsonResponse({
        unified_face_authenticity_score: {
          unique_trx_id: "trx_test",
          filename: "photo.jpg",
          content_type: "image/jpeg",
          status: "pending",
          status_code: 99,
          billable: "N",
          risk_score: null,
          risk_level: null,
          message: "Processing",
          ai_threat_signals: [],
        },
      }),
    );
    const client = new NeuroVerifyClient({ apiKey: "key", fetch });
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });

    expect(result.status).toBe("unknown");
    const serialized = JSON.parse(JSON.stringify(result));
    expect(serialized).not.toHaveProperty("raw");
    expect(serialized.originalStatus).toBe("pending");
    expect(result.raw).toBeDefined();
  });
});

describe("generated core adapter", () => {
  it("uses raw methods and recovers runtime.ResponseError.response", async () => {
    class ResponseError extends Error {
      override name = "ResponseError";
      constructor(readonly response: Response) {
        super("generated response error");
      }
    }
    const errorResponse = jsonResponse({ detail: "Invalid" }, 401);
    const imageApi = {
      detectImageRaw: vi
        .fn()
        .mockRejectedValue(new ResponseError(errorResponse)),
    };
    const videoApi = {
      detectVideoRaw: vi.fn(),
    };
    const adapter = new GeneratedCoreTransport(imageApi, videoApi);
    const result = await adapter.execute({
      kind: "image",
      file: new Blob(["x"]),
      filename: "photo.jpg",
      apiKey: "key",
      baseUrl: "https://example.com",
      signal: new AbortController().signal,
    });
    expect(result).toBe(errorResponse);
    expect(imageApi.detectImageRaw).toHaveBeenCalledOnce();
  });
});
