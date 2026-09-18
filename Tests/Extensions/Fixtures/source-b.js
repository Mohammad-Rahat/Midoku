var MidokuExtension = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // midoku:/Users/raahat/Projects/PracticeProjects/Midoku/Extensions/fixtures/source-b/index.ts
  var index_exports = {};
  __export(index_exports, {
    default: () => index_default
  });

  // midoku:/Users/raahat/Projects/PracticeProjects/Midoku/Extensions/sdk/index.ts
  function defineExtension(extension) {
    return Object.freeze(extension);
  }

  // midoku:/Users/raahat/Projects/PracticeProjects/Midoku/Extensions/fixtures/shared.ts
  function fixture(source) {
    const summary = { id: "fixture-manga", title: "The Missing Chapter", coverURL: null };
    const chapters = Array.from({ length: 40 }, (_, index) => index + 1).filter((number) => source !== "a" || number !== 21).map((number) => ({
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
      async getFeeds() {
        return [{ id: "all", title: "All fixtures" }];
      },
      async getFeedPage() {
        return { items: [summary], nextCursor: null };
      },
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

  // midoku:/Users/raahat/Projects/PracticeProjects/Midoku/Extensions/fixtures/source-b/index.ts
  var index_default = fixture("b");
  return __toCommonJS(index_exports);
})();
