import { defineExtension, type Chapter } from "../sdk/index";

export function fixture(source: "a" | "b") {
    const summary = { id: "fixture-manga", title: "The Missing Chapter", coverURL: null };
    const chapters: Chapter[] = Array.from({ length: 40 }, (_, index) => index + 1)
        .filter(number => source !== "a" || number !== 21)
        .map(number => ({
            id: source + ":" + number,
            title: "Chapter " + number,
            number: String(number),
            ordinal: number,
            language: "en"
        }));
    return defineExtension({
        async search({ query }) {
            return { items: summary.title.toLowerCase().includes(query.toLowerCase()) ? [summary] : [], nextCursor: null };
        },
        async getFeeds() { return [{ id: "all", title: "All fixtures" }]; },
        async getFeedPage() { return { items: [summary], nextCursor: null }; },
        async getMangaDetails({ mangaID }) {
            if (mangaID !== summary.id) throw new Error("Unknown fixture manga");
            return { ...summary, description: "Local fixture " + source.toUpperCase() + ". No internet required." };
        },
        async getChapterPage({ mangaID }) {
            if (mangaID !== summary.id) throw new Error("Unknown fixture manga");
            return { items: chapters, nextCursor: null };
        }
    });
}
