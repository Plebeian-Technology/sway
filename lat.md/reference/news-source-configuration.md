# News source configuration contract

This contract defines locale-owned newsroom configuration for administrator-requested discovery, with locale YAML authoritative and database instruction rows synchronized.

| Field | Contract |
| --- | --- |
| news_sources | Required array in each config/sway_locales document, including the example; an empty array explicitly disables news discovery for that locale. |
| url | Mandatory HTTPS publisher or section URL; credentials (@), IP literals (IPv4 standard, octal, hex, dword, shorthand, and IPv6), custom ports, local/private destinations (.localhost, .local, .internal, .lan, .home, .corp, etc.), and all-numeric or 0x TLDs are invalid, while public domains with matching substrings are permitted. |
| URL canonicalization | Scheme and host are lowercased; standard port 443 (including zero-padded :0443) is stripped; root empty path is canonicalized to "/" while non-root paths and trailing slashes are preserved. |
| path_policy | Required per source: search_hint or restrict. Existing configured section URLs migrate as search_hint. |
| search_hint | The path guides the search query; article acceptance requires the configured canonical host, not that path prefix. |
| restrict | The configured canonical host and exact path or slash-delimited descendant path are required for result acceptance and redirects. |
| Host comparison | Case-insensitive, with the www prefix normalized; other subdomains require their own configured entries. |
| Runtime owner | The validated locale document; any legacy instruction-row source list is only a synchronized compatibility projection, never an override. |
| source_config_digest | Deterministic SHA256 digest of canonicalized sources sorted by URL, tracking configuration identity across reloads and formatting permutations. |
| Search integration | Dedicated Brave Search API integration via `BraveSearch::Client` is decoupled from LLM summarization route resolution; locale configuration owns sources, not a provider registry. |
| Capability | Configured Brave Search API key (`BRAVE_SEARCH_API_KEY`) is required; missing or unconfigured key produces `unsupported` receipt status before any search requests. |

## Matching evidence

Candidate acceptance records evidence for either direct bill coverage or jurisdiction-relevant issue context; discovery never establishes approval or stance.

| Match | Required evidence |
| --- | --- |
| Direct | Bill identifier (exact or normalized state/federal variants such as `SB 756` / `Senate Bill 756` for `SB0756` and `H.R. 134` for `119-hr-134`), jurisdiction, and session year (across title, snippet, URL, or publication date) match the requested bill; provider labels require the same identity evidence. Missing or conflicting session evidence cannot establish a direct match. |
| Context | Source text names a specific issue grounded in the bill's text or metadata and supplies a local jurisdictional connection; provider labels require evidence, and generic country, chamber-config, or shared words (`city`, `council`, `state`, `both`, `general`) are insufficient. |
| Ambiguous | Retained in request diagnostics with a reason, but not attached as a matched article. |
| Unmatched | Excluded from bill associations; counted separately from request failure. |
| Evidence limits | A title/snippet can support discovery matching but does not qualify as article text for synthesis. Administrator review remains required. |

## Validation limits and canonicalization

DocumentReader enforces strict URL validation and canonicalization rules when parsing locale YAML news sources.

| Rule | Contract |
| --- | --- |
| Scheme | Mandatory HTTPS scheme; non-HTTPS schemes fail validation. |
| Ports | Default port 443 (including zero-padded :0443) stripped; custom ports fail validation. |
| Authority credentials | Forbidden userinfo and user/password credentials (@) fail validation. |
| IP literals | Rejection of IP addresses in all formats (IPv4 standard decimal, octal, hex, dword, shorthand, and IPv6). |
| Private destinations | Rejection of local, internal, and private destination hosts (localhost, exact private hosts, and suffixes .local, .internal, .lan, .home, .localdomain, .corp, etc.); public domains with matching substrings are permitted. |
| Top-level domains | Rejection of all-numeric (.123, .0) and 0x-prefixed (0x12) top-level domains under RFC 1123 §2.1 and RFC 3696 §2. |
| Canonicalization | Lowercase host and scheme, stripping default port :443, empty root path canonicalized to "/", and preservation of non-root paths and trailing slashes. |
| Duplicate detection | Canonical URL comparison after trimming, lowercasing host and scheme, removing default port 443, and normalizing empty root path to "/". |

