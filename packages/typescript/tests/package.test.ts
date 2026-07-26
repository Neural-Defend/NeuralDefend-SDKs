import { createRequire } from "node:module";
import { readFile, stat } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";

describe("built package", () => {
  it("ships loadable ESM and CommonJS entry points", async () => {
    const esmPath = "../dist/index.js";
    const esm = await import(esmPath);
    const require = createRequire(import.meta.url);
    const cjs = require("../dist/index.cjs") as typeof esm;
    expect(esm.NeuroVerifyClient).toEqual(expect.any(Function));
    expect(cjs.NeuroVerifyClient).toEqual(expect.any(Function));
  });

  it("keeps the browser bundle free of Node built-ins and environment access", async () => {
    const browser = await readFile(
      new URL("../dist/browser.js", import.meta.url),
      "utf8",
    );
    expect(browser).not.toContain("node:");
    expect(browser).not.toContain("process.env");
    expect(browser).not.toContain("nodePlatform");
  });

  it("stays below 20 kB minzipped per public ESM entry", async () => {
    for (const entry of ["index.js", "browser.js"]) {
      const path = new URL(`../dist/${entry}`, import.meta.url);
      expect((await stat(path)).size).toBeGreaterThan(0);
      expect(gzipSync(await readFile(path)).byteLength).toBeLessThan(20_000);
    }
  });
});
