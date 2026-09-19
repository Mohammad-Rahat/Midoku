// Comix protocol reference: keiyoushi/extensions-source (Apache-2.0); see THIRD_PARTY_NOTICES.md.
import { defineExtension, type Host, type MangaSummary, type FilterValues } from "../../sdk/index";
const base = "https://comix.to";
function id(value: unknown, chapter = false): string {
    if (typeof value !== "string" || !(chapter ? /^[1-9][0-9]{0,14}$/ : /^[a-zA-Z0-9]{1,40}$/).test(value)) throw Error("Invalid Comix identity");
    return value;
}
function page(value?: string | null): number {
    if (value == null) return 1;
    if (!/^[1-9][0-9]{0,5}$/.test(value)) throw Error("Invalid cursor");
    return Number(value);
}
function object(value: any): any { if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Invalid Comix response"); return value; }
function allowed(manga: any): boolean { return ["safe", "suggestive"].includes(manga.contentRating ?? manga.content_rating); }
function text(value: any): string { return typeof value === "string" ? value.replace(/<[^>]*>/g, "").trim() : ""; }
function terms(value: any): string[] { return Array.isArray(value) ? value.map(x => text(x?.title)).filter(Boolean) : []; }
function summary(manga: any): MangaSummary {
    object(manga); const title = text(manga.title); if (!title) throw Error("Missing title");
    return { id: id(manga.hid), title, coverURL: manga.poster?.medium ?? manga.poster?.large ?? manga.poster?.small ?? null, preferredChapterLanguage: "en" };
}
// The website owns its rotating API signature. Only this reviewed extraction script runs in
// the connection's isolated browser; cookies and signing material never enter the adapter VM.
function script(operation: string, args: any): string {
    return `(() => {
      const fail = value => { window.__midokuResult = JSON.stringify({midokuError:value}); };
      const xhrSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function(...args) {
        this.addEventListener('load', () => { if (this.getResponseHeader('cf-mitigated') === 'challenge' ||
          ([403,503].includes(this.status) && /text\\/html/i.test(this.getResponseHeader('content-type') || '') && /cloudflare/i.test(this.responseText || ''))) fail('verification'); });
        return xhrSend.apply(this,args);
      };
      const run = async () => { try {
        const origin = new URL(document.baseURI).origin;
        const main = document.querySelector('script[src*="/main-"]');
        if (!main) throw Error('Website module missing');
        const moduleURL = new URL(main.getAttribute('src'), document.baseURI);
        if (moduleURL.origin !== origin) throw Error('Invalid module origin');
        const response = await fetch(moduleURL.href, {credentials:'include'});
        if (response.headers.get('cf-mitigated') === 'challenge') { fail('verification'); return; }
        const source = await response.text();
        const match = source.match(/from\\s*["']\\.\\/(env-[^"']+\\.js)["']/);
        if (!match) throw Error('Website API module missing');
        const envURL = new URL(match[1],moduleURL);
        if (envURL.origin !== origin) throw Error('Invalid API origin');
        const exports = await import(envURL.href);
        const values = Object.values(exports);
        const manga = values.find(x => x && typeof x.list === 'function' && typeof x.chapters === 'function' && typeof x.get === 'function');
        const http = values.find(x => x && typeof x.get === 'function' && typeof x.post === 'function' && typeof x.patch === 'function' && typeof x.delete === 'function' && !x.chapters && !x.interceptors);
        if (!manga) throw Error('Website API unavailable');
        const args = ${JSON.stringify(args)};
        let result;
        if (${JSON.stringify(operation)} === 'list') result = await manga.list(args);
        else {
          const entry = await manga.get(args.mangaID);
          if (!['safe','suggestive'].includes(entry.contentRating ?? entry.content_rating)) throw Error('Entry unavailable');
          if (${JSON.stringify(operation)} === 'details') result = entry;
          else if (${JSON.stringify(operation)} === 'chapters') result = await manga.chapters(args.mangaID,{page:args.page,limit:100,order:{number:'asc'}});
          else { if (!http) throw Error('Reader API unavailable'); result = await http.get('/chapters/' + args.chapterID);
            const parent = result.manga?.hid ?? result.mangaHid ?? result.manga_hid;
            if ((parent && parent !== args.mangaID) || (result.mangaId != null && entry.id != null && String(result.mangaId) !== String(entry.id))) throw Error('Chapter does not belong to entry');
          }
        }
        if (!window.__midokuResult) window.__midokuResult = JSON.stringify({result});
      } catch(e) { if (!window.__midokuResult) fail('extraction'); } };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',run,{once:true}); else run();
    })();`;
}
async function request(host: Host, operation: string, args: any): Promise<any> {
    const response = await host.request({ url: base + "/browse", headers: { Accept: "text/html", Referer: base + "/" }, browserScript: script(operation, args) });
    return object(JSON.parse(response.body)).result;
}
function paginated(result: any, current: number): {items:any[];nextCursor:string|null} {
    object(result); if (!Array.isArray(result.items)) throw Error("Missing items");
    const meta = object(result.meta ?? result.pagination);
    const last = meta.lastPage ?? meta.last_page;
    if (meta.page !== current || !(Number.isInteger(last) && last >= current || typeof meta.hasNext === "boolean")) throw Error("Invalid pagination");
    const more = meta.hasNext === true || (Number.isInteger(last) && current < last);
    return {items: result.items, nextCursor: more ? String(current + 1) : null};
}
const sortOptions = [{id:"views_30d",title:"Popular"},{id:"chapter_updated_at",title:"Recently updated"},{id:"created_at",title:"Recently added"}];
function parameters(query: string, cursor: string | null | undefined, filters?: FilterValues, feed?: string): any {
    for (const key of Object.keys(filters ?? {})) if (key !== "sort") throw Error("Unknown filter");
    const sort = feed ?? filters?.sort?.[0] ?? "views_30d";
    if (!sortOptions.some(x => x.id === sort) || (filters?.sort && filters.sort.length !== 1)) throw Error("Invalid sort");
    return {keyword: query.trim(), page: page(cursor), limit: 28, content_rating: ["safe","suggestive"], order: {[sort]: "desc"}};
}
async function catalogue(host: Host, params: any) {
    const result = paginated(await request(host,"list",params),params.page);
    return {...result,items:result.items.filter(allowed).map(summary)};
}
export default defineExtension({
    async getSearchFilters() { return [{id:"sort", title:"Sort",kind:"single",options:sortOptions,defaults:["views_30d"],scopes:["search"],required:true}]; },
    async getFeeds() { return sortOptions; },
    async search(input, host) { return catalogue(host,parameters(input.query,input.cursor,input.filters)); },
    async getFeedPage(input, host) { return catalogue(host,parameters("",input.cursor,input.filters,input.feedID)); },
    async getMangaDetails(input,host) {
        const value = object(await request(host,"details",{mangaID:id(input.mangaID)}));
        if (!allowed(value) || value.hid !== input.mangaID) throw Error("Entry unavailable");
        return {...summary(value),description:text(value.synopsis),authors:terms(value.authors ?? value.author),artists:terms(value.artists ?? value.artist),
            status:text(value.status),year:value.year == null ? null : String(value.year), tags:[...terms(value.genres ?? value.genre),...terms(value.tags ?? value.theme)],
            availableLanguages:[{id:"en",title:"English"}],defaultChapterLanguage:"en",webURL:base+"/title/"+input.mangaID};
    },
    async getChapterPage(input,host) {
        if (input.language && input.language !== "en") throw Error("Unsupported chapter language");
        const current = page(input.cursor);
        const result = paginated(await request(host,"chapters",{mangaID:id(input.mangaID),page:current}),current);
        return {...result,items: result.items.map((chapter,index) => {
            object(chapter); const number = typeof chapter.number === "number" && Number.isFinite(chapter.number) ? String(chapter.number) : null;
            return {id:id(String(chapter.id),true),title:text(chapter.name) || (number ? "Chapter "+number : "Chapter"),number,
                ordinal:(current-1)*100+index,language:"en",groups:chapter.group?.name ? [text(chapter.group.name)] : [],volume:null,uploadedAt:null};
        })};
    },
    async getChapterPages(input,host) {
        id(input.mangaID); id(input.chapterID,true);
        const result = object(await request(host,"pages",{mangaID:input.mangaID,chapterID:input.chapterID}));
        if (result.id != null && String(result.id) !== input.chapterID) throw Error("Chapter identity mismatch");
        const container = result.pages; const pages = Array.isArray(container) ? container : container?.items;
        if (!Array.isArray(pages) || !pages.length) throw Error("Chapter has no pages");
        return pages.map((item,index) => {
            object(item); if (typeof item.url !== "string" || !item.url) throw Error("Missing page URL");
            let url = /^https:/.test(item.url) ? item.url : (container.baseUrl ?? "").replace(/\/$/, "") + "/" + item.url.replace(/^\//, "");
            if (!/^https:\/\/[^\s]+$/.test(url)) throw Error("Invalid page URL");
            if ((item.s === 1 || item.scramble === true) && !/[?&]v3(?:&|$)/.test(url)) url += (url.includes("?") ? "&" : "?")+"v3";
            return {id:input.chapterID+":"+index,url,headers:{Referer:base+"/"}};
        });
    }
});
