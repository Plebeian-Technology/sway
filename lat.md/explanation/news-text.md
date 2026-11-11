# News text acquisition

The article text service extracts immutable source text. Both background jobs and administrator discovery requests schedule text retrieval for candidate articles lacking text.

## Bounded generic extraction

Article text retrieval applies generic HTML extraction without locale-specific custom scrapers, removing non-editorial layout markup while preserving direct quotes and attributions.

Both [[app/jobs/bill_news_article_fetch_job.rb#BillNewsArticleFetchJob]] and explicit administrator requests through [[app/controllers/admin/bill_news_articles_controller.rb#Admin#BillNewsArticlesController]] schedule text retrieval via [[app/jobs/news_article_text_fetch_job.rb#NewsArticleTextFetchJob]] for candidate articles lacking a text version.

Streaming responses enforce a two-megabyte cap and a fifteen-second read timeout, rejecting non-HTML content types. Extracted prose is scrubbed to valid UTF-8, null bytes are removed, and the final body text is bounded at fifty thousand characters.

[[app/services/news_article_text_fetch_service.rb#NewsArticleTextFetchService]] checks recognized paywall markers, microdata restrictions, in-content login forms, active subscription prompts, and challenge screens before accepting text or metadata. Detected restrictions produce empty paywalled or failed versions with no metadata enrichment or evidence text, regardless of preview length.

The classifier distinguishes article-nested barriers from peripheral layout chrome. It preserves article-nested asides and barrier markers within content containers while removing unrelated layout chrome (headers, footers, navbars, and sidebars outside article containers), ensuring active paywalls and bot challenges inside articles are recognized before text or metadata can be accepted. Rather than relying on raw instruction length, the challenge detector evaluates substantive editorial prose outside verification instruction sentences, preventing long challenge notices from becoming synthesis evidence or contaminating metadata. Unrelated peripheral widgets (such as footer newsletter forms or sidebar ads) and quoted barrier phrases within journalistic reporting remain legitimate readable-article controls.

The required publisher access policy respects robots.txt before article requests and on every redirect hop. [[app/services/news_article_robots_policy.rb#NewsArticleRobotsPolicy]] evaluates crawling permission independently of destination network safety and configured source allowance.

## Robots exclusion policy enforcement

Outbound article retrieval checks publisher robots directives before content requests, normalizing line endings and encoding markers before group matching.

[[app/services/news_article_text_fetch_service.rb#NewsArticleTextFetchService]] consults [[app/services/news_article_robots_policy.rb#NewsArticleRobotsPolicy]] prior to the initial article request and before following every redirect hop. The policy matcher targets the `SwayCivic` user-agent product token case-insensitively, falling back to wildcard `*` groups when no specific group matches. Rule selection follows RFC 9309 longest-match criteria, breaking ties between equal-length Allow and Disallow patterns in favor of Allow. Empty Disallow lines terminate the user-agent section of a record, preserving group boundaries so subsequent user-agent records never fold unrelated crawler directives into prior groups. Rule patterns and request paths are normalized per RFC 9309 §2.2.2 prior to comparison by decoding RFC 3986 unreserved ASCII characters, uppercasing hexadecimal escapes, and percent-encoding non-ASCII octets, with rule specificity lengths derived from the normalized pattern bytesize.

The [[app/services/news_article_robots_policy.rb#NewsArticleRobotsPolicy|parser]] normalizes line endings across CR, LF, and CRLF per RFC 9309 §2.2 and strips any leading UTF-8 byte-order mark before parsing records. This ensures carriage-return-only policies, mixed line terminators, and BOM-prefixed files correctly identify crawler groups and disallow directives without allowing unauthorized retrieval requests.

Recognized access failures refuse retrieval without caching permissive policies. Outbound robots acquisition inspects response bodies for CAPTCHA challenges, login forms, password gates, and paywall markers across HTTP 200, 404, and 410 before admitting policies or treating status as absence. Detected barriers refuse crawling without caching permissive verdicts, issuing zero article requests. Genuine 404 and 410 responses, including ordinary HTML not-found pages without access-barrier evidence, and valid empty or comment-only policies continue to indicate policy absence or permission.

Robots endpoints require HTTPS on port 443 and enforce destination SSRF validation, three-hop redirect bounds, and a 512-kibibyte body limit. Parsed policies and genuine policy absences are cached by origin for twenty-four hours in memory. When a robots policy refuses crawling, retrieval terminates immediately without issuing any request to the article destination, logging `news_article_text_fetch.robots_refused`, retaining a failed text version for auditability, and leaving approved link eligibility intact. In test environments, missing HTTP fixtures fail visibly rather than falling back to permissive fetch behavior.

## Multi-hop SSRF protection

Every outbound HTTP request and redirect hop is validated against SSRF vulnerabilities before any network connection is initiated.

Requests require HTTPS on port 443 with no embedded credentials. Direct IP literals and private host suffixes are rejected. Per-hop DNS resolution verifies that every resolved IP address falls outside loopback, RFC 1918 private ranges, link-local metadata addresses, and reserved CIDR blocks.

## Locale path policy enforcement

Redirect chains are limited to three hops and must strictly adhere to the sway locale's configured news source policies.

The intended rules are owned by [[news-source-configuration]]. The article text fetcher evaluates the request and every redirect against all configured source entries for the matching canonical host, permitting retrieval if at least one valid entry authorizes the destination under its `restrict` or `search_hint` policy regardless of declaration order. If locale source configuration is absent, unreadable, or empty, evaluation fails closed and rejects retrieval. Network destination checks remain separate.

