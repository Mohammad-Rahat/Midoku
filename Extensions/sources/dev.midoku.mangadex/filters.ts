import type { FilterValues, SearchFilter, FilterOption } from "../../sdk/index";

const options = (values: [string, string][]): FilterOption[] => values.map(([id, title]) => ({ id, title }));
export const languages = options([
    ["en", "English"], ["ja", "Japanese"], ["ko", "Korean"], ["zh", "Chinese (Simplified)"],
    ["zh-hk", "Chinese (Traditional)"], ["es", "Spanish"], ["es-la", "Spanish (Latin America)"],
    ["pt-br", "Portuguese (Brazil)"], ["pt", "Portuguese"], ["fr", "French"], ["de", "German"],
    ["it", "Italian"], ["ru", "Russian"], ["uk", "Ukrainian"], ["pl", "Polish"], ["tr", "Turkish"],
    ["ar", "Arabic"], ["bn", "Bengali"], ["hi", "Hindi"], ["id", "Indonesian"], ["ms", "Malay"],
    ["th", "Thai"], ["vi", "Vietnamese"], ["tl", "Filipino"], ["my", "Burmese"],
    ["fa", "Persian"], ["he", "Hebrew"], ["ro", "Romanian"], ["hu", "Hungarian"], ["cs", "Czech"],
    ["sk", "Slovak"], ["bg", "Bulgarian"], ["el", "Greek"], ["nl", "Dutch"], ["sv", "Swedish"],
    ["da", "Danish"], ["no", "Norwegian"], ["fi", "Finnish"], ["sr", "Serbian"], ["hr", "Croatian"]
]);

function filter(id: string, title: string, choices: FilterOption[], defaults: string[] = [],
    kind: "single" | "multiple" = "multiple", required = false): SearchFilter {
    return { id, title, kind, options: choices, defaults, scopes: ["search", "feed"], required };
}

export const staticFilters: SearchFilter[] = [
    { ...filter("sort", "Sort", options([
        ["relevance:desc", "Best match"], ["followedCount:desc", "Most followed"], ["rating:desc", "Highest rated"],
        ["latestUploadedChapter:desc", "Latest updates"], ["createdAt:desc", "Recently added"],
        ["title:asc", "Title A–Z"], ["title:desc", "Title Z–A"], ["year:desc", "Newest publication"]
    ]), ["relevance:desc"], "single", true), scopes: ["search"] },
    filter("language", "Chapter language", languages, ["en"], "single", true),
    filter("status", "Publication status", options([
        ["ongoing", "Ongoing"], ["completed", "Completed"], ["hiatus", "Hiatus"], ["cancelled", "Cancelled"]
    ])),
    filter("demographic", "Demographic", options([
        ["shounen", "Shounen"], ["shoujo", "Shoujo"], ["seinen", "Seinen"], ["josei", "Josei"], ["none", "Unspecified"]
    ])),
    filter("originalLanguage", "Original language", languages),
    filter("rating", "Content rating", options([
        ["safe", "Safe"], ["suggestive", "Suggestive"], ["erotica", "Erotica"], ["pornographic", "Pornographic"]
    ]), ["safe", "suggestive"], "multiple", true),
    filter("includedTagsMode", "Match included tags", options([["AND", "All selected tags"], ["OR", "Any selected tag"]]), ["AND"], "single", true),
    filter("excludedTagsMode", "Exclude titles matching", options([["OR", "Any excluded tag"], ["AND", "All excluded tags"]]), ["OR"], "single", true)
];

export function tagFilters(tags: FilterOption[]): SearchFilter[] {
    return [filter("includedTags", "Include tags", tags), filter("excludedTags", "Exclude tags", tags)];
}

export function searchParameters(values: FilterValues = {}, feedSort?: string): [string, string][] {
    if (!values || typeof values !== "object" || Array.isArray(values)) throw new Error("Invalid filters");
    const known = new Set([...staticFilters.map(filter => filter.id), "includedTags", "excludedTags"]);
    if (Object.keys(values).some(key => !known.has(key))) throw new Error("Unknown filter");
    const selected: FilterValues = {};
    for (const definition of staticFilters) {
        const value = values[definition.id] ?? definition.defaults;
        if (!Array.isArray(value) || new Set(value).size !== value.length ||
            (definition.required && value.length === 0) || (definition.kind === "single" && value.length > 1) ||
            value.some(id => !definition.options.some(option => option.id === id))) throw new Error("Invalid filter selection");
        selected[definition.id] = value;
    }
    const result: [string, string][] = [["hasAvailableChapters", "true"]];
    for (const [key, parameter] of [
        ["language", "availableTranslatedLanguage[]"], ["rating", "contentRating[]"], ["status", "status[]"],
        ["demographic", "publicationDemographic[]"], ["originalLanguage", "originalLanguage[]"]
    ]) {
        for (const value of selected[key]) result.push([parameter, value]);
    }
    for (const key of ["includedTags", "excludedTags"]) {
        const ids = values[key] ?? [];
        if (!Array.isArray(ids) || ids.length > 100 || ids.some(id => typeof id !== "string" ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id))) throw new Error("Invalid tag selection");
        for (const id of ids) result.push([key + "[]", id]);
        result.push([key + "Mode", selected[key + "Mode"][0]]);
    }
    const [sort, direction] = (feedSort ?? selected.sort[0]).split(":");
    result.push([`order[${sort}]`, direction]);
    return result;
}
