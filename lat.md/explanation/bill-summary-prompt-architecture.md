---
lat:
  mode: explanation
---

# How BillSummaryPromptBuilder assembles the bill-summary prompt

`BillSummaryPromptBuilder` builds a prompt holding everything Rails knows about a bill, so an admin can paste it into a separate agent and get a summary back. It only assembles text: it calls no LLM and no outside service.

See also: `docs/explanation/bill-summary-prompt-security.md` for how this builder defends the prompt against text written by outsiders, and `docs/reference/bill-summary-prompt-limits.md` / `docs/explanation/bill-summary-prompt-limits.md` for the size and count caps it enforces.

## The output contract

The prompt tells the receiving agent to answer with JSON in the shape defined by `config/schemas/bill_summary.json` (`BILL_SUMMARY_SCHEMA`).

The keys are `summary_markdown`, `full_breakdown_markdown`, `categories`, and the optional `cited_section_keys`, which must point at the bill's own `BillSectionReference` rows. Drafting organization positions moved to `BillPositionsPromptBuilder`, so this builder no longer asks for `draft_org_positions`. The schema sets `additionalProperties: false` at both levels, so the prompt must never ask the model for any other key.

## Two pieces, so the fixed part can be cached

The prompt comes in two pieces, `#system_prompt` and `#user_message`.

The first piece is the same for every bill (header, jurisdictional context, output contract), so it is sent as Anthropic's "system" block with `cache_control: {type: "ephemeral"}` and can be cached. The per-bill piece (bill metadata, source text, citation allow-list) is the user turn. `#call` still joins everything in one fixed order.

### The caching contract system_prompt must keep

`#system_prompt` is `[header, jurisdictional_context, output_contract]` joined together — the fixed instructions plus the security paragraph, a fixed primer on the legislatures, and the fixed schema.

It is sent as Anthropic's "system" block with `cache_control: {type: "ephemeral"}`, which cuts the input token cost by about 90% on later calls made within the five-minute cache lifetime.

Every section in `#system_prompt` MUST be byte-for-byte the same for every bill. Anthropic's cache only matches an exact prefix, so a single per-bill value drops the hit rate to 0% AND makes every call pay the cache-writing surcharge (1.25x the base input price) while never reading from the cache — strictly worse than not caching. The per-bill citation allow-list used to sit inside `output_contract`; it now lives in `#user_message`. Nothing derived from a bill may move back into `#system_prompt`.

`#user_message` is the per-bill part: `bill_metadata`, `source_text_section`, and `citation_allow_list_section`, which may be `nil` and is then dropped. None of it can be cached — it differs for every bill, so this part misses the cache on every call by design.

## The one consumer

One consumer exists: `BillsController#summary_prompt_prop`, which puts `#call` on the Bill Creator page as the `summary_prompt` prop so an operator can copy it into another agent.

`#paste_summary` reads the operator's pasted RESPONSE and never sees this builder's output at all.

## Why the output is not the same bytes on every call

THREE `Llm::UntrustedTextBlock` enclosures sit in the prompt — the bill source, the bill context, and the allowed citation keys — each carrying a 16-character hex suffix generated fresh per instance.

Being impossible to guess from a prompt someone saw earlier IS the security property, so two calls for the same bill differ on purpose.

## What the byte-stability spec pins

What is pinned: `#call`'s SECTION ORDER and every byte outside those three suffixes, against TWO captures.

What is pinned: `#call`'s SECTION ORDER and every byte outside those three suffixes, against TWO captures — one for a bill with no parsed sections and one for a bill with them, since the allow-list section is absent entirely in the first shape and a single capture pinned only that one, so changing the prompt an operator sees takes a deliberate act either way. The spec normalises exactly those three suffixes, builds the list from the constants so a fourth enclosure cannot slip past, and guards the normalisation with an example proving the suffixes really are random — see the "byte-stability fixture" describe block in `spec/services/bill_summary_prompt_builder_spec.rb`. The security paragraph in `#header` covers the risk that the bill's own source text contains instructions aimed at the model; the same unforgeable enclosure `BillPositionsPromptBuilder` uses backs it up. The delimiter suffix is the one run of bytes in the fixture that is random on purpose.

## No testimony is read here

This builder reads NO testimony of any kind.

It once spliced in `provisioning.supplemental_testimony`, which mixed advocacy into what has to be a neutral account of the legislation. Only `BillPositionsPromptBuilder` reads `supplemental_testimony` now.

## The source-present / source-text agreement rule

The rule this class must keep: `#source_present?` and `#source_text_section` read the SAME inputs in the SAME order.

The first decides whether to spend money — callers pay for an LLM call based on it — and the second is what the model actually receives. If one counts a source the other does not render, you pay for a prompt with no bill in it. Any new source has to be added to BOTH or to NEITHER. `spec/services/bill_summary_prompt_builder_spec.rb` pins the agreement as a four-state matrix (nothing at all / `diff_content` only / `extracted_text` / on-disk markdown), because the code once broke the rule while this comment claimed it held.

### The source spend gate: source_present?

