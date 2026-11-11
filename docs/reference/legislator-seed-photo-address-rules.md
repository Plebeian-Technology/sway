---
mode: reference
summary: "Catalogs the address shapes that must not appear in a committed legislator seed photo URL, and why each one silently loses the person's picture."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Rules for photo addresses in committed seed files

A photo address in the seed files is only ever used once: Sway fetches the
file and keeps its own copy, then serves the copy. If the address has
stopped working by the time that fetch runs, no copy is made and the
person has no face on the site — silently, because the card quietly falls
back to a default picture. The rules below are enforced by
`spec/db/seeds/legislator_photo_addresses_spec.rb`.

## Disqualifying shapes

| Shape | Why it fails | Verified |
| --- | --- | --- |
| A **signed** URL (`X-Amz-Signature`) | Maryland's site hands the browser one carrying `X-Amz-Signature` and `X-Amz-Expires=600`, dead ten minutes after it was generated. Storing one leaves an address that has never worked for anybody who reads it. | — |
| A Drupal **access token** (`?itok=`) | Baltimore's site adds one to every photo, meant to expire. | — |
| One address **pasted onto the end of another** (`https://www.congress.gov/img/member/https://bioguide.congress.gov/photo/<id>.jpg`) | Answers 404, so no copy is made. A leftover from an earlier fetch can carry exactly this shape until the next re-seed overwrites it with the good address. The seed files themselves are clean; this guards against the shape coming back. | — |
| **`http://`** instead of `https://` | Still arrives, but only after an extra redirect hop — and that hop is where photos were lost: mgaleg turns `%20` back into a real space when it writes the redirect address, so members whose file name has a space in it (for example "kramer b.jpg") came back as an address the copier would not accept. Writing `https://` in the first place removes the hop. | Maryland `http://` addresses were fetched over `https://` and every one returned a picture. |

## Why query strings are stripped, with one exception

Neither the signed-URL nor the access-token query string was ever needed:
each address was measured with and without its query string, and every
Baltimore photo came back byte-for-byte identical, while both Maryland
portraits returned a real image unsigned. So the rule is: no query string
on a photo address, unless measurement shows the picture genuinely depends
on it.

The one measured exception is
`ocd-person/943e92d3-98ad-490f-a93a-16182c624a1f`: stripping its query
string does **not** give the same picture — it asks a newspaper's image
service for a crop, and returns 8,420 bytes with the query string versus
160,569 bytes without. It is a fixed crop instruction, not a token, and
carries no expiry, so it stays. A new query string that shows up in the
seed files should be measured the same way: same picture either way,
strip it; different picture, add it to this exception and say what it
does.
