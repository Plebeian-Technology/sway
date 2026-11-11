---
lat:
  mode: explanation
---

# Compiling lat.md into the GitHub Wiki

[[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] compiles `lat.md/` into a flat directory of Gollum-compatible Markdown pages for GitHub's `<repo>.wiki.git` repository.

 The step-by-step operator and CI workflow is [[publish-the-github-wiki]].

## How GitHubWikiBuilder compiles lat.md for Gollum

GitHub Wiki runs Gollum over a flat namespace where `[[target|alias]]` reverses pipe order, subdirectories are ignored on lookup, and source symbols in the main repository do not exist.

[[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] resolves five structural differences between `lat.md/` and Gollum when building the wiki directory:

- **Pipe order in `[[target|alias]]` links**: `lat.md/` places the target before the pipe and the display label after it (`[[target|display text]]`), whereas Gollum treats the left side as display text and the right side as the page name. Converting every `[[...]]` link outside fenced code blocks into a standard `[label](url)` Markdown link avoids Gollum's inverted pipe rule altogether.
- **Flat page namespace and duplicate stems**: Gollum flattens all directories into `/wiki/<Page-Slug>`. [[scripts/github_wiki_builder.rb#GitHubWikiBuilder#slug_for]] maps `lat.md/lat.md` to `Home`, keeps unique file stems unchanged, and prefixes any stem shared across multiple mode directories (`bill-positions-prompt-limits`, `bill-summary-prompt-limits`, and `bill-summary-retry-policy`) with its Diátaxis mode (`explanation-...` and `reference-...`).
- **Repository and source symbol links**: Wiki links targeting repository paths or source symbols (`[[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]]`) rewrite to `https://github.com/<repo>/blob/<branch>/<path>` (or `/tree/<branch>/<path>` for directories).
- **Multi-level section heading chains**: `lat` chains ancestor headings in section fragments (`[[page#Heading#Subheading]]`), whereas GitHub heading anchors slugify only the target heading itself (`#subheading`). [[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] takes the final `#` segment and converts it to GitHub's lowercase hyphenated anchor format.
- **Frontmatter, escaped index brackets, and `.md` suffixes**: Leading YAML frontmatter (`---\nlat: ...\n---`) is stripped so GitHub Wiki does not render a metadata table above each page, escaped `\[\[...\]\]` links inside auto-generated `lat:index` summaries are unescaped before link resolution, and `.md` suffixes are stripped from internal wiki links.

## Why source discovery reads git ls-files

[[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] discovers source pages through `git ls-files` with `--exclude-standard` and an explicit `.cache/` filter rather than a raw directory walk whenever `.git` is present.

Local `lat` commands create untracked cache artifacts under `lat.md/.cache/search.db`, `lat.md/.cache/parsed/`, `lat.md/reference/.cache/parsed/`, and `lat.md/config.local.yaml`. Reading git's non-ignored file list guarantees that local caches and machine-local config never enter a wiki build.

## Why GitHubWikiBuilder lives under scripts/

[[scripts/github_wiki_builder.rb#GitHubWikiBuilder]] is a CI/operator build tool rather than part of the Rails web application.

Keeping it under `scripts/` rather than `lib/` keeps it outside `config.autoload_lib` (so Zeitwerk never eager-loads it into Puma or Solid Queue memory) and inside `/scripts/` in `.dockerignore` and `docker/dockerfiles/production.alpine.dockerfile.dockerignore` (so it is never shipped in the production container image).

## Why the workflow probes the wiki remote before cloning

GitHub does not provision `<repo>.wiki.git` until an operator creates the first wiki page in the repository's **Wiki** tab.

`.github/workflows/wiki-sync.yml` runs `git ls-remote` against `<repo>.wiki.git` before cloning and exits cleanly with a `::notice::` annotation if the wiki repository has not been initialized yet. That keeps pushes to `main` green on fresh repositories or forks where the Wiki tab has not been initialized.
