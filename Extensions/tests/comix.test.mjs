import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
async function load() { const context=vm.createContext({});vm.runInContext(await readFile(new URL('../dist/dev.midoku.comix/bundle.js',import.meta.url),'utf8'),context);return context.MidokuExtension.default; }
function host(result) {return {requests:[], async request(r){this.requests.push(r);assert.equal(r.url,'https://comix.to/browse');assert.ok(r.browserScript.length<32768);new vm.Script(r.browserScript);return {body:JSON.stringify({result})};}};}
const manga={hid:'abc123',title:'Example',contentRating:'safe',poster:{medium:'https://comix.to/cover.jpg'}};
test('Comix catalogue filters content and paginates without losing physical IDs',async()=>{
 const api=await load(),h=host({items:[manga,{...manga,hid:'hidden',contentRating:'explicit'}],meta:{page:1,lastPage:2}});
 const result=await api.search({query:'A & B'},h);assert.equal(result.items.length,1);assert.equal(result.items[0].id,'abc123');assert.equal(result.nextCursor,'2');
 assert.match(h.requests[0].browserScript,/content_rating/);assert.match(h.requests[0].browserScript,/A & B/);
});
test('Comix keeps equal and fractional chapter releases, and validates pagination',async()=>{
 const api=await load(),h=host({items:[{id:101,number:4.5,name:'One',group:{name:'A'}},{id:102,number:4.5,name:'Two',group:{name:'B'}}],pagination:{page:2,last_page:2}});
 const r=await api.getChapterPage({mangaID:'abc123',cursor:'2'},h);assert.equal(r.items.length,2);assert.equal(r.items[0].number,'4.5');assert.equal(r.items[1].id,'102');assert.equal(r.items[0].ordinal,100);assert.equal(r.nextCursor,null);
 await assert.rejects(api.getChapterPage({mangaID:'abc123'},host({items:[]})),/response/);
});
test('Comix pages join relative paths and mark v3 without duplicating parameters',async()=>{
 const api=await load(),h=host({id:101,pages:{baseUrl:'https://comix.to/i/',items:[{url:'/1.jpg',s:1},{url:'https://comix.to/i/2.jpg?v3',s:1}]}});
 const r=await api.getChapterPages({mangaID:'abc123',chapterID:'101'},h);assert.equal(r[0].url,'https://comix.to/i/1.jpg?v3');assert.equal(r[1].url,'https://comix.to/i/2.jpg?v3');assert.equal(r[1].id,'101:1');
 await assert.rejects(api.getChapterPages({mangaID:'abc123',chapterID:'102'},h),/identity/);
});
test('Comix invalid IDs, filters and cursors fail before network',async()=>{
 const api=await load(),h=host({});
 await assert.rejects(api.getMangaDetails({mangaID:'../escape'},h));
 await assert.rejects(api.getChapterPages({mangaID:'abc123',chapterID:'0'},h));
 await assert.rejects(api.search({query:'',cursor:'-1'},h));
 await assert.rejects(api.search({query:'',filters:{sort:['unknown']}},h));
 assert.equal(h.requests.length,0);
});
test('Comix details preserve identity and reject mismatched or unavailable records',async()=>{
 const api=await load();const r=await api.getMangaDetails({mangaID:'abc123'},host({...manga,synopsis:'<p>Example</p>',authors:[{title:'Author'}]}));assert.equal(r.description,'Example');assert.equal(r.authors[0],'Author');
 await assert.rejects(api.getMangaDetails({mangaID:'abc123'},host({...manga,hid:'different'})));
});
