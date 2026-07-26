import { readFile } from "node:fs/promises";
import { describe, expect, it, vi } from "vitest";
import {
  AuthenticationError,
  NeuroVerifyClient,
  ProtocolError,
  RateLimitError,
  ScopeError,
  ServerError,
} from "../src/index.js";

interface Fixture {
  readonly http_status: number;
  readonly headers: Record<string, string>;
  readonly body_kind: "json" | "raw";
  readonly body: unknown;
}

async function fixture(path: string): Promise<Fixture> {
  const url = new URL(`../../../tests/fixtures/${path}`, import.meta.url);
  return JSON.parse(await readFile(url, "utf8")) as Fixture;
}

function response(value: Fixture): Response {
  return new Response(
    value.body_kind === "raw" ? String(value.body) : JSON.stringify(value.body),
    {
      status: value.http_status,
      headers: value.headers,
    },
  );
}

function clientFor(value: Fixture) {
  const fetch = vi
    .fn<typeof globalThis.fetch>()
    .mockResolvedValue(response(value));
  return {
    client: new NeuroVerifyClient({ apiKey: "test-key", fetch, maxRetries: 0 }),
    fetch,
  };
}

describe("shared image fixtures", () => {
  it.each([
    ["low-risk.json", "low"],
    ["medium-risk.json", "medium"],
    ["high-risk-spoof.json", "high"],
  ] as const)("maps scored %s", async (name, level) => {
    const value = await fixture(`image/documented/${name}`);
    const { client } = clientFor(value);
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });
    expect(result.status).toBe("success");
    if (result.status === "success") {
      expect(result.riskLevel).toBe(level);
      expect(result.riskScore).toEqual(expect.any(Number));
      expect(result.scored).toBe(true);
    }
  });

  it.each([
    ["no-face.json", true],
    ["multiple-faces.json", true],
    ["blurry.json", false],
    ["nsfw.json", false],
    ["security-rejection.json", false],
    ["unsupported-format.json", false],
    ["too-large.json", false],
  ] as const)("returns %s as a rejection", async (name, billable) => {
    const value = await fixture(`image/documented/${name}`);
    const { client } = clientFor(value);
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });
    expect(result).toMatchObject({
      status: "rejected",
      rejected: true,
      billable,
      riskScore: null,
      riskLevel: null,
    });
  });

  it("preserves and deeply freezes unknown fields", async () => {
    const value = await fixture("image/robustness/unknown-extra-field.json");
    const { client } = clientFor(value);
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });
    expect(Object.isFrozen(result.raw)).toBe(true);
    expect(result.raw).toHaveProperty("future_signal");
  });

  it.each([
    ["unknown-status.json", "pending"],
    ["unknown-risk-level.json", "success"],
    ["unknown-status-code.json", "success"],
  ] as const)("degrades %s without throwing", async (name, originalStatus) => {
    const value = await fixture(`image/robustness/${name}`);
    const { client } = clientFor(value);
    const result = await client.detectImage(new Uint8Array([1]), {
      filename: "photo.jpg",
    });
    if (name === "unknown-status-code.json") {
      expect(result.status).toBe("success");
      expect(result.statusCode).not.toBe(1);
    } else {
      expect(result).toMatchObject({ status: "unknown", originalStatus });
    }
  });
});

