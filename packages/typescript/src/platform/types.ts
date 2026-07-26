export type DetectionKind = "image" | "video";

export interface PreparedMedia {
  readonly filename: string;
  readonly size: number;
  createUpload(): Promise<Blob>;
  dispose?(): Promise<void>;
}

export interface PlatformAdapter {
  readonly name: "browser" | "node";
  env(name: string): string | undefined;
  prepare(
    input: unknown,
    filename: string | undefined,
    kind: DetectionKind,
    signal?: AbortSignal,
  ): Promise<PreparedMedia>;
}
