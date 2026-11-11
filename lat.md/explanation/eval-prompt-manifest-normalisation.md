---
lat:
  mode: explanation
---
# Eval prompt manifest normalisation

`Eval::PromptDump`'s manifest entry records two hashes and a staleness digest for one bill's dumped prompt bytes. Two of its choices are not obvious from the code alone.

## Why the staleness discriminator is a content digest, not a commit sha

`Eval::PromptDump.builder_content_digest` hashes the CONTENTS of `WATCHED_BUILDER_FILES`, not `git log -1 --format=%H -- <files>`. A commit sha was the first design and was rejected for three reasons that all point the same way.

It under-fires: an uncommitted edit to a watched builder file leaves the last commit's sha exactly where it was, so a dirty working tree — bytes the manifest no longer describes — passes a check whose entire purpose is catching that case.

It over-fires: a commit that touches an unrelated setting in the same file (`lib/sway/settings/llm.rb` carries several) moves the sha and reds the staleness spec for a change that never touched the prompt bytes. A check that reds for no reason gets disabled, which is worse than not having it.

It shells out to git, and specs that shell out to git fail under Docker in a second checkout — the environment this check is most likely to run in.

A SHA-256 over the watched files' own bytes has none of these problems: it moves the moment the bytes it describes move, whether or not that edit is committed, and it never touches git. Each file's repo-relative path is mixed into the digest ahead of its bytes (in `WATCHED_BUILDER_FILES`' own frozen order) so a rename cannot leave the digest unmoved. The manifest also records `builder_digest_files` — the same list — so a later reader can see exactly what the digest covers without cross-referencing the source.

## Why a comment-only edit is re-stamped rather than re-dumped

The digest covers whole file bytes, so an edit to a comment in a watched builder moves it while the prompt bytes it stands for do not move at all.

That is the over-firing the commit-sha design was rejected for, arriving through
a different door, and it is not a reason to loosen the digest. A check that
ignored comments would have to decide what a comment is across five files in two
syntaxes, and the parsing that needs is the parsing a reader can do once, by
hand, on the rare occasion the case arises.

It arose in September 2026, when tracker citations were removed from comments
across the tree and three of the five watched files changed. Two of them changed
only in comments, established by lexing each file's bytes before and after with
Ripper: every changed line was a comment token and none sat inside a heredoc.
The third also carried a type-driven refactor, whose author showed line by line
that the rewritten budget loops select the same rows in the same order and that
a deleted guard cannot fire, because the column's only writer keeps its own copy
of it. A fresh dump was not available either: it reads the diff markdown the
pipeline writes for each reference-set bill, and none of those artefacts existed
on the machine.

Re-stamping writes the current digest and per-file digests into every entry while
leaving each entry's prompt hashes and byte counts exactly as the dump wrote
them. It asserts nothing new about the prompts, and re-dates the provenance of
bytes shown not to have changed. That is honest only with the evidence in hand,
and only for changes somebody has actually read, which is why the ordinary
answer stays a fresh dump.

## Why the payload is built through Llm::PromptPayload, not call

`BillPositionsPromptBuilder#call` returns one joined String, with no seam between the two halves the manifest hashes separately.

Production never uses it for a live call either: `GenerateBillSummaryJob` builds `Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)` and hands that to the adapter. `Eval::PromptDump` copies that exact construction rather than `#call`, so the dumped bytes are the same two strings production actually sends, split the same way.

## Why the user-message hash is delimiter-normalised

`BillPositionsPromptBuilder#user_message` embeds a random 16-hex suffix per `Llm::UntrustedTextBlock` instance, so two dumps of the same bill produce two different raw strings by design.

The unguessable boundary is the security property — see `untrusted-text-block-mechanics`. Left alone, it would make `user_message_sha256` fail to agree across re-dumps for a reason that has nothing to do with the prompt content changing.

`Eval::PromptDump.normalize_delimiters` replaces every `<PREFIX>-<16 hex>` occurrence with `<PREFIX>-<16-hex>` before hashing, iterating `Llm::UntrustedTextBlock::PREFIXES` rather than a hard-coded list so a newly registered prefix is covered without a matching edit here. The manifest entry records `user_message_hash_is_delimiter_normalised: true` so a reader who later hashes a raw user message and gets a mismatch knows why, rather than suspecting a stale manifest.

## Why the summary dump refuses rather than falling back

`BillSummaryPromptBuilder` falls back from missing diff Markdown to extracted text. `Eval::PromptDump` permits that source only for a verified non-amending sentinel.

When the diff file is absent, the builder may instead use the bill's extracted text or a "no text available" note without complaint. The dump validates the sentinel before accepting that fallback.

The fallback is right for production, where a summary built on extracted text is better than no summary at all. It is wrong for a measurement. A dump taken on the fallback holds different source bytes from a dump taken on the diff, so two candidates scored against it are being compared on two prompts rather than on two models — and the diff-fed dimension scores uniformly badly across every candidate for a reason that has nothing to do with any of them.

A deliberate rule keeps missing and stale diffs from silently changing the measured source. `Eval::PromptDump::MissingDiffMarkdownError` names the external id and `LEGISLATION_DIFFS_ROOT`, the setting that decides where those files live, and nothing is written. A verified non-amending sentinel is the narrow exception: the bill must be parsed with `amendment_source` set to `none`, fresh queries must find no section references or amendment operations, and the persisted diff payload must identify the bill, contain its exact extracted-text digest, empty sections, and exact zero stats. The diff timestamp and payload timestamp must be at or after parsing. This is the successful output of [[legislation-pipeline#The legislation pipeline#Diff artifacts describe changes to existing law#Non-amending bills conclude successfully]], where no Markdown diff exists because there is no amendment to render.

The sentinel only admits the extracted-text source already used by production. Its digest binds the sentinel to current extracted text, while `BillSummaryPromptBuilder#source_present?` remains the final gate; if the builder cannot produce a source block, `MissingSourceError` refuses the dump. Any missing, malformed, mismatched, stale, or amendment-bearing diff still raises `MissingDiffMarkdownError` without writing files. The digest also lets unrelated summary saves leave a valid sentinel usable.

This exception can refresh an already committed summary prompt for a verified non-amending bill. `Eval::ReferenceSetSelector` remains diff-only when choosing new references, and its source-character counts remain tied to the diff Markdown used at selection time.

Both are the corrected abort shape this repo already learned to want: name the missing thing and name the variable that decides where it lives, rather than a message nobody can act on.

## Why the caps are asserted and recorded

Three of the four LLM truncation caps resolve smaller in development than anywhere else, and `dip run bundle exec rake` runs there by default. A dump taken under them truncates testimony at under a third of the real cap while looking normal.

The manifest records `effective_caps` — the four values resolved through the builders' own accessors, not the raw settings, because `max_testimony_chars` is additionally bounded by the token budget. That is what lets a later reader tell a hash difference caused by a different truncation configuration from real drift in the prompt text.

Recording alone would not be enough, since a reader who never compares two manifests never notices. `Eval::PromptDump.assert_non_development_caps!` therefore refuses the dump outright when the caps in force are not the non-development values, and names all four settings rather than only the one that drifted.

The refusal message also names the container trap, because an operator who reaches for the obvious fix does not get it: an environment prefix placed in front of `dip run` is dropped, since dip forwards a host variable into the container only when `dip.yml` names it for that command. The four settings reach the process as trailing `NAME=VALUE` arguments to the rake invocation, which Rake reads from its own argv.

## Why the category digest is taken over ordered names

The summary system prompt interpolates the active category names into its output contract, so a machine whose category rows differ produces a different system-prompt hash for a configuration reason, not drift. The digest separates the two.

The digest is order-sensitive by design. `BillSummaryPromptBuilder#active_categories` is `Category.where(active: true).order(:name).to_a`, and `#categories_requirement_note` joins those names with `", "` in exactly that order. A digest over an unordered set would be stable across two configurations that emit different prompt bytes — the one outcome this field exists to prevent.

`Eval::PromptDump` mirrors the builder's own `order(:name)` query rather than writing a second ordering that could drift from it, and commits `active_category_names_ordered` beside the digest so the digest's input is legible without recomputation (REVIEWS finding 14).

An empty digest is not merely a shorter prompt. When the taxonomy is empty the builder omits the `categories` key from the output contract entirely, so the system prompt is structurally different, not just briefer.

## Why the source section heading is recorded

`source_section_heading` is the heading line the builder emitted above the block its answer is grounded in — for the summary type, one of `## Bill diff (bill vs. existing law)`, `## Bill text (extracted)` or `## Bill text`.

Those three headings are the visible trace of which source the builder actually used. A summary entry headed with the extracted-text heading is the warning sign that the fallback fired, and the manifest carries it so that fact is readable without opening the untracked byte dumps. The diff heading clarifies that Sway diffs compare the bill against standing law, not prior bill drafts.

This is defence in depth behind the refusal above. The refusal is the primary control; the heading is what would still surface a fallback if that control were ever weakened or removed, which is why both exist rather than only one.

## What the staleness check does not do

`Eval::ManifestStaleness` compares one digest against another. It does not compare prompt bytes, and it does not re-run either builder.

That narrowness is what lets it run at all on a machine without the corpus. The hash comparison the manifest exists for needs the bills, the diff markdown and the settings to be in place; a phase whose only parity check needs a corpus has no parity check on any other machine. The digest comparison needs the committed manifest and five files' bytes, and nothing else.

The retrospective comparison against production output that earlier drafts of this phase described is out of scope: there is no production reference to compare against, so the whole of the parity claim is internal — the committed bytes are the bytes today's builders emit.

The check also refuses two manifests rather than comparing them. One recorded against a shorter watch list is the artefact that passes while checking nothing, and so is one with no entries at all.

## Why sway:eval tasks stay thin over Eval:: services

Two of this project's gates do not reach into a `.rake` file: `sway:lint:env_reads` parses tracked files under `app/`, and Steep checks `app` and `lib` as its `Steepfile` names them. Logic placed in a task is logic neither one reads.

So `sway:eval:dump`, `:score` and `:reference_set` hold the shape a task is good at — argument reading, iteration over the committed reference set, an aligned-column report, and `abort` — while every typed decision lives in `Eval::PromptDump`, `Eval::ScoreReport`, `Eval::ReferenceSetSelector` and `Eval::ManifestStaleness`, where both gates apply.

The residue is still worth testing. Each task carries refusals that exist nowhere else: `dump` stops when `eval/reference-set.json` is absent, when a pick's `external_id` matches other than exactly one bill, and when any pair failed — it collects every failure and writes no partial manifest rather than stopping at the first. A run that aborted on bill three would report one missing artefact where there may be twelve.

Those refusals are what `spec/lib/tasks/eval_rake_spec.rb` covers, together with the property that the tasks' output carries byte counts and hashes and never payload content. Printing a prompt would put hearing testimony into a terminal scrollback and any log capturing it.

## How ScoreReport and VerdictGate aggregate and guard candidate scores

[[app/services/eval/score_report.rb#ScoreReport]], [[app/services/eval/score_report/renderer.rb#Renderer]], and [[app/services/eval/verdict_gate.rb#VerdictGate]] admit valid verdicts and report score distributions without collapsing them into means.

[[app/services/eval/verdict_gate.rb#VerdictGate]] refuses verdicts where `judge_model` equals the answer's `model_id` or where the answer's recorded prompt hashes differ from `eval/manifest.json`. [[app/services/eval/score_report.rb#ScoreReport]] derives `external_id`, `answer_type`, and `candidate` from the fixture path rather than trusting copy-pasted JSON fields. Admitted verdicts are tallied across [[app/services/eval/score_report.rb#ScoreReport]] alongside self-reported metadata shares ([[app/services/eval/score_report.rb#ScoreReport]]), while [[app/services/eval/score_report.rb#ScoreReport#schema_failure_count]] and [[app/services/eval/score_report.rb#ScoreReport#latency_records]] are reported beside the dimension table rather than folded into a score.
