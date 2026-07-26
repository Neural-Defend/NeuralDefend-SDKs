import { ValidationError } from "./errors.js";
import type { ValidationWarning } from "./models.js";
import type { DetectionKind, PreparedMedia } from "./platform/types.js";

export const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
export const VIDEO_MAX_BYTES = 1_500_000_000;

const MIME_TYPES: Record<DetectionKind, Readonly<Record<string, string>>> = {
  image: {
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    bmp: "image/bmp",
    tif: "image/tiff",
    tiff: "image/tiff",
    webp: "image/webp",
    heic: "image/heic",
    heif: "image/heif",
  },
  video: {
    mp4: "video/mp4",
    avi: "video/vnd.avi",
    mov: "video/quicktime",
    mkv: "video/matroska",
    wmv: "video/x-ms-wmv",
    flv: "video/x-flv",
    webm: "video/webm",
    ogg: "video/ogg",
    ogv: "video/ogg",
  },
};

const EXTENSIONS: Record<DetectionKind, ReadonlySet<string>> = {
  image: new Set(Object.keys(MIME_TYPES.image)),
  video: new Set(Object.keys(MIME_TYPES.video)),
};

export function mimeForFilename(
  filename: string,
  fallback = "application/octet-stream",
): string {
  const ext = filename.toLowerCase().match(/\.([^.]+)$/)?.[1];
  return (ext && (MIME_TYPES.image[ext] ?? MIME_TYPES.video[ext])) || fallback;
}

export function validateMedia(
  media: PreparedMedia,
  kind: DetectionKind,
  onWarning: (warning: ValidationWarning) => void,
): void {
  if (media.size === 0) {
    throw new ValidationError("empty_file", "The upload is empty.");
  }

  const limit = kind === "image" ? IMAGE_MAX_BYTES : VIDEO_MAX_BYTES;
  if (media.size > limit) {
    throw new ValidationError(
      "file_too_large",
      `The ${kind} exceeds the ${kind === "image" ? "10 MB" : "1.5 GB"} limit.`,
    );
  }

  const extension = media.filename.toLowerCase().match(/\.([^.]+)$/)?.[1];
  if (!extension || !EXTENSIONS[kind].has(extension)) {
    onWarning({
      code: "unsupported_extension",
      filename: media.filename,
      message: `The .${extension ?? "(none)"} extension is not documented for ${kind} uploads; the server will inspect the content.`,
    });
  }
}

export function validateVideoOptions(
  maxFrames?: number,
  sampleRate?: number,
): void {
  if (
    maxFrames !== undefined &&
    (!Number.isInteger(maxFrames) || maxFrames < 1 || maxFrames > 100)
  ) {
    throw new ValidationError(
      "invalid_max_frames",
      "maxFrames must be an integer from 1 through 100.",
    );
  }
  if (
    sampleRate !== undefined &&
    (!Number.isInteger(sampleRate) || sampleRate < 1)
  ) {
    throw new ValidationError(
      "invalid_sample_rate",
      "sampleRate must be an integer greater than or equal to 1.",
    );
  }
}
