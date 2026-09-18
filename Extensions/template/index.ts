import { defineExtension } from "../sdk/index";

export default defineExtension({
    async search({ query, cursor }, host) {
        // Add verified exact domains to manifest.json, request via host.request,
        // parse the source's response, and return stable IDs with normalized metadata.
        // Do not return an empty success for an unimplemented or failed parser.
        throw new Error("Implement this source's search method before registering it.");
    }
});
