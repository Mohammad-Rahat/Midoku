import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

const mangaID = "00000001-1111-4111-8111-000000000001";
const chapterID = "00000003-1111-4111-8111-000000000003";
const plain = value => JSON.parse(JSON.stringify(value));
async function fixture(name) {
    return JSON.parse(await readFile(new URL(`../../Tests/Extensions/Fixtures/mangadex/${name}.json`, import.meta.url), "utf8"));
}
async function load() {
    const bundle = await readFile(new URL("../dist/dev.midoku.mangadex/bundle.js", import.meta.url), "utf8");
    const context = vm.createContext({});
    vm.runInContext(bundle, context, { timeout: 1000 });
    assert.equal(context.fetch, undefined);
    assert.equal(context.URL, undefined);
    return context.MidokuExtension.default;
}
function host(...responses) {
    const requests = [];
    return {
        requests,
        async request(request) {
            requests.push(plain(request));
            assert.ok(responses.length, "Unexpected extra request");
            assert.deepEqual(plain(request.headers), { Accept: "application/json", Referer: "https://mangadex.org/" });
            return { url: request.url, status: 200, headers: {}, body: JSON.stringify(responses.shift()) };
        }
    };
}

test("MangaDex search encodes queries, normalizes covers, and advances pagination", async () => {
    const adapter = await load();
    const first = await fixture("search");
    const network = host(first, { ...first, data: [], offset: 20, total: 20 });
    const page = await adapter.search({ query: "A & B", cursor: null }, network);
    assert.equal(page.items[0].id, mangaID);
    assert.equal(page.items[0].title, "The Test Atlas");
    assert.equal(page.items[0].coverURL, `https://uploads.mangadex.org/covers/${mangaID}/test-cover.jpg.256.jpg`);
    assert.equal(page.items[1].coverURL, null);
    assert.equal(page.nextCursor, "20");
    const url = new URL(network.requests[0].url);
    assert.equal(url.searchParams.get("title"), "A & B");
    assert.equal(url.searchParams.get("includes[]"), "cover_art");
    assert.equal(url.searchParams.get("availableTranslatedLanguage[]"), "en");
    assert.deepEqual(url.searchParams.getAll("contentRating[]"), ["safe", "suggestive"]);
    assert.deepEqual(plain(await adapter.search({ query: "A & B", cursor: page.nextCursor }, network)), { items: [], nextCursor: null });
    assert.equal(new URL(network.requests[1].url).searchParams.get("offset"), "20");
});

test("MangaDex feeds declare and use known API sorts", async () => {
    const adapter = await load();
    const feeds = await adapter.getFeeds({}, host());
    assert.deepEqual(plain(feeds.map(item => item.id)), ["latest", "popular", "recent"]);
    for (const [feedID, sort] of [["latest", "latestUploadedChapter"], ["popular", "followedCount"], ["recent", "createdAt"]]) {
        const network = host(await fixture("search"));
        await adapter.getFeedPage({ feedID }, network);
        assert.equal(new URL(network.requests[0].url).searchParams.get(`order[${sort}]`), "desc");
    }
    await assert.rejects(adapter.getFeedPage({ feedID: "unknown" }, host()));
});

test("MangaDex details prefer English and preserve IDs when locators change", async () => {
    const adapter = await load();
    const response = await fixture("details");
    const first = await adapter.getMangaDetails({ mangaID }, host(response));
    assert.equal(first.description, "Synthetic API fixture for Midoku.");
    response.data.relationships[0].attributes.fileName = "changed-cover.png";
    const second = await adapter.getMangaDetails({ mangaID }, host(response));
    assert.equal(first.id, second.id);
    assert.notEqual(first.coverURL, second.coverURL);
    response.data.attributes.title = { ja: "テスト" };
    response.data.attributes.altTitles = [{ en: "English alternative" }];
    assert.equal((await adapter.getMangaDetails({ mangaID }, host(response))).title, "English alternative");
    response.data.id = "00000002-1111-4111-8111-000000000002";
    await assert.rejects(adapter.getMangaDetails({ mangaID }, host(response)));
});

