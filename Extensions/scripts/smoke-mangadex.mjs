// Explicit opt-in live check. Never runs in npm test and never saves responses or images.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { setTimeout } from "node:timers/promises";
import vm from "node:vm";

const directory = new URL("../dist/dev.midoku.mangadex/", import.meta.url);
const manifest = JSON.parse(await readFile(new URL("manifest.json", directory), "utf8"));
const context = vm.createContext({});
vm.runInContext(await readFile(new URL("bundle.js", directory), "utf8"), context, { timeout: 1000 });
const adapter = context.MidokuExtension.default;
let count = 0;
let lastStart = 0;

function allowed(address) {
    const url = new URL(address);
    assert.equal(url.protocol, "https:");
    assert.ok(!url.username && !url.password && !url.port);
    assert.ok(manifest.domains.some(domain => domain.startsWith("*.")
        ? url.hostname.endsWith(domain.slice(1)) : url.hostname === domain));
    return url;
}

async function request(url, headers = {}) {
    allowed(url);
    assert.ok(++count <= 16, "Live check request budget exceeded");
    await setTimeout(Math.max(0, lastStart + 600 - Date.now()));
    lastStart = Date.now();
    const response = await fetch(url, {
        headers: { ...headers, "User-Agent": "MidokuDevelopment/0.1 (manual adapter smoke test)" },
        redirect: "error", signal: AbortSignal.timeout(30000)
    });
    // Stop immediately on challenges/errors; no automatic retry and no secret/header logging.
    assert.ok(response.ok, `HTTP ${response.status}; live check stopped`);
    assert.notEqual(response.headers.get("cf-mitigated"), "challenge", "Website verification required; test in the app");
    return response;
}

const host = {
    async request({ url, headers }) {
        const response = await request(url, headers);
        const body = await response.text();
        assert.ok(Buffer.byteLength(body) <= 8 * 1024 * 1024);
        return { url: response.url, status: response.status, headers: {}, body };
    }
};

const feeds = await adapter.getFeeds({}, host);
const filters = await adapter.getSearchFilters({}, host);
assert.ok(filters.some(filter => filter.id === "includedTags" && filter.options.length > 0));
const feed = await adapter.getFeedPage({ feedID: "popular", cursor: null }, host);
const search = await adapter.search({ query: process.argv[2] || "Yotsuba", cursor: null }, host);
const manga = search.items[0] ?? feed.items[0];
assert.ok(manga, "No manga available for the live check");
const details = await adapter.getMangaDetails({ mangaID: manga.id }, host);
let chapters = await adapter.getChapterPage({ mangaID: manga.id, cursor: null }, host);
for (let index = 0; !chapters.items.length && chapters.nextCursor && index < 2; index++) {
    chapters = await adapter.getChapterPage({ mangaID: manga.id, cursor: chapters.nextCursor }, host);
}
assert.ok(chapters.items.length, "No readable English chapter available for the live check");
const pages = await adapter.getChapterPages({ mangaID: manga.id, chapterID: chapters.items[0].id }, host);
assert.ok(pages.length);
for (const page of pages) allowed(page.url);
const image = await request(pages[0].url, pages[0].headers);
assert.ok(image.headers.get("content-type")?.startsWith("image/"), "First page is not an image response");
let imageBytes = 0;
for await (const chunk of image.body) {
    imageBytes += chunk.byteLength;
    assert.ok(imageBytes <= 8 * 1024 * 1024, "Image exceeds live-check limit");
}
assert.ok(imageBytes > 0);
console.log(JSON.stringify({
    source: manifest.name, title: details.title, feeds: feeds.length, filters: filters.length,
    searchResults: search.items.length, feedResults: feed.items.length,
    chaptersInPage: chapters.items.length, pageCount: pages.length,
    firstImageBytes: imageBytes, requests: count
}, null, 2));
console.log("Live adapter/API smoke passed. This does not validate iOS sessions, a reader, or Cloudflare clearance.");
