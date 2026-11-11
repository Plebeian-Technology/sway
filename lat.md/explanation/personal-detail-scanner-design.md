---
lat:
  mode: explanation
---
# Why the personal-detail scanner inverts the credential scanner's skip list

`PersonalDetailScanner` copies `EnvCredentialScanner`'s whole architecture but exists to catch the opposite class of leak, which forces its skip list to be a mirror image of the one it copies from.

`EnvCredentialScanner` (`spec/support/env_credential_scanner.rb`) exists so a credential never leaks out through code that reads `ENV`. `PersonalDetailScanner` (`spec/support/personal_detail_scanner.rb`) exists so a constituent's email address, street address or phone number never leaks into a commit. It keeps the same `git ls-files` sweep, a value class of the same shape (`Finding` here, `Read` there), the same reasoned skip list, and the same `EXEMPT_PATHS` hash whose value is the evidence for allowing a match through.

## Why the scan extensions are inverted

The credential scanner's `SKIPPED_EXTENSIONS` excludes `.json` and `.md` outright, because a credential cannot live usefully in either — a key sitting in a comment or a JSON fixture is not being *read* by anything.

Those are exactly the files `PersonalDetailScanner` exists to read: the eval harness's committed answer and verdict JSON, and the markdown prose describing them. A scanner that inherited the credential scanner's skip list would scan nothing it exists to scan, so `SCANNED_EXTENSIONS` is its own allow-list — `.json` and `.md` — rather than borrowed. The same inversion applies to `SKIPPED_PREFIXES`: the credential scanner skips `.agents/`, `docs/` and `spec/` because those directories quote code and run nothing, but a documentation page that quoted a real address would be exactly as published as any other tracked file. This scanner's skip list holds only `node_modules/`, `.pnpm-store/` and `legislation/` — directories that structurally cannot carry a constituent's detail because nothing under them is ever tracked.

## Why it fails rather than redacts

The scanner never rewrites a file. It only reports a `Finding` and lets the RSpec example fail loudly.

A silent rewrite would change the bytes of whatever it touched and hide the event from the person who caused it — the opposite of what a check like this exists for. If a rewrite ever mattered, it would need to happen where the content is generated or reviewed, not inside a scanner whose only job is to say a line is not safe as committed.

## Why the patterns over-report

Each of the three `DETAIL_PATTERNS` — email, street address, phone — is a plain, low-precision pattern rather than a validated one, by deliberate choice.

A pattern this simple catches an `@sway.vote` business address and a fictional `555-0199` phone number just as readily as a real one, and every false positive costs one `EXEMPT_PATHS` entry naming the evidence for allowing it through — a sentence, checked once. A false negative costs nothing visible until the day it matters: a real home address, already in a commit on a repo with a public remote, in a history that cannot be recalled.

## Why the scanner is proven against an isolated git tree

`scannable_paths` enumerates through `git ls-files`, which always answers "what's tracked" for whichever repository the command runs against — making the class hard to test against a fixture tree living inside Sway's own working copy.

`PersonalDetailScanner#initialize` takes a `root:`, and the scan shells out as `git -C <root> ls-files -z` (via `IO.popen` with an argv array, not a shell string, so a root path containing a space is never re-interpreted). A spec can then build a throwaway git repository under a temp directory, `git add` a handful of planted fixtures into it, and root a scanner instance there — proving the class matches real committed content without ever touching Sway's own index. `EnvCredentialScanner`'s own spec never needs this, because it only ever runs rooted at `Rails.root`.

## Why one example scans Sway's own tree

The isolated-tree examples prove the scanner can detect; a single example rooted at `Rails.root` is what makes it a gate. Without it the class runs only against fixtures it planted itself, and no committed file is ever read.

That distinction is what the `EXEMPT_PATHS` table depends on. The table is a set of claims about paths in the real repository, and a claim nothing re-checks decays: a file gets deleted, a placeholder address gets replaced by a real one, a new document arrives carrying a constituent's detail. The isolated examples cannot notice any of that, because they never look at Sway's tree.

The eval harness raises the stakes: its answer and verdict files derive from hearing testimony, the one corpus in this project that carries constituents' names, addresses and phone numbers. No such file is committed at present, and the real-tree example is what stands between a future transcription slip and a permanent git object.

A red from it names the path and line and stops there. Widening `EXEMPT_PATHS` to clear a red is only correct once the match has been read and matched to one of the five reasons; the entry records that reading, which is why each one carries its evidence rather than a bare constant.

## Why the development storage directory is ignored outright

The directory holding the development containers' databases is ignored by git rather than scanned, and the ignore rule is the only thing standing between it and a commit.

Nothing reads a database at that path — the live development database lives in a Docker named volume — so the only thing a tracked copy could do is publish rows. That asymmetry is what makes an ignore rule the right instrument: there is
no reading to preserve and nothing to exempt, so a scanner finding is not the
outcome worth aiming at.

## Where the current exemptions came from

`EXEMPT_PATHS` holds 13 entries — every tracked file the scanner matches at least once, each one read by hand, none of them a constituent's real detail.

They fall into four shapes, one reason constant each: **`PLACEHOLDER_EMAIL`** (an RFC 2606 reserved example domain or an obviously fake mailbox, mostly inside documentation prose describing code samples and test fixtures), **`PLACEHOLDER_PHONE`** (the `410-555-01xx`/`555-xxxx` block this repo's own docs and UI copy use throughout, matching the NANP-reserved fictional exchange), **`SWAY_OWN_CONTACT`** (Sway's own published `@sway.vote` addresses), and **`PUBLIC_GOV_CONTACT`** (a legislator's or government office's own published contact, seeded from the jurisdiction's own directory, or named in a real bill's title). None was redacted, edited, or reasoned away by narrowing the pattern — each earned its entry the way `EnvCredentialScanner`'s own entries do: read by hand, matched to a reason, and recorded.
