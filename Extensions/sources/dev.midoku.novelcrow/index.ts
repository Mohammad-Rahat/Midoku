// NovelCrow protocol reference: keiyoushi/extensions-source (Apache-2.0); see THIRD_PARTY_NOTICES.md.
import { defineExtension, type FilterValues, type Host, type MangaSummary } from "../../sdk/index";

const base = "https://novelcrow.com";

function object(value: unknown): Record<string, any> {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
        throw Error("Invalid NovelCrow response");
    }
    return value as Record<string, any>;
}

function text(value: unknown): string {
    return typeof value === "string" ? value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim() : "";
}

function mangaID(value: unknown): string {
    if (typeof value !== "string" || !/^[a-z0-9](?:[a-z0-9-]{0,198}[a-z0-9])?$/.test(value)) {
        throw Error("Invalid NovelCrow manga identity");
    }
    return value;
}

function chapterID(value: unknown): string {
    if (typeof value !== "string" || value.length > 512 || !/^[^/?#\\\s]+$/.test(value)) {
        throw Error("Invalid NovelCrow chapter identity");
    }
    return value;
}

function page(value?: string | null): number {
    if (value == null) return 1;
    if (!/^[1-9][0-9]{0,4}$/.test(value)) throw Error("Invalid cursor");
    return Number(value);
}

function browserScript(operation: string, args: Record<string, unknown>): string {
    const serialized = JSON.stringify(args)
        .replace(/</g, "\\u003c")
        .replace(/`/g, "\\u0060")
        .replace(/\$\{/g, "\\u0024{");
    return `(() => {
      const fail = value => { window.__midokuResult = JSON.stringify({midokuError:value}); };
      const clean = value => typeof value === 'string' ? value.replace(/\\s+/g,' ').trim() : '';
      const absolute = value => { try { const url = new URL(value, document.baseURI); return url.protocol === 'https:' ? url.href : null; } catch (_) { return null; } };
      const image = element => {
        if (!element) return null;
        const candidates = [element.getAttribute('data-src'),element.getAttribute('data-lazy-src'),element.getAttribute('data-cfsrc'),element.getAttribute('data-manga-src'),element.getAttribute('src')];
        const srcset = element.getAttribute('srcset');
        if (srcset) candidates.unshift(...srcset.split(',').reverse().map(value => value.trim().split(/\\s+/,1)[0]));
        for (const candidate of candidates) { const url = candidate && absolute(candidate); if (url && !url.startsWith('data:')) return url; }
        return null;
      };
      const parts = href => { try { const url = new URL(href, document.baseURI); if (url.origin !== location.origin) return null; return url.pathname.split('/').filter(Boolean).map(decodeURIComponent); } catch (_) { return null; } };
      const mangaSlug = href => { const value = parts(href); return value && value[0] === 'comic' && value.length >= 2 ? value[1] : null; };
      const chapterSlug = (href,parent) => { const value = parts(href); return value && value[0] === 'comic' && value[1] === parent && value.length >= 3 ? value.slice(2).join('/') : null; };
      const unique = values => [...new Set(values.filter(Boolean))];
      const chapterNumber = title => {
        const named = title.match(/(?:chapter|ch\\.?)[\\s:#-]*(-?\\d+(?:\\.\\d+)?)/i);
        if (named) return named[1];
        const leading = title.match(/^\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:[.:-]|$)/);
        return leading ? leading[1] : null;
      };
      const chapterItems = (root,parent) => [...root.querySelectorAll('li.wp-manga-chapter')].map(node => {
        const link = node.querySelector('a'); const id = link && chapterSlug(link.href,parent); const title = clean(link?.textContent);
        return id && title ? {id,title,number:chapterNumber(title)} : null;
      }).filter(Boolean).reverse().map((item,index) => ({...item,ordinal:index,language:'en',groups:[],volume:null,uploadedAt:null}));
      const catalogue = () => {
        const nodes = [...document.querySelectorAll('div.page-item-detail, div.c-tabs-item__content, .manga__item')];
        const seen = new Set(); const items = [];
        for (const node of nodes) {
          const link = node.querySelector('div.post-title a, .post-title a'); const id = link && mangaSlug(link.href); const title = clean(link?.textContent);
          if (!id || !title || seen.has(id)) continue; seen.add(id);
          items.push({id,title,coverURL:image(node.querySelector('img')),preferredChapterLanguage:'en'});
        }
        return {items,hasNext:!!document.querySelector('div.nav-previous, nav.navigation-ajax, a.nextpostslink')};
      };
      const detailValue = label => {
        const row = [...document.querySelectorAll('.post-content_item')].find(item => clean(item.querySelector('.summary-heading')?.textContent).toLowerCase().includes(label));
        return clean(row?.querySelector('.summary-content')?.textContent);
      };
      const details = parent => {
        const actual = mangaSlug(location.href); if (actual !== parent) throw Error('Manga identity mismatch');
        const title = clean(document.querySelector('div.post-title h3, div.post-title h1, #manga-title > h1')?.textContent);
        const descriptionRoot = document.querySelector('div.description-summary div.summary__content, div.summary_content div.post-content_item > h5 + div, div.summary_content div.manga-excerpt');
        const description = [...(descriptionRoot?.querySelectorAll('p') || [])].map(p => clean(p.textContent)).filter(Boolean).join('\\n\\n') || clean(descriptionRoot?.textContent);
        return {id:parent,title,description,coverURL:image(document.querySelector('div.summary_image img')),
          authors:unique([...document.querySelectorAll('div.author-content > a, div.manga-authors > a')].map(a => clean(a.textContent))),
          artists:unique([...document.querySelectorAll('div.artist-content > a')].map(a => clean(a.textContent))),
          status:detailValue('status') || null,year:detailValue('release') || null,
          tags:unique([...document.querySelectorAll('div.genres-content a, div.tags-content a')].map(a => clean(a.textContent))),
          availableLanguages:[{id:'en',title:'English'}],defaultChapterLanguage:'en',webURL:location.href};
      };
      const run = async () => { try {
        const args = ${serialized}; let result;
        if (${JSON.stringify(operation)} === 'catalogue') result = catalogue();
        else if (${JSON.stringify(operation)} === 'details') result = details(args.mangaID);
        else if (${JSON.stringify(operation)} === 'chapters') {
          if (mangaSlug(location.href) !== args.mangaID) throw Error('Manga identity mismatch');
          let root = document; let items = chapterItems(root,args.mangaID);
          if (!items.length) {
            const response = await fetch(location.href.replace(/\\/$/,'') + '/ajax/chapters',{method:'POST',credentials:'include',headers:{'X-Requested-With':'XMLHttpRequest'}});
            if (response.headers.get('cf-mitigated') === 'challenge') { fail('verification'); return; }
            if (!response.ok) throw Error('Chapter request failed');
            root = new DOMParser().parseFromString(await response.text(),'text/html'); items = chapterItems(root,args.mangaID);
          }
          result = {items};
        } else {
          const actual = chapterSlug(location.href,args.mangaID); if (actual !== args.chapterID) throw Error('Chapter identity mismatch');
          const selectors = 'div.page-break img, li.blocks-gallery-item img, .reading-content .text-left img';
          const urls = unique([...document.querySelectorAll(selectors)].map(image));
          result = {chapterID:actual,urls};
        }
        if (!window.__midokuResult) window.__midokuResult = JSON.stringify({result});
      } catch (_) { if (!window.__midokuResult) fail('extraction'); } };
      if (/cloudflare|just a moment/i.test(document.title) || document.querySelector('#challenge-running,.cf-challenge-running')) fail('verification');
      else if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',run,{once:true}); else run();
    })();`;
}

async function request(host: Host, url: string, operation: string, args: Record<string, unknown>): Promise<Record<string, any>> {
    const response = await host.request({
        url,
        headers: { Accept: "text/html", Referer: base + "/" },
        browserScript: browserScript(operation, args)
    });
    const envelope = object(JSON.parse(response.body));
    if (typeof envelope.midokuError === "string") throw Error("NovelCrow browser extraction failed");
    return object(envelope.result);
}

function searchURL(query: string, current: number, order: string): string {
    const prefix = current === 1 ? "/" : `/page/${current}/`;
    const values = [`s=${encodeURIComponent(query.trim())}`, "post_type=wp-manga"];
    if (order) values.push(`m_orderby=${encodeURIComponent(order)}`);
    return base + prefix + "?" + values.join("&");
}

const sortOptions = [
    { id: "relevance", title: "Relevance" },
    { id: "latest", title: "Latest updates" },
    { id: "alphabet", title: "A–Z" },
    { id: "rating", title: "Rating" },
    { id: "trending", title: "Trending" },
    { id: "views", title: "Most viewed" },
    { id: "new-manga", title: "Recently added" }
];

function selectedSort(filters?: FilterValues): string {
    for (const key of Object.keys(filters ?? {})) if (key !== "sort") throw Error("Unknown filter");
    const selected = filters?.sort ?? ["relevance"];
    if (selected.length !== 1 || !sortOptions.some(option => option.id === selected[0])) throw Error("Invalid sort");
    return selected[0] === "relevance" ? "" : selected[0];
}

function summary(value: unknown): MangaSummary {
    const item = object(value); const id = mangaID(item.id); const title = text(item.title);
    if (!title) throw Error("Missing NovelCrow title");
    const coverURL = item.coverURL == null ? null : text(item.coverURL);
    if (coverURL !== null && !/^https:\/\/novelcrow\.com\//.test(coverURL)) throw Error("Invalid NovelCrow cover");
    return { id, title, coverURL, preferredChapterLanguage: "en" };
}

async function catalogue(host: Host, query: string, cursor: string | null | undefined, order: string) {
    const current = page(cursor);
    const result = await request(host, searchURL(query, current, order), "catalogue", { page: current });
    if (!Array.isArray(result.items) || typeof result.hasNext !== "boolean") throw Error("Invalid NovelCrow catalogue");
    const items = result.items.map(summary);
    if (new Set(items.map(item => item.id)).size !== items.length) throw Error("Duplicate NovelCrow manga");
    return { items, nextCursor: result.hasNext ? String(current + 1) : null };
}

export default defineExtension({
    async getSearchFilters() {
        return [{ id: "sort", title: "Sort", kind: "single", options: sortOptions, defaults: ["relevance"], scopes: ["search"], required: true }];
    },
    async getFeeds() {
        return [{ id: "trending", title: "Trending" }, { id: "latest", title: "Latest updates" }];
    },
    async search(input, host) {
        return catalogue(host, input.query, input.cursor, selectedSort(input.filters));
    },
    async getFeedPage(input, host) {
        if (input.feedID !== "trending" && input.feedID !== "latest") throw Error("Unknown NovelCrow feed");
        return catalogue(host, "", input.cursor, input.feedID);
    },
    async getMangaDetails(input, host) {
        const id = mangaID(input.mangaID);
        const result = await request(host, `${base}/comic/${encodeURIComponent(id)}/`, "details", { mangaID: id });
        if (result.id !== id) throw Error("Manga identity mismatch");
        const title = text(result.title); if (!title) throw Error("Missing NovelCrow title");
        const coverURL = result.coverURL == null ? null : text(result.coverURL);
        if (coverURL !== null && !/^https:\/\/novelcrow\.com\//.test(coverURL)) throw Error("Invalid NovelCrow cover");
        const list = (value: unknown) => Array.isArray(value) ? value.map(text).filter(Boolean) : [];
        return { id, title, description: text(result.description), coverURL, authors: list(result.authors), artists: list(result.artists),
            status: text(result.status) || null, year: text(result.year) || null, tags: list(result.tags),
            availableLanguages: [{ id: "en", title: "English" }], defaultChapterLanguage: "en", webURL: `${base}/comic/${encodeURIComponent(id)}/` };
    },
    async getChapterPage(input, host) {
        if (input.language && input.language !== "en") throw Error("Unsupported chapter language");
        if (input.cursor != null) throw Error("NovelCrow chapters are not paginated");
        const id = mangaID(input.mangaID);
        const result = await request(host, `${base}/comic/${encodeURIComponent(id)}/`, "chapters", { mangaID: id });
        if (!Array.isArray(result.items) || result.items.length > 2000) throw Error("Invalid NovelCrow chapters");
        const items = result.items.map((value: unknown, index: number) => {
            const item = object(value); const title = text(item.title); if (!title) throw Error("Missing chapter title");
            return { id: chapterID(item.id), title, number: item.number == null ? null : text(item.number) || null,
                ordinal: index, language: "en", groups: [], volume: null, uploadedAt: null };
        });
        if (new Set(items.map(item => item.id)).size !== items.length) throw Error("Duplicate NovelCrow chapter");
        return { items, nextCursor: null };
    },
    async getChapterPages(input, host) {
        const parent = mangaID(input.mangaID); const chapter = chapterID(input.chapterID);
        const url = `${base}/comic/${encodeURIComponent(parent)}/${chapter.split("/").map(encodeURIComponent).join("/")}/`;
        const result = await request(host, url, "pages", { mangaID: parent, chapterID: chapter });
        if (result.chapterID !== chapter || !Array.isArray(result.urls) || !result.urls.length || result.urls.length > 2000) {
            throw Error("Invalid NovelCrow pages");
        }
        const seen = new Set<string>();
        return result.urls.map((value: unknown, index: number) => {
            const pageURL = text(value);
            if (!/^https:\/\/novelcrow\.com\//.test(pageURL) || seen.has(pageURL)) throw Error("Invalid NovelCrow page URL");
            seen.add(pageURL);
            return { id: `${chapter}:${index + 1}`, url: pageURL, headers: { Referer: url } };
        });
    }
});
