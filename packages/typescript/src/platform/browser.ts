import { ValidationError } from "../errors.js";
import { mimeForFilename } from "../media.js";
import type { PlatformAdapter, PreparedMedia } from "./types.js";

interface BlobMetadata {
  readonly blob: Blob;
  readonly size: number;
  readonly type: string;
}

interface FileMetadata {
  readonly name: string;
  readonly lastModified: number;
}

function nativeBlobMetadata(value: unknown): BlobMetadata | null {
  if (typeof value !== "object" || value === null) return null;
  try {
    const size = Object.getOwnPropertyDescriptor(
      Blob.prototype,
      "size",
    )!.get!.call(value) as number;
    const type = Object.getOwnPropertyDescriptor(
      Blob.prototype,
      "type",
    )!.get!.call(value) as string;
    Blob.prototype.slice.call(value, 0, 0);
    return { blob: value as Blob, size, type };
  } catch {
    return null;
  }
}

function nativeFileMetadata(value: unknown): FileMetadata | null {
  if (typeof File === "undefined") return null;
  try {
    const name = Object.getOwnPropertyDescriptor(
      File.prototype,
      "name",
    )!.get!.call(value) as string;
    const lastModified = Object.getOwnPropertyDescriptor(
      File.prototype,
      "lastModified",
    )!.get!.call(value) as number;
    return { name, lastModified };
  } catch {
    return null;
  }
}

export const browserPlatform: PlatformAdapter = {
  name: "browser",
  env: () => undefined,
  async prepare(input, requestedFilename): Promise<PreparedMedia> {
    const blob = nativeBlobMetadata(input);
    if (blob === null) {
      throw new ValidationError(
        "unsupported_input",
        "Browser uploads must be a File or Blob.",
      );
    }
    const file = nativeFileMetadata(input);

    const filename = requestedFilename ?? file?.name;
    if (!filename) {
      throw new ValidationError(
        "filename_required",
        "A filename is required when uploading a plain Blob.",
      );
    }

    return {
      filename,
      size: blob.size,
      async createUpload() {
        return new File([blob.blob], filename, {
          type: mimeForFilename(
            filename,
            blob.type || "application/octet-stream",
          ),
          lastModified: file?.lastModified ?? Date.now(),
        });
      },
    };
  },
};
