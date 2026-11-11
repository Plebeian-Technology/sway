---
mode: explanation
summary: "Why SitemapController forces render formats: :xml regardless of the request's Accept header."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `GET /sitemap.xml` forces the XML format

`SitemapController#index` always renders the XML sitemap, no matter what
the request's `Accept` header asks for. The route matches a literal
`.xml` path (not a Rails `:format` segment), so a browser or crawler
sending `Accept: text/html` would otherwise fall through
`respond_to { format.xml }` and raise `ActionController::UnknownFormat`
(HTTP 406 plus a FATAL stack trace). Forcing the format keeps the sitemap
working for every client.
