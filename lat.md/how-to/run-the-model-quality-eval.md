---
lat:
  mode: how-to
---
# Run the model quality eval

The eval measures whether a candidate model's answers to Sway's own bill prompts are any good. It runs only on a machine that holds the local corpus. It cannot run on a fresh clone, and it cannot run in continuous integration.

That limitation is deliberate, not an oversight waiting for a fix. The bills, the extracted testimony and the diff markdown under `LEGISLATION_ROOT` are untracked bulk data, and the local model server is not present in CI. The existing corpus measurement task accepts the same limitation for the same reason. What travels instead is the committed manifest and `Eval::ManifestStaleness`, which reds the ordinary suite anywhere when a prompt builder moves without a re-dump.

## Steps

The whole sequence, from an empty `eval/` to a scored report. Steps 1 to 3 need the corpus; steps 4 to 7 need the committed dumps.

1. Pin the four LLM truncation caps on every rake invocation below. Pass them as trailing `NAME=VALUE` arguments to the rake command itself, not as an environment prefix in front of `dip run` — dip forwards a host variable into the container only when `dip.yml` names it for that command, so a prefix is dropped and the process silently runs under development-sized caps:

    ```bash
    dip run bundle exec rake sway:eval:reference_set \
      LLM_MAX_SOURCE_CHARS=300000 LLM_MAX_TESTIMONY_TOKENS=90000 \
      LLM_MAX_TESTIMONY_CHARS=150000 LLM_MAX_SUMMARY_CONTEXT_CHARS=4000
    ```

2. Choose the reference set with `sway:eval:reference_set`, as spelled above. It bands the local corpus by testimony length, picks 30 bills, and writes `eval/reference-set.json` and `eval/reference-set.txt`. Commit both. If it aborts naming bills with no diff markdown, generate those diffs and run it again; do not shrink the set.
3. Dump the prompt bytes with `dip run bundle exec rake sway:eval:dump`, carrying the same four trailing arguments. It writes each pick's system prompt and user message under `LEGISLATION_PROMPT_DUMPS_ROOT`, which is untracked, and merges one entry per bill and answer type into `eval/manifest.json`. Commit the manifest. If it aborts, it names every missing artefact at once.
4. Start `llama-server` on the host at port 8888, then run the answering candidate over the dumped bytes:

    ```bash
    pnpm run eval:promptfoo -- eval --config scripts/eval/promptfooconfig.yaml
    ```

    That script carries the telemetry-off and isolated-config-directory variables promptfoo needs. Do not approve any of promptfoo's native build scripts; all four are declined on purpose.

5. Place each candidate's answer at `eval/answers/<external_id>/<answer_type>/<candidate>.json`. Candidates that cannot be driven from a rake task — anything answered inside a working session rather than by the local server — arrive the same way, as committed data. This phase makes no Anthropic API call.
6. Author one verdict per answer at `eval/verdicts/<external_id>/<answer_type>/<candidate>.json`. Grading is session work over the committed answers. `Eval::VerdictGate` refuses a verdict whose grader is the candidate that produced the answer, and refuses one written against a stale answer, so a verdict has to name the answer it read.
7. Score with `dip run bundle exec rake sway:eval:score`. It joins every verdict to its answer through the gate, aggregates per-dimension distributions, and writes `eval/REPORT.md`. Commit the report.

## Where each artefact lands

Committed artefacts hold hashes, configuration and judgements. Prompt bytes never reach git.

- `eval/reference-set.json`, `eval/reference-set.txt` — the 30 chosen bills and the band tally behind them
- `eval/manifest.json` — one entry per bill and answer type: both hashes, both byte lengths, the builder class, the builder content digest and its file list, the effective caps, the ordered category digest, the source section heading
- `eval/answers/`, `eval/verdicts/`, `eval/REPORT.md` — the candidates' answers, the graded verdicts, and the scored report
- `LEGISLATION_PROMPT_DUMPS_ROOT` — the prompt bytes themselves, untracked and ignored

## What to do when a check reds

Two checks guard the sequence, and each has one correct response.

- `Eval::ManifestStaleness` reds when a watched prompt file's contents move without a re-dump. Run the dump again and commit the new manifest. Do not edit the manifest by hand; that restores the green without restoring the truth.
- `Eval::PromptDump` refuses to run under development-sized caps, and refuses a summary dump for a bill with no diff markdown. Fix the cause it names — the four trailing arguments, or the missing diff — rather than relaxing the check.
