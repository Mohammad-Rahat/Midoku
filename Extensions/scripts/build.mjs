import { build } from "esbuild";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const methods = {
    search: ["search"], feeds: ["getFeeds", "getFeedPage"], details: ["getMangaDetails"],
    chapters: ["getChapterPage"], pages: ["getChapterPages"]
};

function validDomainPermission(value) {
    if (typeof value !== "string") return false;
    const host = value.startsWith("*.") ? value.slice(2) : value;
    return host.length <= 253 &&
        /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(host) &&
        /[a-z]/.test(host) && host.split(".").every(label => label.length <= 63) &&
        !["localhost", "local", "internal", "home", "lan", "test", "invalid"].includes(host.split(".").at(-1));
}

export function validateManifest(manifest) {
    if (manifest.contractVersion !== 1 ||
        !/^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$/.test(manifest.id) ||
        !/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(manifest.version) ||
        typeof manifest.name !== "string" || !manifest.name.trim() || manifest.name.length > 100 ||
        !Array.isArray(manifest.capabilities) || !manifest.capabilities.length ||
        manifest.capabilities.some(value => !Object.hasOwn(methods, value)) ||
        !Array.isArray(manifest.domains) || manifest.domains.length > 32 ||
        new Set(manifest.domains).size !== manifest.domains.length ||
        manifest.domains.some(value => !validDomainPermission(value))) {
        throw new Error("Invalid extension manifest");
    }
    return manifest;
}

export async function buildSource(directory) {
    const manifest = validateManifest(JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8")));
    const output = await build({
        absWorkingDir: tmpdir(),
        entryPoints: [path.join(directory, "index.ts")],
        bundle: true, format: "iife", globalName: "MidokuExtension",
        platform: "neutral", target: "es2020", write: false, legalComments: "none",
        tsconfigRaw: {},
        // Resolve only explicit local modules, without ambient Node packages or ancestor configs.
        plugins: [{
            name: "midoku-source-modules",
            setup(builder) {
                builder.onResolve({ filter: /.*/ }, args => {
                    if (args.kind !== "entry-point" && !args.path.startsWith(".")) {
                        throw new Error("Unsupported runtime import: " + args.path);
                    }
                    const candidate = args.kind === "entry-point" ? args.path
                        : path.resolve(path.dirname(args.importer), args.path);
                    const relative = path.relative(root, candidate);
                    if (relative.startsWith("..") || path.isAbsolute(relative)) {
                        throw new Error("Imports must remain inside Extensions/");
                    }
                    const file = [candidate, candidate + ".ts", candidate + ".js"]
                        .find(value => /\.(ts|js)$/.test(value) && existsSync(value));
                    if (!file) throw new Error("Cannot resolve local module: " + args.path);
                    return { path: file, namespace: "midoku" };
                });
                builder.onLoad({ filter: /.*/, namespace: "midoku" }, args => ({
                    contents: readFileSync(args.path, "utf8"),
                    loader: args.path.endsWith(".ts") ? "ts" : "js"
                }));
            }
        }]
    });
    const javaScript = output.outputFiles[0].text;
    if (Buffer.byteLength(javaScript) > 2 * 1024 * 1024) throw new Error("Bundle exceeds 2 MiB");
    const destination = path.join(root, "dist", manifest.id);
    await mkdir(destination, { recursive: true });
    await writeFile(path.join(destination, "bundle.js"), javaScript);
    await writeFile(path.join(destination, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
    return { manifest, javaScript };
}

function swiftLiteral(value) {
    // Avoid both closing the raw literal and accidentally enabling Swift interpolation.
    let delimiter = "#";
    while (value.includes('"""' + delimiter) || value.includes(String.fromCharCode(92) + delimiter + "(")) {
        delimiter += "#";
    }
    return delimiter + '"""\n' + value + '\n"""' + delimiter;
}

async function main() {
    const fixtureA = await buildSource(path.join(root, "fixtures/source-a"));
    const fixtureB = await buildSource(path.join(root, "fixtures/source-b"));
    let sources = [];
    try { sources = await readdir(path.join(root, "sources"), { withFileTypes: true }); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    const builtSources = new Map();
    for (const source of sources.filter(entry => entry.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
        const built = await buildSource(path.join(root, "sources", source.name));
        if (built.manifest.id !== source.name || builtSources.has(built.manifest.id)) {
            throw new Error("Source directories must have unique matching manifest IDs");
        }
        builtSources.set(built.manifest.id, built);
    }
    // Explicit review list: creating a source never automatically makes it executable in the app.
    const selected = JSON.parse(await readFile(path.join(root, "bundled.json"), "utf8"));
    if (!Array.isArray(selected) || new Set(selected).size !== selected.length ||
        selected.some(id => typeof id !== "string" || !builtSources.has(id))) {
        throw new Error("bundled.json must list unique built source IDs");
    }
    const bundled = selected.map(id => builtSources.get(id));
    const entries = bundled.map(source => "        (manifestJSON: " +
        swiftLiteral(JSON.stringify(source.manifest)) + ", javaScript: " + swiftLiteral(source.javaScript) + ")");
    const catalogue = "// Generated by Extensions/scripts/build.mjs from reviewed bundled.json. Do not edit.\n" +
        "nonisolated enum BundledExtensionResources {\n" +
        "    static let entries: [(manifestJSON: String, javaScript: String)] = [\n" +
        entries.join(",\n") + "\n    ]\n}\n";
    await writeFile(path.join(root, "../Midoku/Extensions/Core/BundledExtensionResources.swift"), catalogue);
    // Checked-in debug-only Swift embeds the exact bundles tested by the Node runner.
    const literal = swiftLiteral;
    const swift = "// Generated by Extensions/scripts/build.mjs. Do not edit.\n#if DEBUG\n" +
        "nonisolated enum DevelopmentFixtureBundles {\n" +
        "    static let sourceA = " + literal(fixtureA.javaScript) + "\n" +
        "    static let sourceB = " + literal(fixtureB.javaScript) + "\n" +
        "}\n#endif\n";
    await writeFile(path.join(root, "../Midoku/Development/DevelopmentFixtureBundles.swift"), swift);
    const testFixtures = path.join(root, "../Tests/Extensions/Fixtures");
    await mkdir(testFixtures, { recursive: true });
    for (const [name, fixture] of [["source-a", fixtureA], ["source-b", fixtureB]]) {
        await writeFile(path.join(testFixtures, name + ".js"), fixture.javaScript);
        await writeFile(path.join(testFixtures, name + ".json"), JSON.stringify(fixture.manifest, null, 2) + "\n");
    }
    console.log("Built fixtures, " + builtSources.size + " local source(s), and " + bundled.length + " bundled source(s).");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
