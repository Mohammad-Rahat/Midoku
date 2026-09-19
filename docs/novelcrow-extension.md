# NovelCrow extension

Midoku bundles `dev.midoku.novelcrow` as a contract-2, browser-rendered source adapter. It is a TypeScript conversion of Keiyoushi's NovelCrow extension and its Madara Legacy behavior.

The adapter keeps NovelCrow's `/comic/` identities, `trending` and `latest` archive ordering, the newer `/<manga>/ajax/chapters` endpoint, lazy-image fallbacks, and unsuffixed chapter URLs. It exposes search sorting, source details, English chapters, and ordered page resources.

All website work is routed through the connection-scoped host. The adapter does not copy cookies, solve challenges, or bypass Cloudflare. A user-visible verification may still be required, and successful offline tests do not establish physical-device clearance.

Offline tests cover request construction, pagination, stable IDs, fractional chapter numbers, page ordering, Referer headers, and malformed input. Live WebKit behavior and a full chapter image path still require device verification.
