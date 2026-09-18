import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const [id, name] = process.argv.slice(2);
if (!id || !/^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$/.test(id) || !name?.trim()) {
    throw new Error('Usage: npm run create -- dev.publisher.source "Source name"');
}
const directory = path.join(root, "sources", id);
await mkdir(path.dirname(directory), { recursive: true });
await mkdir(directory); // Fail if it exists; never overwrite an adapter.
const manifest = JSON.parse(await readFile(path.join(root, "template/manifest.json"), "utf8"));
await writeFile(path.join(directory, "manifest.json"), JSON.stringify({ ...manifest, id, name }, null, 2) + "\n");
const starter = await readFile(path.join(root, "template/index.ts"), "utf8");
await writeFile(path.join(directory, "index.ts"), starter.replace("../sdk/index", "../../sdk/index"));
console.log("Created " + path.relative(root, directory) + ". Add verified hosts and implement search.");
