%% lat:begin %%
# Before starting work

- Run `lat search` to find sections relevant to your task. Read them to understand the design intent before writing code.
- Run `lat expand` on user prompts to expand any `[[refs]]` — this resolves section names to file locations and provides context.

# Post-task checklist (REQUIRED — do not skip)

After EVERY task, before responding to the user:

- [ ] Update `lat.md/` if you added or changed meaningful functionality, architecture, tests, behavior, or planned work. Keep it a focused snapshot of current/planned state, not a journal/changelog.
- [ ] Run `lat check` — all validations must pass
- [ ] Do not skip these steps. Do not consider your task done until both are complete.

---

# What is lat.md?

This project uses [lat.md](https://www.npmjs.com/package/lat.md) to maintain a structured knowledge graph of its architecture, design decisions, and test specs in the `lat.md/` directory. It is a set of cross-linked markdown files that describe **what** this project does and **why** — the domain concepts, key design decisions, business logic, and test specifications. Use it to ground your work in the actual architecture rather than guessing. Do not treat `lat.md/` as a journal or changelog; it should be a focused snapshot of current or planned state, and should not grow just to note insignificant details.

# Commands

```bash
lat locate "Section Name"      # find a section by name (exact, fuzzy)
lat refs "file#Section"        # find what references a section
lat search "natural language"  # semantic search across all sections
lat expand "user prompt text"  # expand [[refs]] to resolved locations
lat check                      # run full graph and documentation validation
```

Run `lat --help` when in doubt about available commands or options.

If `lat search` fails because no API key is configured, explain to the user that semantic search requires a key provided via `LAT_LLM_KEY` (direct value), `LAT_LLM_KEY_FILE` (path to key file), or `LAT_LLM_KEY_HELPER` (command that prints the key). Supported key prefixes: `sk-...` (OpenAI) or `vck_...` (Vercel). If the user doesn't want to set it up, use `lat locate` for direct lookups instead.

# Syntax primer

- **Section ids**: `lat.md/path/to/file#Heading#SubHeading` — full form uses project-root-relative path (e.g. `lat.md/tests/search#RAG Replay Tests`). Short form uses bare file name when unique (e.g. `search#RAG Replay Tests`, `cli#search#Indexing`).
- **Wiki links**: `[[target]]` or `[[target|alias]]` — cross-references between sections. Can also reference source code: `[[src/foo.ts#myFunction]]`.
- **Source code links**: Wiki links in `lat.md/` files can reference functions, classes, constants, and methods in TypeScript/JavaScript/Python/Rust/Go/C files. Use the full path: `[[src/config.ts#getConfigDir]]`, `[[src/server.ts#App#listen]]` (class method), `[[lib/utils.py#parse_args]]`, `[[src/lib.rs#Greeter#greet]]` (Rust impl method), `[[src/app.go#Greeter#Greet]]` (Go method), `[[src/app.h#Greeter]]` (C struct). `lat check` validates these exist.
- **Code refs**: `// @lat: [[section-id]]` (JS/TS/Rust/Go/C) or `# @lat: [[section-id]]` (Python) — ties source code to concepts

# Test specs

Key tests can be described as sections in `lat.md/` files (e.g. `tests.md`). Add frontmatter to require that every leaf section is referenced by a `// @lat:` or `# @lat:` comment in test code:

```markdown
---
lat:
  require-code-mention: true
---
# Tests

Authentication and authorization test specifications.

## User login

Verify credential validation and error handling for the login endpoint.

### Rejects expired tokens
Tokens past their expiry timestamp are rejected with 401, even if otherwise valid.

### Handles missing password
Login request without a password field returns 400 with a descriptive error.
```

Every section MUST have a description — at least one sentence explaining what the test verifies and why. Empty sections with just a heading are not acceptable. (This is a specific case of the general leading paragraph rule below.)

Each test in code should reference its spec with exactly one comment placed next to the relevant test — not at the top of the file:

```python
# @lat: [[tests#User login#Rejects expired tokens]]
def test_rejects_expired_tokens():
    ...

# @lat: [[tests#User login#Handles missing password]]
def test_handles_missing_password():
    ...
```

Do not duplicate refs. One `@lat:` comment per spec section, placed at the test that covers it. `lat check` will flag any spec section not covered by a code reference, and any code reference pointing to a nonexistent section.

# Section structure

Every section in `lat.md/` **must** have a leading paragraph — at least one sentence immediately after the heading, before any child headings or other block content. The first paragraph must be ≤250 characters (excluding `[[wiki link]]` content). This paragraph serves as the section's overview and is used in search results, command output, and RAG context — keeping it concise guarantees the section's essence is always captured.

```markdown
# Good Section

Brief overview of what this section documents and why it matters.

More detail can go in subsequent paragraphs, code blocks, or lists.

## Child heading

Details about this child topic.
```

```markdown
# Bad Section

## Child heading

Details about this child topic.
```

The second example is invalid because `Bad Section` has no leading paragraph. `lat check` validates this rule and reports errors for missing or overly long leading paragraphs.

# Diátaxis modes

Documents under `lat.md/tutorials/`, `lat.md/how-to/`, `lat.md/reference/`, and `lat.md/explanation/` are checked against their Diátaxis mode. Declare it explicitly with nested frontmatter, or rely on the directory:

```markdown
---
lat:
  mode: reference
---
```

If a document is in one of the four mode directories, the declared mode must match that directory. Each mode enforces one shape rule: tutorials need an ordered list of steps and a stated outcome; how-to guides need an ordered list of steps; reference docs must not contain narrative prose (no second paragraph under a heading); explanations must not give imperative commands. Run `lat check mode` to validate.
%% lat:end %%

%% lat-fork:begin %%
# lat.md conventions this project enforces

`lat check` fails on the first three rules below. The last two it cannot see,
and they matter as much. None of the five are style preferences. This block is
generated and a later `lat init` replaces it — record project guidance in
`lat.md/`, never here.

## Every document goes in a Diátaxis mode directory

A document belongs in exactly one of four subdirectories, and `lat check mode`
enforces one shape rule for each:

| Directory | Holds | Shape rule |
| --- | --- | --- |
| `lat.md/tutorials/` | a guided first pass for someone new | an ordered list of steps, and a stated outcome |
| `lat.md/how-to/` | a recipe for a task that recurs | an ordered list of steps |
| `lat.md/reference/` | lookup facts: fields, states, limits, names | no narrative prose — no second paragraph under a heading |
| `lat.md/explanation/` | why the design is what it is | no imperative commands |

A document is classified either by the directory it sits in, or by declaring
the mode in its own frontmatter:

```markdown
---
lat:
  mode: explanation
---
```

Both are enforced identically — `lat check mode` applies the shape rule to any
document that declares a mode, whether or not the root index carries
`require-mode: true`. That flag adds a separate rule: a document declaring *no*
mode, in no mode directory, becomes an error too.

Prefer the directory in a tree you own outright. Prefer the declaration when
the file cannot move — a document another project maintains, or a tree other
agents are writing to while you work. Moving costs every reference to the file;
declaring costs nothing at read time, because frontmatter sits above the first
heading and outside every section.

**A document that fails its mode is usually two documents.** A file that lists
the states *and* argues for the design is mixed: the lookup half goes in
`reference/`, the reasoning half in `explanation/`, and each links the other.
Filing it under one mode and softening the prose until the check passes is the
wrong repair.

Classifying a mixed document does not make it pass. Narrative prose put under
`reference/` fails on contact, because a reference may not carry a second
paragraph under a heading — so a move is not a way to adopt the rule cheaply.
Split first, then place. And `explanation` is not the safe default: it bans
only imperative commands, so nearly any prose passes it. Declaring it is a
claim about the document, not somewhere to put whatever is left over. A
document you cannot honestly classify is better left undeclared than
mislabelled.

Classify before writing, not after. If a `diataxis` skill is available, use it.

## Every project has at least one `@lat:` code ref

`lat check` fails a tree that has documents and no `@lat:` ref anywhere in the
codebase. A graph nothing points at cannot be reached from the code, which is
the only reason it exists.

Start at the application entrypoint — `config/application.rb`, `src/index.ts`,
`main.go`, `manage.py`, whatever a new reader opens first — and point it at the
root index:

```ruby
# @lat: [[lat#Acme]]
module Acme
```

Then one ref per section that source code actually implements, placed at that
code. Never in a block at the top of a file.

### An `@lat:` pointer is exempt from this project's comment conventions

A repository that minimises, budgets, or forbids comments is right about prose
comments and does not reach this one. An `@lat:` line is a machine directive,
in the same class as `# frozen_string_literal:` or `// eslint-disable`. It
carries no rationale, asserts nothing a reader could dispute, and cannot rot
quietly — `lat check` fails the moment its target moves or disappears.

Add the ref. Then, if the reasoning that would have been a comment is worth
keeping, put it in a `lat.md/explanation/` section and let the pointer reach it.

### The marker is a comment syntax, not a language allowlist

`//` for C-family languages; `#` for Ruby, Python, shell, Elixir, YAML, Make,
and everything else that comments with `#`. The scan is textual and walks every
non-markdown file in the project, so every language works.

Any list of example languages you find is a list of examples. Never conclude a
language is unsupported because it is absent from one. `lat check` prints what
it scanned:

```
Scanned 41 .md, 622 .rb, 118 .tsx in 1.2s
```

Read that line rather than guessing, and if you are still unsure, add one ref
and run the check. It costs one command.

(The tree-sitter grammars limit only `[[src/file.ts#symbol]]` wiki links, which
resolve a symbol inside source. `@lat:` refs point the other way and have no
such limit.)

## Test specs are wired to their tests

A document describing tests declares it in frontmatter:

```markdown
---
lat:
  require-code-mention: true
---
```

Every leaf section then needs exactly one `@lat:` comment at the test that
covers it, and every section needs at least one sentence saying what it
verifies and why. `lat check` reports any spec section no test claims, and any
ref pointing at no section.

## One specialty per document

A document is **small**, **discrete**, and does **not conflict** with any
other. Those are three demands on the same thing: a reader must be able to
find the one place a fact is written down, and trust it.

**Small — a document covers one specialty.** Not one topic area; one
specialty. When a document covers two, it is two documents. Past roughly forty
sections it has almost certainly become several, and an agent then loads all of
it to reach one part.

**Discrete — each document covers its own specialty.** Before writing a new
document, search for the specialty first:

```
lat search "the thing you are about to document"
```

An overlap has two honest repairs, and picking neither is what produces the
third copy. Either the two are one document and belong merged, or the part they
share is its own document that both link. Deciding they are "mostly different"
and writing anyway is how the set rots.

**Does not conflict — two documents never say different things about the same
specialty.** Never restate a fact another document owns. Link to it with
`[[section]]`. A restatement is a second copy, a second copy drifts, and drift
is how document B ends up contradicting document A while both look maintained.

The mode rule above is the sharpest available test of "one specialty": a
document that fails its mode is usually two documents. Split it. Do not soften
the prose until the check passes.

## Read sections, not files

`lat search` prints a section id and the exact lines that section occupies.
Resolve it with `lat section`, or read only that line range. Opening the whole
file is the reflex to break, and it is the expensive one:

```
lat search "how does backend selection work"
lat section "cli#CLI#search#Backend selection"
```

not a `read` of `lat.md/cli.md`. Measured on lat.md's own graph, the section
costs 4 KB against the file's 44 KB — eleven times the context for the same
answer, and the answer arrives buried in forty-one sections that were not
asked about.

Use `lat expand` on a prompt carrying `[[refs]]` for the same reason: it
resolves each ref to a location and a preview rather than to a file.
%% lat-fork:end %%
