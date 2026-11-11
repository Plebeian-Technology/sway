---
lat:
  mode: explanation
---
# Private-individual guard regions

ApproveOrgPositionService's private-individual guard used to match an org name against a letter's whole body, refusing any agency a resident named in their own testimony. It now searches only the header and signature regions.

## Character bounds, not marker-based

`#authorship_regions` bounds both regions by character count rather than by finding a marker, so a region is always locatable no matter what the letter's text contains.

A marker-based search — the way `Testimony::SenderReader` locates a `From:` line — can fail to find its marker, and a guard whose fallback on that failure is the whole body would reintroduce the exact bug this fixes.

`BACKSTOP_HEADER_CHARS` (350) and `BACKSTOP_SIGNATURE_CHARS` (150) are sized against the local-only, untracked Baltimore Legistar testimony fixture in `spec/fixtures/testimony/no_campaign_bundle.txt` ([[lat.md/explanation/testimony-fixtures]]): once `Testimony::BoilerplateRemover` strips the phishing banner, its six letters' `From:`/`Sent:`/`To:`/`Subject:` block runs up to 267 characters and its name-plus-address sign-off runs up to 56, so both bounds carry a comfortable margin over what a real letter uses.

## Short letters are searched whole

When a letter is no longer than the two bounds combined, `#authorship_regions` returns it whole rather than carving two windows out of it.

That is the correct outcome, not a fallback: the header and signature windows already overlap and cover the entire text of a letter that short, which is essentially all header and signature already.

## What the bounds give up

Narrowing the search trades one failure for another, and the new one is quieter: a signer whose name sits further from the end of their letter than `BACKSTOP_SIGNATURE_CHARS` is no longer seen.

Such a resident could be approved as an organization where the old whole-body search would have refused.

That trade is deliberate. The old failure was loud and constant — every agency a resident named anywhere in their testimony became permanently unapprovable, which is most of Baltimore's agencies most of the time. The new one needs a letter whose sign-off is buried behind a long trailing block, which `Testimony::BoilerplateRemover` already strips the common causes of.

It is also not the last line of defence. The guard reads a classification the testimony pipeline already made, and an operator sees the refusal before acting on it, so a missed signature is caught by a reader rather than published unseen.

## Direct organization evidence stands the guard down

Before reading a resident's letter, the guard checks whether this bill's testimony also holds a named_organization or public_body letter naming the submitted name — direct evidence it stands down for.

This is defence in depth on top of the matching fix above, not a replacement for it: the private-individual check underneath still runs, unchanged, whenever no matching organization evidence exists.

## Only where the letter identifies itself

The standdown reads an organization letter's header and signature, plus a window around each phrase that classified it as an organization — not the letter's whole body.

Reading the whole body was the first shape of this check, and it conflated two different things: that a letter is an organization speaking, and that the letter is naming *itself*. An agency letter that thanks a council member by name, or cites a resident, carries that person's name in its body like any other prose. Matching it there stood the guard down for that name across the entire bill — so a resident who also signed their own letter could be published as a followable organization with no refusal, no dialog, and nothing in the activity log, which is the exact harm the guard exists to prevent and worse than the false refusals it was added to relieve, because those at least reach a reader.

Two windows alone would not do either, which is why the phrase windows are there beside them. A public body's letterhead phrasing genuinely does sit mid-letter — "on behalf of the ... Department" inside a paragraph rather than on a header line — and `Testimony::SourceKindRules` is already the authority on what that phrasing looks like, since it is the same set of patterns that decided the letter was an organization in the first place. Searching a window that starts at each of those matches and runs `ORG_EVIDENCE_WINDOW_CHARS` past it covers the name that follows the phrase without covering the rest of the letter.

What this gives up is an organization that writes in, is classified by an own-voice phrase like "we urge" that names nobody, and then names itself only in the middle of a paragraph far from any window. That name is refused rather than stood down — and unlike the silent publication above, a refusal is on screen, with the override behind it.

## What the backstop reads, and what it deliberately does not

The backstop works from the name the operator submitted rather than from the
draft's stored one, and it matches on word boundaries above a minimum length
rather than on a bare substring.

Reading the submitted name is what makes it a backstop at all: it has to hold
against a card an operator edited before clicking Approve, which is the threat
the whole pre-check and re-check split exists for, so it cannot key off a token
identifying the draft. A draft position carries no link back to the letter it
came from either.

A bare substring test would refuse "Tenants Union" because a resident wrote
"the tenants unionized", and would refuse any organization whose name is a
common short word the moment one resident happened to use that word — a
permanent refusal with nothing on screen to override. What the backstop is
really bounding is a person's own name lifted out of their signed letter, and a
name below the minimum length is nobody's full name.

The match runs through the extracted-text helper rather than against the raw
string, for the same reason every other phrase here does: the letter came out
of a document converter, so a two-word name can arrive with a line break inside
it.

The check reaches every testimony-sourced caller, including the
claimed-affiliation card, where an operator retypes a name pre-filled from raw
letter text. It deliberately does not reach an admin naming neither a draft nor
a letter. That exemption is deliberate rather than left
to drift: it leaves one route by which a resident's name can be published as an
organization, which is accepted because only an admin can take it and only on
purpose. Refusing there would instead stop an admin recording a position that
disagrees with Sway's own reading of the letters, with nothing on screen to
override it.
