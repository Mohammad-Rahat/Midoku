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
    assert.deepEqual(plain(first.authors), ["Fixture Author"]);
    assert.deepEqual(plain(first.artists), ["Fixture Artist"]);
    assert.deepEqual(plain(first.tags), ["Adventure"]);
    assert.deepEqual(plain(first.availableLanguages), [{ id: "en", title: "English" }, { id: "es", title: "Spanish" }]);
    assert.equal(first.defaultChapterLanguage, "en");
    assert.equal(first.status, "ongoing");
    assert.equal(first.year, "2024");
    assert.equal(first.webURL, `https://mangadex.org/title/${mangaID}`);
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
    assert.deepEqual(plain(page.items[0].groups), ["Fixture Scanlation Group"]);
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

test("MangaDex filter definitions expose valid defaults and live stable tag IDs", async () => {
    const adapter = await load();
    const network = host(await fixture("tags"));
    const filters = await adapter.getSearchFilters({}, network);
    assert.equal(new URL(network.requests[0].url).pathname, "/manga/tag");
    assert.deepEqual(plain(filters.find(item => item.id === "includedTags").options), [
        { id: "00000080-1111-4111-8111-000000000080", title: "Adventure" },
        { id: "00000081-1111-4111-8111-000000000081", title: "Comedy" }
    ]);
    for (const filter of filters) {
        assert.equal(new Set(filter.options.map(item => item.id)).size, filter.options.length);
        assert.ok(filter.defaults.every(id => filter.options.some(item => item.id === id)));
        if (filter.required) assert.ok(filter.defaults.length);
    }
    assert.deepEqual(plain(filters.find(item => item.id === "sort").scopes), ["search"]);
});

test("MangaDex search and feed filters encode arrays while preserving feed ordering and pagination", async () => {
    const adapter = await load();
    const filters = {
        sort: ["title:asc"], language: ["es"], rating: ["safe"], status: ["completed", "hiatus"],
        demographic: ["seinen"], originalLanguage: ["ko"],
        includedTags: ["00000080-1111-4111-8111-000000000080"], includedTagsMode: ["OR"],
        excludedTags: ["00000081-1111-4111-8111-000000000081"], excludedTagsMode: ["AND"]
    };
    const response = await fixture("search");
    const network = host(response, { ...response, offset: 20 }, response);
    const result = await adapter.search({ query: "", filters }, network);
    assert.equal(result.items[0].preferredChapterLanguage, "es");
    await adapter.search({ query: "", cursor: "20", filters }, network);
    await adapter.getFeedPage({ feedID: "popular", filters }, network);
    for (const request of network.requests) {
        const p = new URL(request.url).searchParams;
        assert.equal(p.has("title"), false);
        assert.equal(p.get("availableTranslatedLanguage[]"), "es");
        assert.deepEqual(p.getAll("status[]"), ["completed", "hiatus"]);
        assert.deepEqual(p.getAll("contentRating[]"), ["safe"]);
        assert.equal(p.get("originalLanguage[]"), "ko");
        assert.equal(p.get("publicationDemographic[]"), "seinen");
        assert.equal(p.get("includedTags[]"), filters.includedTags[0]);
        assert.equal(p.get("excludedTags[]"), filters.excludedTags[0]);
        assert.equal(p.get("includedTagsMode"), "OR");
        assert.equal(p.get("excludedTagsMode"), "AND");
    }
    assert.equal(new URL(network.requests[1].url).searchParams.get("offset"), "20");
    assert.equal(new URL(network.requests[0].url).searchParams.get("order[title]"), "asc");
    assert.equal(new URL(network.requests[2].url).searchParams.get("order[followedCount]"), "desc");
    assert.equal(new URL(network.requests[2].url).searchParams.has("order[title]"), false);
});

test("MangaDex invalid filter values fail before issuing HTTP requests", async () => {
    const adapter = await load();
    for (const filters of [{ sort: ["inject:asc"] }, { rating: [] }, { language: ["en", "es"] },
        { language: ["bad"] }, { unknown: ["x"] }, { includedTags: ["../tag"] }, { status: "completed" }]) {
        await assert.rejects(adapter.search({ query: "x", filters }, host()));
    }
});

test("MangaDex selected chapter language also opens pages without an English-only restriction", async () => {
    const adapter = await load();
    const response = await fixture("chapters");
    response.data[0].attributes.translatedLanguage = "es";
    const network = host(response);
    const result = await adapter.getChapterPage({ mangaID, language: "es" }, network);
    assert.deepEqual(plain(result.items.map(item => item.id)), [chapterID]);
    assert.equal(new URL(network.requests[0].url).searchParams.get("translatedLanguage[]"), "es");
    const metadata = await fixture("chapter");
    metadata.data.attributes.translatedLanguage = "es";
    const pages = await adapter.getChapterPages({ mangaID, chapterID }, host(metadata, await fixture("pages")));
    assert.equal(pages.length, 2);
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
