import { defineExtension, type Host, type MangaSummary, type Chapter, type Page } from "../../sdk/index";

const api = "https://api.mangadex.org";
const referer = "https://mangadex.org/";
const pageSize = 20;
const chapterPageSize = 100;
const maximumResults = 10_000;
// Contract 1 has no source settings yet. These defaults are documented in README.md.
const language = "en";
const ratings: [string, string][] = [["contentRating[]", "safe"], ["contentRating[]", "suggestive"]];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
type ObjectValue = Record<string, unknown>;
type Parameter = [string, string];

function object(value: unknown): ObjectValue {
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected object");
    return value as ObjectValue;
}

function text(value: unknown): string {
    if (typeof value !== "string" || !value.trim()) throw new Error("Missing text");
    return value;
}

function optionalText(value: unknown): string | null {
    if (value == null || value === "") return null;
    return text(value);
}

function integer(value: unknown): number {
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) throw new Error("Invalid count");
    return value;
}

function uuid(value: unknown): string {
    const id = text(value);
    if (!uuidPattern.test(id)) throw new Error("Invalid MangaDex ID");
    return id;
}

function segment(value: unknown): string {
    const part = text(value);
    if (part === "." || part === ".." || /[\\/%?#\s]/.test(part)) throw new Error("Invalid resource path");
    return encodeURIComponent(part);
}

function offsetFrom(cursor?: string | null): number {
    if (cursor == null) return 0;
    if (!/^(0|[1-9][0-9]{0,3})$/.test(cursor)) throw new Error("Invalid MangaDex cursor");
    return Number(cursor);
}

function localized(maps: ObjectValue[], preferred: string[]): string | null {
    for (const map of maps) {
        for (const value of Object.values(map)) {
            if (typeof value !== "string") throw new Error("Invalid localized text");
        }
    }
    for (const locale of preferred) {
        for (const map of maps) {
            const value = map[locale];
            if (typeof value === "string" && value.trim()) return value;
        }
    }
    for (const map of maps) {
        for (const locale of Object.keys(map).sort()) {
            const value = map[locale] as string;
            if (value.trim()) return value;
        }
    }
    return null;
}

function relationships(value: ObjectValue): ObjectValue[] {
    if (!Array.isArray(value.relationships)) throw new Error("Missing relationships");
    return value.relationships.map(object);
}

function entity(value: unknown, type: string): ObjectValue {
    const result = object(value);
    if (result.type !== type) throw new Error("Unexpected entity type");
    uuid(result.id);
    object(result.attributes);
    return result;
}

function summary(value: unknown): MangaSummary {
    const manga = entity(value, "manga");
    const attributes = object(manga.attributes);
    const maps = [object(attributes.title)];
    if (attributes.altTitles !== undefined) {
        if (!Array.isArray(attributes.altTitles)) throw new Error("Invalid alternative titles");
        maps.push(...attributes.altTitles.map(object));
    }
    const title = localized(maps, [language, "ja-ro", optionalText(attributes.originalLanguage) ?? ""]);
    if (!title) throw new Error("Missing manga title");
    const cover = relationships(manga).find(item => item.type === "cover_art");
    const fileName = cover?.attributes == null ? null : optionalText(object(cover.attributes).fileName);
    const id = uuid(manga.id);
    return {
        id, title,
        coverURL: fileName === null ? null : `https://uploads.mangadex.org/covers/${id}/${segment(fileName)}.256.jpg`
    };
}

async function get(host: Host, path: string, parameters: Parameter[] = []): Promise<ObjectValue> {
    const query = parameters.map(([key, value]) => encodeURIComponent(key) + "=" + encodeURIComponent(value)).join("&");
    const response = await host.request({
        url: api + path + (query ? "?" + query : ""),
        headers: { Accept: "application/json", Referer: referer }
    });
    const result = object(JSON.parse(response.body));
    if (result.result !== "ok") throw new Error("MangaDex returned an API error");
    return result;
}

function collection(value: ObjectValue, offset: number, limit: number): Page<unknown> {
    if (value.response !== "collection" || !Array.isArray(value.data)) throw new Error("Missing collection");
    const actualLimit = integer(value.limit);
    const total = integer(value.total);
    if (integer(value.offset) !== offset || actualLimit < 1 || actualLimit > limit || value.data.length > actualLimit) {
        throw new Error("Invalid pagination metadata");
    }
    if (value.data.length === 0 && offset < total) throw new Error("Unexpected empty page");
    const next = offset + actualLimit;
    return { items: value.data, nextCursor: next < Math.min(total, maximumResults) ? String(next) : null };
}

function unique<T extends { id: string }>(items: T[]): T[] {
    if (new Set(items.map(item => item.id)).size !== items.length) throw new Error("Duplicate source ID");
    return items;
}

async function mangaPage(host: Host, cursor: string | null | undefined, parameters: Parameter[]): Promise<Page<MangaSummary>> {
    const offset = offsetFrom(cursor);
    const limit = Math.min(pageSize, maximumResults - offset);
    const response = await get(host, "/manga", [
        ["limit", String(limit)], ["offset", String(offset)], ["includes[]", "cover_art"],
        ["hasAvailableChapters", "true"], ["availableTranslatedLanguage[]", language], ...ratings, ...parameters
    ]);
    const page = collection(response, offset, limit);
    return { items: unique(page.items.map(summary)), nextCursor: page.nextCursor };
}

function chapter(value: unknown, mangaID: string, ordinal: number): Chapter | null {
    const entry = entity(value, "chapter");
    const attributes = object(entry.attributes);
    const parent = relationships(entry).find(item => item.type === "manga");
    if (!parent || uuid(parent.id) !== mangaID) throw new Error("Chapter belongs to another manga");
    // External/locked/empty chapters cannot provide readable pages through this adapter.
    if (attributes.isUnavailable !== undefined && typeof attributes.isUnavailable !== "boolean") {
        throw new Error("Invalid chapter availability");
    }
    if (optionalText(attributes.externalUrl) !== null || attributes.isUnavailable === true || integer(attributes.pages) === 0) return null;
    const translatedLanguage = text(attributes.translatedLanguage);
    if (translatedLanguage !== language) return null;
    const number = optionalText(attributes.chapter);
    const volume = optionalText(attributes.volume);
    const fallback = number === null ? "Oneshot" : `Chapter ${number}`;
    const title = optionalText(attributes.title) ?? fallback;
    return {
        id: uuid(entry.id), title: volume === null ? title : `Vol. ${volume} · ${title}`,
        number, ordinal, language: translatedLanguage
    };
}

function imageBase(value: unknown): string {
    const base = text(value).replace(/\/$/, "");
    // No URL global in JavaScriptCore. Validate authority and path before constructing descriptors;
    // native SourceRequestPolicy independently validates every returned URL.
    const match = /^https:\/\/([a-z0-9.-]+)(?::443)?((?:\/[A-Za-z0-9._~-]+)*)$/.exec(base);
    const host = match?.[1];
    if (!host || !(host === "uploads.mangadex.org" || host.endsWith(".mangadex.network"))) {
        throw new Error("Unexpected MangaDex image host");
    }
    if (match[2].split("/").some(part => part === "." || part === "..")) throw new Error("Invalid image base path");
    return base;
}

export default defineExtension({
    async search({ query, cursor }, host) {
        return mangaPage(host, cursor, [["title", query.trim()], ["order[relevance]", "desc"]]);
    },
    async getFeeds() {
        return [
            { id: "latest", title: "Latest updates" },
            { id: "popular", title: "Popular" },
            { id: "recent", title: "Recently added" }
        ];
    },
    async getFeedPage({ feedID, cursor }, host) {
        const sort = feedID === "latest" ? "latestUploadedChapter"
            : feedID === "popular" ? "followedCount" : feedID === "recent" ? "createdAt" : null;
        if (!sort) throw new Error("Unknown MangaDex feed");
        return mangaPage(host, cursor, [[`order[${sort}]`, "desc"]]);
    },
    async getMangaDetails({ mangaID }, host) {
        uuid(mangaID);
        const response = await get(host, `/manga/${mangaID}`, [["includes[]", "cover_art"]]);
        const manga = entity(response.data, "manga");
        if (manga.id !== mangaID) throw new Error("Manga ID mismatch");
        const attributes = object(manga.attributes);
        return { ...summary(manga), description: localized([object(attributes.description)], [language]) ?? "" };
    },
    async getChapterPage({ mangaID, cursor }, host) {
        uuid(mangaID);
        const offset = offsetFrom(cursor);
        const limit = Math.min(chapterPageSize, maximumResults - offset);
        const response = await get(host, `/manga/${mangaID}/feed`, [
            ["limit", String(limit)], ["offset", String(offset)], ["translatedLanguage[]", language],
            ["order[volume]", "asc"], ["order[chapter]", "asc"], ["order[createdAt]", "asc"],
            ["includeExternalUrl", "0"], ["includeUnavailable", "0"], ["includeEmptyPages", "0"],
            ["includeFutureUpdates", "0"], ["includeFuturePublishAt", "0"], ...ratings
        ]);
        const page = collection(response, offset, limit);
        const items = page.items.map((value, index) => chapter(value, mangaID, offset + index))
            .filter((value): value is Chapter => value !== null);
        // Advance by the source page, even if every entry was deliberately filtered out.
        return { items: unique(items), nextCursor: page.nextCursor };
    },
    async getChapterPages({ mangaID, chapterID }, host) {
        uuid(mangaID);
        uuid(chapterID);
        // At-home only takes a chapter ID. Validate its parent before resolving page URLs.
        const metadata = await get(host, `/chapter/${chapterID}`);
        if (object(metadata.data).id !== chapterID || chapter(metadata.data, mangaID, 0) === null) {
            throw new Error("Chapter is not readable");
        }
        const response = await get(host, `/at-home/server/${chapterID}`, [["forcePort443", "true"]]);
        const base = imageBase(response.baseUrl);
        const pages = object(response.chapter);
        const hash = segment(pages.hash);
        if (!Array.isArray(pages.data) || pages.data.length === 0 || pages.data.length > 2000) {
            throw new Error("Missing chapter pages");
        }
        return pages.data.map((file, index) => ({
            id: `${chapterID}:${index + 1}`,
            url: `${base}/data/${hash}/${segment(file)}`,
            headers: { Referer: referer }
        }));
    }
});
