---
lat:
  mode: explanation
---

# What the bundle ships to a visitor

The service worker precaches the built bundle on a visitor's first load, so whatever the build emits is downloaded by everyone — signed in or not, admin or not.

Admin code is therefore split out and fetched only on use, and no unserved entrypoint is built, so the precache stays small.

## Why admin chunks are named apart from the rest

Workbox selects what to precache by globbing the output directory, so the only way to exclude a chunk is to make its path recognisable.

`build.rollupOptions.output.chunkFileNames` sends admin-only chunks to `assets/admin/` and everything else to `assets/`. A chunk counts as admin-only when its `facadeModuleId` is an admin source file, or when every first-party module inside it is one.

The `facadeModuleId` arm carries most of the weight, and it is safe for a reason worth stating: Rollup inlines a module into a chunk only when no other chunk needs it, so a chunk fronted by an admin page contains nothing another page could want. The second arm exists for shared chunks with no facade of their own — reachable from several admin pages and nothing else.

An earlier version had only the second arm and required every module in the chunk to be admin. It missed the Bill Creator, which is the page the whole exercise started from: that chunk inlines shared components, so "every module is admin" was false for it while "only admins can reach it" was true.

## Why the precache excludes them

`globIgnores: ["assets/admin/**"]` keeps those chunks out of the generated manifest, and a `CacheFirst` route in `sw.ts` matching `/assets/admin/` caches them the first time somebody actually loads one.

`CacheFirst` rather than a revalidating strategy because the filenames are content-hashed: a changed file is a different URL, so a cached entry can never be stale. The expiration bound is there to keep the store from growing across deploys, not to catch staleness.

The route matches on the `assets/admin/` path segment rather than a full path, because the build directory is not fixed — every verify run builds into its own `vite-test/run-<id>`.

Admin JavaScript was never a data leak. It is public static code carrying no user content, and anyone could always fetch the URL. What it cost was bandwidth from every visitor, and a description of the admin surface offered to people who have no use for it.

## Why the V1 entrypoint was removed

`app/frontend/entrypoints/legacy.tsx` was built into every deploy and served by nothing.

No layout called `vite_typescript_tag 'legacy.tsx'`, no controller selected a layout that did, and nothing outside `app/frontend/legacy/` imported into that tree. It was a second copy of the page set — its own `Home`, its own Bill Creator — plus the MUI and react-bootstrap dependencies that survive nowhere else, and all of it was precached onto every visitor's device.

Deleting that one file made the whole `app/frontend/legacy/` tree unreachable from any entrypoint, which is what took the manifest from 208 entries to 124. The tree itself has since been deleted.

The plugin's `input` option would also have excluded it, and was rejected: supplying `input` sets `entrypointsDir` to null, which drops that key from `rails-vite.json`, which is what `vite_stylesheet_tag` reads to resolve an entry — it would have re-broken the stylesheet link described in [[shared-stylesheet-entrypoint]].

## Why the bill layouts do not import the markdown renderer directly

`BillSummaryMarkdown` pulls in `react-markdown` and `remark-gfm`, the largest single dependency the build emits, and the bill detail page is the busiest page on the site.

The three theme layouts that show a summary — Ballot, Banner and Corner Store — are themselves loaded through `lazy()` from `layouts/index.ts`. A plain `import BillSummaryMarkdown from …` inside one of them put the markdown code in that layout's own chunk, so every visitor on that theme downloaded it before the layout could render, whether or not the bill had a summary.

`LazyBillSummaryMarkdown` holds the `lazy()` call and the `Suspense` boundary in one file, and every bill surface renders that instead. The markdown chunk becomes a separate download that the layout does not wait on, and the choice is made once rather than in each layout. Its fallback is a blank line of the same shape as the empty-summary state, so nothing on the page moves when the real renderer arrives.

The boundary is inside the wrapper rather than around the layouts because a `Suspense` higher up would blank the whole bill while the markdown loaded.

`BillContent`, which the default `sway` theme reaches through `DefaultBillLayout`, renders the wrapper too. `DefaultBillLayout` is imported statically by `layouts/index.ts`, so a direct import there would have kept the markdown in the layouts index chunk however lazily the other three loaded it. With all four on the wrapper, no chunk the build emits imports the markdown chunk statically: the only two edges to it are dynamic, one from the wrapper and one from the admin summary editor.

[[app/frontend/components/bill/BillSummaryMarkdown.tsx]] parses summary Markdown into semantic elements, while Tailwind's reset removes the browser defaults that normally distinguish headings and lists. The shared wrapper supplies those styles so every bill layout presents the same Markdown structure without depending on the typography plugin.

A test that waits on the rendered markdown text imports the lazy renderer in `beforeAll`, because the first import can outlast Testing Library's default one-second `findBy` wait on a loaded host, while `beforeAll` has a longer hook budget.