`#source_present?` is true when there is real material to summarize: a diff markdown file on disk (bills that amend existing law) or extracted bill text (bills that do not, such as resolutions and appointments).

These are the SAME two reads `#source_text_section` makes, in the SAME order, so this is false in exactly the cases where the rendered prompt falls through to "No bill text is available yet". Callers (`GenerateBillSummaryService`, `GenerateBillSummaryJob`) can therefore read it as "the prompt will have a bill in it". Adding a branch to one of the two methods and not the other breaks that; `spec/services/bill_summary_prompt_builder_spec.rb` pins the agreement as a four-state matrix rather than leaving it to this comment.

This method used to count `provisioning.diff_content` as a third signal, and the comment claimed it mirrored the renderer. It did not — `#source_text_section` has never read that column. The damage was not cosmetic: a bill whose only artifact was `diff_content` passed this spend gate, we were BILLED for a prompt telling the model there is no bill text, and whatever the model made up came back, was saved as `llm_summary`, was marked `citations_valid`, showed a green "Ready", and was offered up for promotion to the public `bills.summary`.

`diff_content` is not source text and cannot be turned into it. It is the JSON COPY that `GenerateDiffsService#persist_diff_artifact!` writes for `Pipeline::ArtifactPresence`, and `#strip_helper_keys` deletes every key holding text (`_diff_block`, `_before_text`, `_warnings`, `_resolution`) before it is saved — what survives per section is `key`, `article`, `title`, `status` and `operations_applied`. Rendering that would feed the model section identifiers and `section_not_found` statuses with no legislative content in them: the same invitation to invent, a longer prompt, and a bigger bill. Hence a narrower gate rather than a fourth branch in the renderer.

Bills that amend nothing lose nothing they had. `#persist_diff_artifact!` runs on that branch no matter what, so a resolution with no PDF only ever carried the empty placeholder (`"sections": []`, every statistic zero) anyway. What changed is that the job now says so instead of buying a summary of it — see the nothing-to-generate ending of `GenerateBillSummaryJob`, which has to stay paired with this narrower gate.

Both reads are scrubbed of invalid bytes. Scrubbing `MupdfExtractor`'s output where its subprocess hands it over stops NEW bad bytes from being written, but it does not clean up `bill.extracted_text` rows or `legislation/bills_text/*.md` files that earlier builds already wrote. This method is the first thing `GenerateBillSummaryService#call` touches when an admin posts the form, and `String#present?` raises `ArgumentError` on invalid bytes — NOT the `Encoding::CompatibilityError` that ActiveSupport rescues — which would be an uncaught HTTP 500. `BillPositionsPromptBuilder` takes the same last-line-of-defense stance.

## initialize: the active_categories parameter, and class history

`@param active_categories [Array<Category>, nil]` — pass the active categories in to skip a query at call sites that only ask `source_present?`.

When it is `nil`, the list is looked up the first time it is needed, via `Category.where(active: true)` — so a caller that only checks `source_present?` runs no query at all. The summary job passes its already-loaded array; all four existing one-argument `.new(bill)` call sites still work, because the keyword has a default.

This class no longer holds the `BillLlmProvisioning` row. Its last reader was `#scrubbed_diff_content`, which went away when the source gate was narrowed; the other reader, `#supplemental_section`, had already gone. The class reads the `Bill` and nothing else, which is what lets you confirm by eye that the spend gate counts exactly what the prompt renders.

## Categories: what to say when there are none to choose from

The old single version filled in an empty list and then forbade the only honest answer: "choose 1–3 categories from the active taxonomy: .

... Never return an empty array." A model that follows orders invents names. That text shipped inside the CACHED part of the prompt, so every summarize call in a deployment with no active categories paid for it, while the response side behaved correctly (`generate_bill_summary_job.rb` skips the assigner and logs `no_active_categories`) — money spent telling the model to make up a field the job was already going to ignore.

"Do not emit it" is allowed by the contract: `categories` is optional in `BILL_SUMMARY_SCHEMA`, whose only required key is `summary_markdown`, so leaving it out still validates. `BillCategoryPromptBuilder` is the opposite — its schema REQUIRES a non-empty categories array, so with no categories there is no honest prompt to write at all and that builder refuses to be constructed.

Caching is unaffected: this depends on the category list, which is the same for every bill, so the cacheable part stays byte-for-byte identical across bills within a deployment. It changes only when an admin changes the active set, which was already true of the category names themselves.

## MAX_CATEGORIES and schema authority

The upper number for how many categories the prompt asks for comes from `MAX_CATEGORIES`, which reads `bill_summary.json`'s `maxItems`.

An earlier version of this comment argued the two could safely drift, on the grounds that `BillCategoryAssigner`'s `.uniq.first(Category::MAX_ACTIVE_PER_BILL)` trims anything extra. It does not get the chance: the adapter validates the reply against `BILL_SUMMARY_SCHEMA` first, so a reply with one category too many is thrown away whole and the summary that was paid for goes with it. The trim still earns its place — it catches duplicate NAMES collapsing under the cap, which the schema counts as separate items.