test("MangaDex chapters preserve fractional numbers and releases, filter unreadable entries, and keep global ordinals", async () => {
    const adapter = await load();
    const response = await fixture("chapters");
    const network = host(response);
    const page = await adapter.getChapterPage({ mangaID }, network);
    assert.deepEqual(plain(page.items.map(item => item.number)), ["20.5", "20.5", null]);
    assert.deepEqual(plain(page.items.map(item => item.ordinal)), [0, 1, 4]);
    assert.equal(page.items[2].title, "Oneshot");
    assert.equal(new Set(page.items.map(item => item.id)).size, 3);
    assert.equal(page.nextCursor, "100");
    const params = new URL(network.requests[0].url).searchParams;
    assert.equal(params.get("order[chapter]"), "asc");
    assert.equal(params.get("translatedLanguage[]"), "en");
    assert.equal(params.get("includeExternalUrl"), "0");
    const final = { ...response, data: [response.data[0]], offset: 100, total: 101 };
    const end = await adapter.getChapterPage({ mangaID, cursor: "100" }, host(final));
    assert.equal(end.items[0].ordinal, 100);
    assert.equal(end.nextCursor, null);
    response.data = [response.data[2]];
    const filtered = await adapter.getChapterPage({ mangaID }, host(response));
    assert.equal(filtered.items.length, 0);
    assert.equal(filtered.nextCursor, "100");
});

test("MangaDex pages validate parent identity and return ordered original-quality CDN descriptors", async () => {
    const adapter = await load();
    const network = host(await fixture("chapter"), await fixture("pages"));
    const pages = await adapter.getChapterPages({ mangaID, chapterID }, network);
    assert.deepEqual(plain(pages.map(item => item.id)), [`${chapterID}:1`, `${chapterID}:2`]);
    assert.equal(pages[0].url, "https://node-a.region.mangadex.network/token/data/fixture-hash/1-first.jpg");
    assert.equal(pages[0].headers.Referer, "https://mangadex.org/");
    assert.equal(new URL(network.requests[1].url).searchParams.get("forcePort443"), "true");
    const wrongParent = await fixture("chapter");
    wrongParent.data.relationships[0].id = "00000002-1111-4111-8111-000000000002";
    const denied = host(wrongParent);
    await assert.rejects(adapter.getChapterPages({ mangaID, chapterID }, denied));
    assert.equal(denied.requests.length, 1);
});

test("MangaDex rejects untrusted page hosts, ports, traversal, and empty page arrays", async () => {
    const adapter = await load();
    for (const baseUrl of ["https://mangadex.network", "https://evil.org", "https://x.mangadex.network.evil.org", "https://badmangadex.network", "http://x.mangadex.network", "https://x.mangadex.network:8443", "https://user@x.mangadex.network", "https://x.mangadex.network/../token"]) {
        await assert.rejects(adapter.getChapterPages({ mangaID, chapterID }, host(await fixture("chapter"), { ...await fixture("pages"), baseUrl })));
    }
    for (const files of [[], ["../secret"], ["a%2fb.jpg"], ["/file.jpg"]]) {
        const response = await fixture("pages");
        response.chapter.data = files;
        await assert.rejects(adapter.getChapterPages({ mangaID, chapterID }, host(await fixture("chapter"), response)));
    }
});

test("MangaDex malformed responses remain failures instead of empty successes", async () => {
    const adapter = await load();
    for (const patch of [{ result: "error" }, { data: "bad" }, { total: -1 }, { offset: 20 }, { limit: 0 }, { data: [] }]) {
        await assert.rejects(adapter.search({ query: "test" }, host({ ...await fixture("search"), ...patch })));
    }
    const duplicate = await fixture("search");
    duplicate.data.push(duplicate.data[0]);
    await assert.rejects(adapter.search({ query: "test" }, host(duplicate)));
    const malformed = await fixture("search");
    malformed.data[0].attributes.title.en = 42;
    await assert.rejects(adapter.search({ query: "test" }, host(malformed)));
});

test("MangaDex rejects invalid cursors and IDs without network access and respects the API offset cap", async () => {
    const adapter = await load();
    for (const cursor of ["-1", "1.5", "10000", "01", "https://evil.org", ""]) {
        await assert.rejects(adapter.search({ query: "test", cursor }, host()));
    }
    await assert.rejects(adapter.getMangaDetails({ mangaID: "../chapter" }, host()));
    const response = await fixture("search");
    const final = await adapter.search({ query: "test", cursor: "9980" }, host({ ...response, offset: 9980, total: 25000 }));
    assert.equal(final.nextCursor, null);
});
