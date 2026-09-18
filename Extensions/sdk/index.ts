export type Capability = "search" | "feeds" | "details" | "chapters" | "pages" | "filters";

export interface Manifest {
    id: string;
    name: string;
    version: string;
    contractVersion: 1 | 2;
    domains: string[];
    capabilities: Capability[];
}

export interface HTTPRequest {
    url: string;
    /** Accept, Accept-Language, and permitted Referer only. The host owns cookies and User-Agent. */
    headers?: Record<string, string>;
}

export interface HTTPResponse {
    url: string;
    status: number;
    headers: Record<string, string>;
    body: string;
}

export interface Host {
    /** GET through the host's permissions, rate limiting, and interactive-verification flow. */
    request(request: HTTPRequest): Promise<HTTPResponse>;
}

export interface Page<T> { items: T[]; nextCursor: string | null }
export interface MangaSummary {
    id: string;
    title: string;
    coverURL: string | null;
    preferredChapterLanguage?: string | null;
}
export interface MangaDetails extends MangaSummary {
    description: string;
    authors?: string[];
    artists?: string[];
    status?: string | null;
    year?: string | null;
    tags?: string[];
    availableLanguages?: FilterOption[];
    defaultChapterLanguage?: string | null;
    webURL?: string | null;
}
export interface Chapter {
    id: string;
    title: string;
    number: string | null;
    ordinal: number;
    language: string | null;
    groups?: string[];
}
export interface PageResource { id: string; url: string; headers: Record<string, string> }
export interface Feed { id: string; title: string }
export interface CursorInput { cursor?: string | null }
export type FilterValues = Record<string, string[]>;
export interface FilterOption { id: string; title: string }
export interface SearchFilter {
    id: string;
    title: string;
    kind: "single" | "multiple";
    options: FilterOption[];
    defaults: string[];
    /** Feed ordering belongs to the selected feed. */
    scopes: ("search" | "feed")[];
    required: boolean;
}

export interface Extension {
    getSearchFilters?(input: Record<string, never>, host: Host): Promise<SearchFilter[]>;
    search?(input: CursorInput & { query: string; filters?: FilterValues }, host: Host): Promise<Page<MangaSummary>>;
    getFeeds?(input: Record<string, never>, host: Host): Promise<Feed[]>;
    getFeedPage?(input: CursorInput & { feedID: string; filters?: FilterValues }, host: Host): Promise<Page<MangaSummary>>;
    getMangaDetails?(input: { mangaID: string }, host: Host): Promise<MangaDetails>;
    getChapterPage?(input: CursorInput & { mangaID: string; language?: string | null }, host: Host): Promise<Page<Chapter>>;
    getChapterPages?(input: { mangaID: string; chapterID: string }, host: Host): Promise<PageResource[]>;
}

export function defineExtension(extension: Extension): Extension {
    return Object.freeze(extension);
}

export async function getJSON<T>(host: Host, url: string): Promise<T> {
    const response = await host.request({ url, headers: { Accept: "application/json" } });
    // The caller still validates the source-specific schema. Swift validates normalized results.
    return JSON.parse(response.body) as T;
}
