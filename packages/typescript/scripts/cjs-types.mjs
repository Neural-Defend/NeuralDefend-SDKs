import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

async function declarations(directory) {
  const output = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...(await declarations(path)));
    else if (entry.name.endsWith(".d.ts")) output.push(path);
  }
  return output;
}

for (const path of await declarations(
  fileURLToPath(new URL("../dist", import.meta.url)),
)) {
  const target = path.replace(/\.d\.ts$/, ".d.cts");
  const source = await readFile(path, "utf8");
  await writeFile(
    target,
    source
      .replaceAll(/(from\s+["'][^"']+)\.js(["'])/g, "$1.cjs$2")
      .replaceAll(/(import\(["'][^"']+)\.js(["']\))/g, "$1.cjs$2")
      .replace(/^\/\/# sourceMappingURL=.*$/gm, ""),
  );
}
