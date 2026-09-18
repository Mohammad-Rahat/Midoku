import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { cp, mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import path from "node:path";
import { root, validateManifest } from "../scripts/build.mjs";

async function load(id) {
    const source = await readFile(path.join(root, "dist", id, "bundle.js"), "utf8");
    const manifest = JSON.parse(await readFile(path.join(root, "dist", id, "manifest.json"), "utf8"));
    const context = vm.createContext({});
    vm.runInContext(source, context, { timeout: 1000 });
    return { adapter: context.MidokuExtension.default, manifest };
}

const noNetwork = { request() { throw new Error("Fixtures must not access the network"); } };

test("fixture bundles use the real contract and preserve source-specific identities", async () => {
    const a = await load("dev.midoku.fixture-a");
    const b = await load("dev.midoku.fixture-b");
    for (const { adapter, manifest } of [a, b]) {
        validateManifest(manifest);
        const result = await adapter.search({ query: "missing", cursor: null }, noNetwork);
        assert.equal(result.items[0].id, "fixture-manga");
        assert.equal(result.nextCursor, null);
        assert.equal((await adapter.getFeeds({}, noNetwork))[0].id, "all");
    }
    const ca = (await a.adapter.getChapterPage({ mangaID: "fixture-manga" }, noNetwork)).items;
    const cb = (await b.adapter.getChapterPage({ mangaID: "fixture-manga" }, noNetwork)).items;
    assert.equal(ca.length, 39);
    assert.equal(cb.length, 40);
    assert.equal(ca.some(chapter => chapter.number === "21"), false);
    assert.equal(cb.find(chapter => chapter.number === "21").id, "b:21");
    assert.equal(ca.find(chapter => chapter.number === "20").id, "a:20");
    assert.equal(ca.find(chapter => chapter.number === "22").id, "a:22");
});

test("fixture errors do not masquerade as empty chapter lists", async () => {
    const { adapter } = await load("dev.midoku.fixture-a");
    await assert.rejects(adapter.getChapterPage({ mangaID: "missing" }, noNetwork));
});

test("manifest validation rejects incompatible contracts, private hosts, and broad permissions", async () => {
    const { manifest } = await load("dev.midoku.fixture-a");
    validateManifest({ ...manifest, domains: ["*.mangadex.network"] });
    for (const patch of [
        { contractVersion: 2 }, { version: "1.9" }, { capabilities: ["unknown"] },
        { domains: ["*.com"] }, { domains: ["127.0.0.1"] },
        { domains: ["example.local"] }, { domains: ["example.com", "example.com"] },
        { domains: ["*.*.example.com"] }, { domains: ["foo*.example.com"] }, { domains: ["*.127.0.0.1"] }
    ]) {
        assert.throws(() => validateManifest({ ...manifest, ...patch }));
    }
});

test("scaffolding creates a local source, rejects traversal, and never overwrites one", async () => {
    const temporary = await mkdtemp(path.join(tmpdir(), "midoku-scaffold-"));
    try {
        await mkdir(path.join(temporary, "scripts"));
        await cp(path.join(root, "scripts/create.mjs"), path.join(temporary, "scripts/create.mjs"));
        await cp(path.join(root, "template"), path.join(temporary, "template"), { recursive: true });
        const run = promisify(execFile);
        const script = path.join(temporary, "scripts/create.mjs");
        await run(process.execPath, [script, "dev.midoku.scaffold", "Scaffold"]);
        const directory = path.join(temporary, "sources/dev.midoku.scaffold");
        const manifest = JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8"));
        assert.equal(manifest.id, "dev.midoku.scaffold");
        assert.equal(manifest.name, "Scaffold");
        assert.match(await readFile(path.join(directory, "index.ts"), "utf8"), /\.\.\/\.\.\/sdk\/index/);
        await assert.rejects(run(process.execPath, [script, "dev.midoku.scaffold", "Overwrite"]));
        await assert.rejects(run(process.execPath, [script, "../escape", "Escape"]));
        assert.equal(JSON.parse(await readFile(path.join(directory, "manifest.json"), "utf8")).name, "Scaffold");
    } finally {
        await rm(temporary, { recursive: true, force: true });
    }
});
