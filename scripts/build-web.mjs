import { copyFile, mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const outputDirectory = join(projectRoot, "dist");
const websiteFiles = ["index.html", "orbit-concept.css", "orbit-concept.js"];

await rm(outputDirectory, { recursive: true, force: true });
await mkdir(outputDirectory, { recursive: true });
await Promise.all(
  websiteFiles.map((file) => copyFile(join(projectRoot, file), join(outputDirectory, file))),
);

console.log(`Built Orbit website with ${websiteFiles.length} files.`);