`Category::MAX_ACTIVE_PER_BILL` is deliberately NOT the source here. It is the cap on what is stored, and a reply that passes it is trimmed locally at no cost; `maxItems` is the one that discards paid work.

## Output contract keys: prose and JSON must agree

The key list in `#output_contract_keys_json` and the prose around it have to agree.

"Return a single JSON object with exactly these keys" over a block containing `categories`, three lines above "Do NOT emit `categories`", is the same contradiction one level down — and the example object is the part a model is most likely to copy.

`cited_section_keys` is the SAME contradiction and could not be closed the same way. Dropping it per bill would make `#system_prompt` differ from bill to bill, which takes the prompt cache hit rate to zero while every call still pays the cache-write surcharge, so the framing above was fixed instead — it no longer says "exactly these keys" — and the value shown is a bracketed instruction rather than a plausible key. A model that copies `art_14__sec_301` onto a bill with no parsed sections gets it validated against an empty allow list, and the operator reads a red invalid-citation warning on a summary that had nothing to cite. Both edits leave `#system_prompt` byte-identical across bills.

`#output_contract_keys_json` is built line by line rather than as a heredoc, so the one optional key does not need a splice in the middle of the object.

## Why TRUNCATION_NOTICE is appended rather than silently cutting the tail

`TRUNCATION_NOTICE` is appended in place of the dropped tail so the model — and any operator reading the prompt — knows the summary is based on a partial source.

## call's six sections, and how the API split shares them

`#call` keeps the original six-section order: header, bill metadata, source text, citation allow list, jurisdictional context, output contract.

`#system_prompt` and `#user_message` regroup those SAME six sections for the Anthropic system/user split; the order in `#call` is its own thing and must stay stable against the captured fixture — every byte of it except the two per-instance delimiter suffixes, which are random by design.

## active_categories: memoized, query-free until needed, and ordered for the cache key

`#active_categories` works out the active category list once and remembers it.

When the caller passed an `active_categories:` array, that array comes straight back and no query runs. When it was `nil`, as at the one-argument `.new(bill)` call sites, the query runs the first time this is called. `#source_present?` never calls this method, so it pays nothing.

The query orders by `.order(:name)` to keep the categories in one predictable order, so the rendered `output_contract` — and with it Anthropic's prompt cache key — stays the same between calls.

## allowed_citation_keys: ordering, null titles, and why the accumulator is not redundant

`#allowed_citation_keys` returns the list of sections the model is allowed to cite.

`BillSectionReference` has a default scope of `.order(:ordinal)`, so the row order is already fixed. `title` can be null, for references that were never resolved. An empty result means the bill has no parsed sections yet; `#output_contract` then leaves the citation paragraph out entirely rather than rendering an empty allow-list.

The accumulator in this method is not redundant, though it reads that way — `pluck(:key, :title)` already returns pairs. `rbs_rails` types `#pluck` as `Array[Array[untyped]]`, and `Array[untyped]` is not a subtype of the tuple `[String, String?]` this method declares, so returning `pluck`'s result directly fails Steep. Neither a `#:` on the call nor a `#:` on an assignment of it is accepted (both were tried). Rebuilding through a typed accumulator is the only form that keeps the declared tuple type, and weakening the type to get one line back would push `String?` onto `key` at every reader.

## Why the source-text fallback order avoids "Analysis Status: Incomplete"

`#source_text_section` prefers the diff markdown `GenerateDiffsService` wrote to disk.

It falls back to `extracted_text` for bills that amend nothing, since `GenerateDiffsService` writes no file for those. It only uses the "no source" wording when neither exists, so the model has a real chance of writing a substantive summary instead of "Analysis Status: Incomplete".

Both of the first two branches carry text written by outsiders, so the body goes inside an `Llm::UntrustedTextBlock` rather than a ``` fence, which anyone could fake. The third branch is fixed wording this class wrote itself — nothing to enclose.

## on_disk_diff_markdown: reading the writer's own path builder, and the rescue that treats "cannot read" as "not on disk"

`#on_disk_diff_markdown` is the reading half of `GenerateDiffsService::ResultWriter#write_markdown`.

Both halves build the path with `Legislation::Paths`, so they cannot end up pointing at different files. Nothing here raises: this runs when an admin posts the form, and an external ID that will not turn into a path means "no diff on disk", not a 500.

Checking `exist?` and then calling `read` leaves a gap in which the file can vanish, and the open itself is unguarded. This runs inside the `generate_summary` stage AND on the admin POST path, so an `Errno` would either kill the run with a `StageError` or return a 500 on the one page whose whole job is to show the operator a prompt. The diff is optional by design — every other way of not having it already returns `nil` — so "cannot read it" gets the same answer as "not on disk", via a rescue on `SystemCallError, IOError`.

## truncate_source: why the cut keeps the start of the document

`#truncate_source` cuts the embedded source text down to what `.max_source_chars` returns and adds `TRUNCATION_NOTICE` when it had to cut.

It keeps the start of the document, which for a bill is the title, the findings and the opening sections; the end is the cheaper part to lose. Extracting only the ordinance text instead of the whole testimony bundle would make truncation rare in practice; that fix is still open.
