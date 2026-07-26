import { AbortError, ValidationError } from "../errors.js";
import { IMAGE_MAX_BYTES, VIDEO_MAX_BYTES, mimeForFilename } from "../media.js";
import type { DetectionKind, PlatformAdapter, PreparedMedia } from "./types.js";

function basename(path: string): string {
  return path.replaceAll("\\", "/").split("/").at(-1) ?? path;
}

function isFile(value: Blob): value is File {
  return (
    typeof (value as { name?: unknown }).name === "string" &&
    typeof (value as { lastModified?: unknown }).lastModified === "number"
  );
}

async function createNodeFile(
  parts: unknown[],
  filename: string,
  type: string,
): Promise<File> {
  const { File: NodeFile } = await import("node:buffer");
  return new NodeFile(
    parts as ConstructorParameters<typeof NodeFile>[0],
    filename,
    { type },
  ) as File;
}

function isReadableStream(value: unknown): value is AsyncIterable<unknown> & {
  destroy?: () => void;
  path?: unknown;
} {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { [Symbol.asyncIterator]?: unknown })[
      Symbol.asyncIterator
    ] === "function"
  );
}

async function prepareStream(
  input: AsyncIterable<unknown> & {
    destroy?: () => void;
    path?: unknown;
  },
  requestedFilename: string | undefined,
  kind: DetectionKind,
  signal?: AbortSignal,
): Promise<PreparedMedia> {
  const filename =
    requestedFilename ??
    (typeof input.path === "string" ? basename(input.path) : undefined);
  if (!filename) {
    throw new ValidationError(
      "filename_required",
      "A filename is required when uploading a Node.js stream.",
    );
  }

  const [{ mkdtemp, open, rm }, { tmpdir }, { join }] = await Promise.all([
    import("node:fs/promises"),
    import("node:os"),
    import("node:path"),
  ]);
  const directory = await mkdtemp(join(tmpdir(), "neuraldefend-"));
  const temporaryPath = join(directory, "upload");
  const handle = await open(temporaryPath, "wx", 0o600);
  const maxBytes = kind === "image" ? IMAGE_MAX_BYTES : VIDEO_MAX_BYTES;
  let size = 0;
  let iterator: AsyncIterator<unknown> | undefined;
  try {
    const activeIterator = input[Symbol.asyncIterator]();
    iterator = activeIterator;
    while (true) {
      if (signal?.aborted) {
        throw new AbortError("The request was aborted.");
      }
      const next = await new Promise<IteratorResult<unknown>>(
        (resolve, reject) => {
          const onAbort = () =>
            reject(new AbortError("The request was aborted."));
          signal?.addEventListener("abort", onAbort, { once: true });
          activeIterator
            .next()
            .then(resolve, reject)
            .finally(() => {
              signal?.removeEventListener("abort", onAbort);
            });
        },
      );
      if (next.done) break;
      const chunk = next.value;
      let bytes: Uint8Array;
      if (typeof chunk === "string") {
        bytes = new TextEncoder().encode(chunk);
      } else if (chunk instanceof Uint8Array) {
        bytes = chunk;
      } else {
        throw new ValidationError(
          "unsupported_input",
          "Node.js streams must emit strings, Buffers, or Uint8Array chunks.",
        );
      }
      size += bytes.byteLength;
      if (size > maxBytes) {
        throw new ValidationError(
          "file_too_large",
          `The ${kind} exceeds the maximum upload size.`,
        );
      }
      await handle.writeFile(bytes);
    }
  } catch (error) {
    try {
      await iterator?.return?.();
    } catch {
      // Preserve the original validation or abort error.
    }
    try {
      input.destroy?.();
    } catch {
      // Preserve the original validation or abort error.
    }
    await handle.close();
    await rm(directory, { recursive: true, force: true });
    throw error;
  }
  await handle.close();

  return {
    filename,
    size,
    async createUpload() {
      const { openAsBlob } = await import("node:fs");
      const blob = await openAsBlob(temporaryPath);
      return createNodeFile(
        [blob],
        filename,
        mimeForFilename(filename, blob.type || "application/octet-stream"),
      );
    },
    async dispose() {
      await rm(directory, { recursive: true, force: true });
    },
  };
}

async function preparePath(
  input: string,
  requestedFilename: string | undefined,
  kind: DetectionKind,
  signal?: AbortSignal,
): Promise<PreparedMedia> {
  const [{ constants }, { lstat, open }] = await Promise.all([
    import("node:fs"),
    import("node:fs/promises"),
  ]);
  const filename = requestedFilename ?? basename(input);
  let pathStat;
  try {
    pathStat = await lstat(input);
  } catch {
    throw new ValidationError(
      "unsupported_input",
      "The upload path is not a readable file.",
    );
  }
  if (pathStat.isSymbolicLink() || !pathStat.isFile()) {
    throw new ValidationError(
      "unsupported_input",
      "The upload path must be a regular file and cannot be a symbolic link.",
    );
  }

  let source;
  try {
    source = await open(input, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch {
    throw new ValidationError(
      "unsupported_input",
      "The upload path is not a readable regular file.",
    );
  }

  try {
    const openedStat = await source.stat();
    if (
      !openedStat.isFile() ||
      openedStat.dev !== pathStat.dev ||
      openedStat.ino !== pathStat.ino
    ) {
      throw new ValidationError(
        "unsupported_input",
        "The upload path changed while it was being opened.",
      );
    }
    const stream = source.createReadStream({ autoClose: true });
    return await prepareStream(stream, filename, kind, signal);
  } finally {
    await source.close().catch(() => undefined);
  }
}

export const nodePlatform: PlatformAdapter = {
  name: "node",
  env: (name) => process.env[name],
  async prepare(
    input,
    requestedFilename,
    kind,
    signal,
  ): Promise<PreparedMedia> {
    if (typeof input === "string") {
      return preparePath(input, requestedFilename, kind, signal);
    }

    if (input instanceof Blob) {
      const filename =
        requestedFilename ?? (isFile(input) ? input.name : undefined);
      if (!filename) {
        throw new ValidationError(
          "filename_required",
          "A filename is required when uploading a plain Blob.",
        );
      }
      return {
        filename,
        size: input.size,
        async createUpload() {
          return createNodeFile(
            [input],
            filename,
            mimeForFilename(filename, input.type || "application/octet-stream"),
          );
        },
      };
    }

    if (input instanceof Uint8Array) {
      if (!requestedFilename) {
        throw new ValidationError(
          "filename_required",
          "A filename is required when uploading bytes.",
        );
      }
      const bytes = new Uint8Array(input);
      return {
        filename: requestedFilename,
        size: bytes.byteLength,
        async createUpload() {
          return createNodeFile(
            [bytes],
            requestedFilename,
            mimeForFilename(requestedFilename),
          );
        },
      };
    }

    if (isReadableStream(input)) {
      return prepareStream(input, requestedFilename, kind, signal);
    }

    throw new ValidationError(
      "unsupported_input",
      "Node.js uploads must be a path, stream, Uint8Array, Buffer, File, or Blob.",
    );
  },
};
