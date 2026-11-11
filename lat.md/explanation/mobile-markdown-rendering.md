---
lat:
  mode: explanation
---

# Mobile markdown rendering

Bill summaries and organization position summaries on mobile render GitHub-flavored markdown through one shared component instead of the link-only scanner used for news testimony.

The web renders the same text with react-markdown and remark-gfm, so mobile parses with the same mdast family and draws the result with native components, keeping the two surfaces showing the same structure.

## Parsing and truncation

The text is parsed into an mdast tree with the GFM extensions, and the collapsed preview is cut on that tree rather than on the source string.

[[mobile/src/utils/markdownTree.ts#parseMarkdown]] supplies tables, task lists, strikethrough, autolinks and footnotes. Cutting source text could split a link, a table row or a code fence into corrupt fragments, so [[mobile/src/utils/markdownTree.ts#truncateMarkdown]] counts only what a reader sees and treats links, inline code, code blocks, tables and images as single units. A unit that starts inside the budget is kept whole, and every block after the budget is spent is dropped.

Identical bill summaries on screens such as bill detail and featured bills check truncation budgets before rendering, calling [[mobile/src/utils/markdownTree.ts#parseMarkdown]] repeatedly for identical text. Because [[mobile/src/utils/markdownTree.ts#truncateMarkdown]] constructs shallow nodes without mutating the underlying AST, [[mobile/src/utils/markdownTree.ts#parseMarkdown]] retains parsed `Root` trees in an in-memory `Map` bounded by `MAX_MARKDOWN_CACHE_ENTRIES` (100 entries). Cache hits refresh insertion order to maintain least-recently-used eviction, and cache misses evict the oldest entry once capacity is reached. Keying by the exact input string ensures immediate cache misses upon any summary modification while avoiding redundant remark-gfm parser passes during scroll and re-render events.

## Rendering

[[mobile/src/components/Markdown.tsx#Markdown]] turns each mdast node into React Native views and text, and never interprets raw HTML.

Link targets go through [[mobile/src/utils/safeUrl.ts#isSafeCitationUrl]], so an unsafe scheme shows as plain text with no link role. Reference-style links resolve through the document's definitions. Raw HTML appears as literal text, and images appear as their alt text because the layouts have no room for remote pictures. Block text classes come from the caller because React Native text styles do not inherit through views. A `selectable` prop makes the paragraphs and headings selectable text; the organization position cards pass it so a reader can copy a position.

The parsers are ES modules, so the Jest config in [[mobile/jest.config.js]] lists them among the packages it transforms. News testimony keeps [[mobile/src/components/CitedMarkdown.tsx#CitedMarkdown]], which only needs links.

For news testimony passages, [[mobile/src/components/CitedMarkdown.tsx#CitedMarkdown]] splits link targets from body text using [[mobile/src/components/CitedMarkdown.tsx#tokenizeMarkdown]]. Because token truncation creates sliced copies without modifying the underlying token array, tokenized results remain immutable. [[mobile/src/components/CitedMarkdown.tsx#tokenizeMarkdown]] caches tokenized arrays in an in-memory LRU `Map` bounded by `MAX_TOKEN_CACHE_ENTRIES` (100 entries) keyed by the exact raw content string. Cache hits refresh key recency to preserve active passages, preventing repetitive character scanning during fifteen-second polling intervals, list scrolling, or theme changes on memory-constrained mobile devices.
