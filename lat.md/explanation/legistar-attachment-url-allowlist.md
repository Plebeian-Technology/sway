---
lat:
  mode: explanation
---

# Why Legistar attachment URLs go through an allowlist

`Legistar::AttachmentUrl` decides whether a `MatterAttachmentHyperlink` from the Legistar API is safe to request.

This explains why that check exists, what it does and does not cover, and two places its implementation had to be careful for reasons that are not visible from the code alone.

## Why validate at all

`MatterAttachmentHyperlink` is an ABSOLUTE URL sent by Legistar, and Faraday follows it exactly, ignoring the connection's `url_prefix`.

Legistar's own schema carries a `MatterAttachmentIsHyperlink` flag: an attachment row is allowed to point at any third-party URL. "The upstream would never send that" is not a defense — the schema explicitly allows it.

Nothing downstream defends against a bad URL either. The PDF magic-bytes check controls what gets WRITTEN to disk, not what gets REQUESTED. Retry middleware repeats each attempt. The rejection reason shows up in the admin UI. The reach is also large: up to 200 attachment candidates per bill, times every bill in a pipeline run.

The allowlist itself comes from a real recording of the live API, not a guess: every attachment row in that recording is HTTPS on `baltimore.legistar1.com`, measured in `attachment_url_spec.rb`. `legistar.com` is also allowed, since it's the API host this codebase already talks to. Other Granicus tenants sit on their own subdomain — pinning the one tenant currently seen would break the next jurisdiction.

## What the allowlist covers, and what it deliberately does not

`ALLOWED_HOST` matches the two apex domains (`legistar.com`, `legistar1.com`) plus any subdomain of either, anchored at both ends — a host merely ending with or merely starting with an apex does not match.

This allowlists NAMES, not network ADDRESSES. DNS lookup happens later, inside Faraday, so address-level checks belong at connect time (resolve the name first and validate it with `ipaddr`), which is separate work from this allowlist. `ALLOWED_HOST` does not control where packets go, only which names are accepted.

## Normalization happens in exactly one place

`AttachmentUrl.normalize` is the one place an outside string becomes a URL candidate.

Every site that turns a Legistar value into something to check or request goes through it, so the validator and the transport layer can't disagree about what string they're looking at — that disagreement is what `Legistar::AttachmentFetch#call` paid for once already, when the allowlist judged a trimmed copy of a URL and Faraday requested the untrimmed one.

Normalization does two things, both needed before anything else reads the string:

- **Scrub.** `String#strip` raises `Encoding::CompatibilityError` on a
  UTF-8-tagged string holding invalid bytes — not `Rejected` or
  `Faraday::Error`, so it walks past rescues and kills the run.
  `Sway::Utf8.scrub` replaces bad bytes with U+FFFD first, so a mangled host
  can't close into an allowed one, and `URI.parse` refuses the non-ASCII byte,
  rejecting the URL as unparseable rather than raising.
- **Trim.** A whitespace-padded `MatterAttachmentHyperlink` used to pass the
  allowlist and then raise inside the transport.

Scrubbing lives here rather than at the caller because `.allowed?` and `.rejection_reason` promise, in their own specs, to reject bad input without raising. `Legistar::Client` scrubs response bodies too, but that's a different class's property and doesn't cover a value read after parsing.

## The host string is never truncated for the match itself

The rejected-URL message reports the host in every branch, because "which host did it try?" is the first question an operator asks.

A trailing dot is chomped before matching — `baltimore.legistar1.com.` is a legal spelling of the same name, and the anchored regexp used to reject it, failing safe but with no visible cause. Chomping the dot can't widen what matches.

The `host` value that every security decision is made on is deliberately NOT truncated. It used to be cut to `[0, 100]` before matching, which differed from the string `AttachmentFetch` actually opens a socket to. Since `ALLOWED_HOST` is anchored at the end (`\z`), cutting the tail could CREATE a match the real host lacks — a truncated attacker suffix could pass the allowlist and then get requested in full. A separate, display-only `display_host` variable is capped instead, purely so one hostile, extra-long hostname can't push the scheme/port detail off the end of the rejection message; it never narrows the allowlist check itself.

## Why every rejection reason is length-capped through one constant

`MAX_REASON_LENGTH` used to have ZERO references — reasons were capped piecemeal and the caller re-capped separately, with three numbers, none of them matching this one.

A named constant documenting a limit the code doesn't enforce is worse than none, so every `rejection_reason` return now goes through `.bounded`, which applies this one cap. The caller's own `[0, 300]` still covers OTHER messages at that choke point — it isn't replaced by this one.

## Why .allowed? is kept even though production never calls it

`.allowed?` is a pure pass-through to `.rejection_reason`, so two spellings can't drift apart. It has no production caller, and is deliberately kept while two other caller-less methods were deleted, for two reasons:

- What a caller gives up by using it is the REASON string, which
  `.rejection_reason` returns and `Legistar::AttachmentFetch` needs for the
  admin status page — production always needs the reason, never just the
  verdict.
- It is not unused: `attachment_url_spec.rb` is written against it
  throughout, and a boolean assertion reads better as
  `expect(allowed?(url)).to be(false)` than a nil check — this class's
  contract read as a spec.

## Why rejection_reason's message names the host but never the path or query

The reason string is shown in the admin UI.

Echoing an attacker-chosen path back into an operator's browser would give the attacker a way to put their own content on that page, so `rejection_reason` deliberately reports the scheme and host but never the path or query.

## Why .normalize converts to a String before anything else

`.normalize` calls `.to_s` before scrubbing or stripping, because it takes whatever the parsed Legistar JSON held — `MatterAttachmentHyperlink` is a JSON scalar, not necessarily a String.

## Why only port 443 is allowed

[[app/services/legistar/attachment_url.rb#AttachmentUrl]] restricts attachment URLs to port 443 because Legistar serves attachments on default HTTPS and arbitrary ports would allow port-scanning an allowlisted host.