describe("shared video fixtures", () => {
  it.each([
    "both-low.json",
    "video-high-audio-low.json",
    "video-low-audio-high.json",
    "both-high.json",
  ])("maps dual-modality success %s", async (name) => {
    const value = await fixture(`video/documented/${name}`);
    const { client } = clientFor(value);
    const result = await client.detectVideo(new Uint8Array([1]), {
      filename: "clip.mp4",
    });
    expect(result.status).toBe("success");
    if (result.status === "success") {
      expect(result.hasAudio).toBe(true);
      expect(result.overallRiskScore).toBe(
        Math.max(result.videoRiskScore, result.audioRiskScore ?? 0),
      );
    }
  });

  it.each(["silent-no-audio.json", "medium-no-audio.json"])(
    "maps %s as success without audio",
    async (name) => {
      const value = await fixture(`video/documented/${name}`);
      const { client } = clientFor(value);
      const result = await client.detectVideo(new Uint8Array([1]), {
        filename: "clip.mp4",
      });
      expect(result).toMatchObject({
        status: "success",
        hasAudio: false,
        audioRiskScore: null,
        audioRiskLevel: null,
      });
    },
  );

  it.each([
    "no-face.json",
    "multiple-faces.json",
    "security-rejection.json",
    "unsupported-format.json",
    "too-large.json",
  ])("returns %s as a rejection", async (name) => {
    const value = await fixture(`video/documented/${name}`);
    const { client } = clientFor(value);
    const result = await client.detectVideo(new Uint8Array([1]), {
      filename: "clip.mp4",
    });
    expect(result.status).toBe("rejected");
  });

  it("preserves and deeply freezes unknown video fields", async () => {
    const value = await fixture("video/robustness/unknown-extra-field.json");
    const { client } = clientFor(value);
    const result = await client.detectVideo(new Uint8Array([1]), {
      filename: "clip.mp4",
    });
    expect(Object.isFrozen(result.raw)).toBe(true);
    expect(result.raw).toHaveProperty("future_signal");
  });

  it.each([
    ["unknown-status.json", "pending"],
    ["unknown-risk-level.json", "success"],
    ["unknown-status-code.json", "success"],
  ] as const)(
    "degrades video %s without throwing",
    async (name, originalStatus) => {
      const value = await fixture(`video/robustness/${name}`);
      const { client } = clientFor(value);
      const result = await client.detectVideo(new Uint8Array([1]), {
        filename: "clip.mp4",
      });
      if (name === "unknown-status-code.json") {
        expect(result.status).toBe("success");
        expect(result.statusCode).not.toBe(1);
      } else {
        expect(result).toMatchObject({ status: "unknown", originalStatus });
      }
    },
  );
});

describe("HTTP error semantics", () => {
  it.each([
    ["image/synthetic/unauthorized-401.json", AuthenticationError],
    ["video/synthetic/unauthorized-401.json", AuthenticationError],
    ["image/synthetic/forbidden-403.json", ScopeError],
    ["video/synthetic/forbidden-403.json", ScopeError],
  ] as const)("maps %s and never retries", async (path, ErrorClass) => {
    const value = await fixture(path);
    const { client, fetch } = clientFor(value);
    const request = path.startsWith("image/")
      ? client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" })
      : client.detectVideo(new Uint8Array([1]), { filename: "clip.mp4" });
    await expect(request).rejects.toBeInstanceOf(ErrorClass);
    expect(fetch).toHaveBeenCalledOnce();
  });

  it.each([
    "image/synthetic/rate-limited-429.json",
    "video/synthetic/rate-limited-429.json",
  ])("maps exhausted rate limits with metadata for %s", async (path) => {
    const value = await fixture(path);
    const { client } = clientFor(value);
    const promise = path.startsWith("image/")
      ? client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" })
      : client.detectVideo(new Uint8Array([1]), { filename: "clip.mp4" });
    await expect(promise).rejects.toMatchObject({
      name: RateLimitError.name,
      retryAfter: 60,
      limit: "1000",
      remaining: "0",
    });
  });

  it.each([
    "image/documented/internal-error-500.json",
    "image/documented/service-unavailable-503.json",
    "video/documented/internal-error-500.json",
    "video/documented/service-unavailable-503.json",
  ])("raises ServerError for %s", async (path) => {
    const value = await fixture(path);
    const { client } = clientFor(value);
    const request = path.startsWith("image/")
      ? client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" })
      : client.detectVideo(new Uint8Array([1]), { filename: "clip.mp4" });
    await expect(request).rejects.toBeInstanceOf(ServerError);
  });

  it.each([
    "image/robustness/missing-envelope.json",
    "image/robustness/malformed-json.json",
    "video/robustness/missing-envelope.json",
    "video/robustness/malformed-json.json",
  ])("raises ProtocolError for %s", async (path) => {
    const value = await fixture(path);
    const { client } = clientFor(value);
    const request = path.startsWith("image/")
      ? client.detectImage(new Uint8Array([1]), { filename: "photo.jpg" })
      : client.detectVideo(new Uint8Array([1]), { filename: "clip.mp4" });
    await expect(request).rejects.toBeInstanceOf(ProtocolError);
  });
});
