// Optional, read-only macOS smoke check. No cookies, tokens, or catalogue content are logged.
import AppKit
import WebKit
import Foundation

let app = NSApplication.shared
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800), configuration: config)
let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = web
window.orderFrontRegardless()
let script = #"""
(async()=>{try{
 const main=new URL(document.querySelector('script[type="module"][src*="/main-"]').src);
 const text=await(await fetch(main)).text();const name=text.match(/from\s*["']\.\/(env-[^"']+\.js)["']/)[1];
 const env=await import(new URL(name,main).href),values=Object.values(env);
 const api=values.find(x=>x&&typeof x.list==='function'&&typeof x.chapters==='function');
 const http=values.find(x=>x&&typeof x.get==='function'&&typeof x.post==='function'&&typeof x.patch==='function'&&typeof x.delete==='function'&&!x.chapters&&!x.interceptors);
 const list=await api.list({limit:5,content_rating:['safe'],page:1});
 const item=list.items.find(x=>x.contentRating==='safe'||x.content_rating==='safe');
 if(!item)throw Error('No safe sample');
 const detail=await api.get(item.hid);
 const chapters=await api.chapters(item.hid,{limit:5,page:1,order:{number:'asc'}});
 const chapter=await http.get('/chapters/'+chapters.items[0].id);
 const pages=chapter.pages,items=Array.isArray(pages)?pages:pages.items;
 const urls=items.map(x=>x.url.startsWith('http')?x.url:(pages.baseUrl||'').replace(/\/$/,'')+'/'+x.url.replace(/^\//,''));
 window.smokeResult=JSON.stringify({ok:true,listKeys:Object.keys(list),meta:list.meta||list.pagination,mangaKeys:Object.keys(detail),chapterKeys:Object.keys(chapter),chapterListKeys:Object.keys(chapters.items[0]),pageKeys:Object.keys(items[0]),hosts:[...new Set([item.poster?.medium,...urls].filter(Boolean).map(x=>new URL(x).hostname))]});
}catch(e){window.smokeResult=JSON.stringify({ok:false,error:String(e)});}})();
"""#
final class Navigation: NSObject, WKNavigationDelegate {
    var started = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !started else { return }; started = true
        webView.evaluateJavaScript(script) { _, error in if let error { print("JavaScript setup:", error.localizedDescription) } }
    }
}
let navigation = Navigation(); web.navigationDelegate = navigation
guard let sourceURL = URL(string: "https://comix.to/browse") else { exit(1) }
web.load(URLRequest(url: sourceURL))
Task { @MainActor in
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
        if let value = try? await web.evaluateJavaScript("window.smokeResult || null"), let result = value as? String {
            print(result); fflush(stdout); exit(0)
        }
        try? await Task.sleep(for: .seconds(1))
    }
    print("Comix smoke timed out; interactive verification or site availability may require a device."); fflush(stdout); exit(0)
}
app.run()
