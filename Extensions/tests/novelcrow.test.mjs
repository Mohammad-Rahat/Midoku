import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";

async function load() {
    const context = vm.createContext({});
    vm.runInContext(await readFile(new URL("../dist/dev.midoku.novelcrow/bundle.js", import.meta.url), "utf8"), context);
    return context.MidokuExtension.default;
}

function host(result) {
    return {
        requests: [],
        async request(request) {
            this.requests.push(request);
            assert.ok(request.browserScript.length < 32768);
            new vm.Script(request.browserScript);
            return { url: request.url, status: 200, headers: {}, body: JSON.stringify({ result }) };
        }
    };
}

test("NovelCrow search follows the Madara route and preserves pagination", async () => {
    const api = await load();
    const h = host({ items: [{ id: "story-one", title: "Story One", coverURL: "https://novelcrow.com/cover.webp" }], hasNext: true });
    const result = await api.search({ query: "A & B", filters: { sort: ["trending"] } }, h);
    assert.equal(result.items[0].id, "story-one");
    assert.equal(result.nextCursor, "2");
    assert.equal(h.requests[0].url, "https://novelcrow.com/?s=A%20%26%20B&post_type=wp-manga&m_orderby=trending");
    assert.match(h.requests[0].browserScript, /page-item-detail/);
});

test("NovelCrow feeds use the Keiyoushi trending and latest orders", async () => {
    const api = await load();
    const h = host({ items: [], hasNext: false });
    await api.getFeedPage({ feedID: "latest", cursor: "2" }, h);
    assert.equal(h.requests[0].url, "https://novelcrow.com/page/2/?s=&post_type=wp-manga&m_orderby=latest");
    await assert.rejects(api.getFeedPage({ feedID: "unknown" }, h));
});

test("NovelCrow details map Madara metadata and enforce identity", async () => {
    const api = await load();
    const h = host({ id: "story-one", title: "Story One", description: "Summary", coverURL: null, authors: ["Author"], artists: ["Artist"], status: "Completed", year: null, tags: ["3D"] });
    const result = await api.getMangaDetails({ mangaID: "story-one" }, h);
    assert.equal(result.webURL, "https://novelcrow.com/comic/story-one/");
    assert.equal(result.artists[0], "Artist");
    await assert.rejects(api.getMangaDetails({ mangaID: "story-one" }, host({ ...h, id: "other" })));
});

test("NovelCrow chapters retain fractional releases and stable path IDs", async () => {
    const api = await load();
    const h = host({ items: [
        { id: "chapter-1", title: "Chapter 1", number: "1" },
        { id: "chapter-1-5", title: "Chapter 1.5", number: "1.5" }
    ] });
    const result = await api.getChapterPage({ mangaID: "story-one", language: "en" }, h);
    assert.equal(result.items[1].number, "1.5");
    assert.equal(result.items[1].ordinal, 1);
    assert.match(h.requests[0].browserScript, /ajax\/chapters/);
    await assert.rejects(api.getChapterPage({ mangaID: "story-one", cursor: "2" }, h));
});

test("NovelCrow pages keep order and source referers", async () => {
    const api = await load();
    const h = host({ chapterID: "chapter-1", urls: [
        "https://novelcrow.com/wp-content/uploads/1.webp",
        "https://novelcrow.com/wp-content/uploads/2.webp"
    ] });
    const result = await api.getChapterPages({ mangaID: "story-one", chapterID: "chapter-1" }, h);
    assert.equal(result[0].id, "chapter-1:1");
    assert.equal(result[1].headers.Referer, "https://novelcrow.com/comic/story-one/chapter-1/");
});

test("NovelCrow rejects invalid IDs, filters, cursors and page hosts before accepting data", async () => {
    const api = await load(); const h = host({ items: [], hasNext: false });
    await assert.rejects(api.getMangaDetails({ mangaID: "../escape" }, h));
    await assert.rejects(api.search({ query: "", cursor: "0" }, h));
    await assert.rejects(api.search({ query: "", filters: { sort: ["unknown"] } }, h));
    assert.equal(h.requests.length, 0);
    await assert.rejects(api.getChapterPages({ mangaID: "story-one", chapterID: "chapter-1" },
        host({ chapterID: "chapter-1", urls: ["https://example.com/page.webp"] })));
});
