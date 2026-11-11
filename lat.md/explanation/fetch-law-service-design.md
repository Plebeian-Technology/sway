---
lat:
  mode: explanation
---

# FetchLawService design notes

`FetchLawService` is the law-corpus stage: it reads the city's law text (charter + code) into the database. It is the Ruby port of the old Python script `legislation/fetch_law.py`.

## Why it runs once per pipeline run, not once per bill

It is constructed with `run:` only, and runs ONCE per pipeline run rather than once per bill. It parses Akoma Ntoso XML (a standard XML format for legal documents) and, for each `<container>`/`<section>` pair:

1. Upserts a `LawSection` row — `find_or_initialize_by(sway_locale:, key:)`,
   so re-running updates rows instead of duplicating them.
2. Writes the per-section markdown to
   `legislation/law/<corpus>/<art_slug>/<sec>.md` — the files stay on disk
   so output can be compared against the old Python pipeline's.
3. Builds up a `section_index.json` manifest, tagging each section with its
   status (active/reserved/repealed).

## Why a failure here fails the whole run

Failure raises `StageError`, never `BillProcessingError`.

Failure raises `StageError`, never `BillProcessingError` — because law sections are shared across every bill in the locale, a partial or corrupt law corpus would silently mis-resolve section references for every bill that runs after it, not just one.

## The Nokogiri namespace strategy

The source XML declares the default namespace `xmlns="https://open.law/schemas/library"` (see e.g.

`legislation/law/raw/law-xml-main/us/md/cities/baltimore/charter.xml`), which would force every XPath query to spell that namespace out. Calling `doc.remove_namespaces!` first lets bare `//container` XPath queries be used instead. The parser never writes the XML back out, so losing namespace fidelity costs nothing.

## Why the charter is found by name and the Code by directory

The charter is a single REQUIRED file, found by name (`CHARTER_FILE`) anywhere in the extracted tree.

The Code is OPTIONAL and split across MANY per-article files under a `code/` directory — the Baltimore corpus has no single `code.xml` — so `#locate_code_xmls` finds it by directory, not filename. Mirrors the Python original's `_find_charter_xml` and `_find_code_xmls`.

`#locate_code_xmls` matches every `*.xml` whose path contains a `code` directory, excluding `charter.xml`, sorted so files are ingested in a stable order. The Baltimore corpus splits the Code into per-article files like `code/8.xml` and `code/health.xml` — there is no single `code.xml`, which is why an earlier version that searched for `"code.xml"` by name found nothing and skipped the entire Code.

## Why the download step runs first inside call

`#call` runs `FetchLawCorpusService.new(run: @run).call` before parsing.

The Ruby port originally lost the download step the Python original (`legislation/.archive/fetch_law.py`) ran here, so on production's fresh disk there was no `charter.xml` and `#locate_xml` raised `StageError`. See [[docs/explanation/fetch-law-corpus-service.md|Why FetchLawCorpusService exists]] for how that download step skips re-downloading and tolerates being offline.

## Why resolve_locale raises StageError, never RecordNotFound

`#resolve_locale` raises `StageError`, never `ActiveRecord::RecordNotFound`, on a miss.

`RunLegislationPipelineJob` declares `discard_on ActiveRecord::RecordNotFound`, so a `RecordNotFound` here would silently drop the job and leave the run stuck in `fetching_law` with no failure handler. `StageError` instead flows through `run_run_level_stage`'s rescue into `handle_run_failure`, which marks the run `:failed` and records an `error_message`.

`SwayLocale` has no `name` column — the name is computed — so an earlier `find_by(name:)` here made every lookup miss raise `StatementInvalid` instead of the intended `StageError`. The primary lookup now uses city + state so it is unambiguous, and the fallback goes through the shared computed-name resolver.

Baltimore is hard-coded for now (the Python original did the same). Future locales will pass a `SwayLocale` through `LegislationPipelineRun`.

## AkomaNtosoParser: the same namespace strategy, at the XML-parsing layer

`FetchLawService::AkomaNtosoParser` is the class that actually parses the Akoma Ntoso XML on `FetchLawService`'s behalf, and it carries the same namespace decision described above.

`FetchLawService::AkomaNtosoParser` is the class that actually parses the Akoma Ntoso XML on `FetchLawService`'s behalf, and it carries the same namespace decision described above: the source XML declares the open.law default namespace `xmlns="https://open.law/schemas/library"`. The Python original handled it with an explicit namespace map; here `remove_namespaces!` is called instead, so the bare XPath queries (`//container`, `section`, `num`, `heading`, `text`) all resolve without prefixes. The parser never writes the XML back out, so losing namespace fidelity costs nothing.

## Why AkomaNtosoParser caps XML input at 50MB

`MAX_XML_BYTES` is checked before `xml_path.read` pulls the whole file into one String and Nokogiri builds a DOM from it.

The Baltimore charter is far under this cap, but a future state-code XML could easily pass 100MB; with 3 worker threads (`config/queue.yml`) that could make the OS kill the worker for running out of memory — and a killed worker leaks the global concurrency lock. A full streaming-parser rewrite is still deferred; this cap closes the silent out-of-memory case cheaply.

## Steep narrowing notes

`#call` and `#resolve_locale` both write their nil check as a `case`/`when` rather than an `if x.nil?; raise; end`, so Steep (the Ruby type checker) narrows the result to a definite, non-nil return type.

The `if`-form works at runtime but Steep does not always narrow through it.
