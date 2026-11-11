---
lat:
  mode: explanation
---

# Themed home layout design concepts

The design concepts behind Sway's themed public landing page layouts.

## DefaultHomeLayout

Presents the default Sway landing page as a balanced civic workspace that keeps passkey sign-in immediately reachable above the fold on both mobile and desktop viewports.

On desktop (`lg:grid-cols-12`), the hero statement and three horizontal value-proposition cards occupy a seven-column reading column on the left while [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] spans a five-column rail on the right. On mobile and tablet viewports, the single-column DOM order places the sign-in panel directly beneath the hero statement and above the three feature cards so returning and new voters can authenticate without scrolling past secondary copy.

## BallotHomeLayout

Shows the landing page like the sample ballot that arrives in the mail before an election — a header, numbered instructions for the voter, and signing in framed as checking in at the polls.

One paper-like surface marked off by scanner-style rules, matching the bill layout: no cards, no shadows.

Its `INSTRUCTIONS` list is numbered because ballot instructions are genuinely a sequence — a voter is told to do these things in this order — so the numbering encodes something true rather than decorating three unordered value propositions.

## ChamberHomeLayout

Shows the public landing page like the chamber doors opening.

Shows the public landing page like the chamber doors opening — a plaque-style hero section with a brass-colored rule, the passkey sign-in panel framed as the members' entrance, and the value propositions listed like a formal order of business. Reuses the same dark, formal-agenda look as the chamber bill-detail page.

## MonochromeHomeLayout

Presents the public landing page as a high-contrast editorial sheet with pure black and white ink aesthetics.

A single-column reading column is bounded by a 65-character measure and a 900-pixel container. Narrative hero copy introduces civic participation, followed by a civic tally specimen contrasting solid and double-bordered hatched bars for color-independent vote comprehension, with passkey authentication anchored below.

## ServiceManualHomeLayout

Presents the public landing page through the authoritative, utilitarian lens of a civic digital service manual.

A signature thick accent rule tops the layout, establishing institutional credibility. The structure branches into a two-column desktop masthead and authentication split, housing the hero statement and a left-bordered callout container for key civic guidance alongside passkey sign-in.

## SwissGridHomeLayout

Presents the public landing page as a municipal posting structured around an exposed architectural hairline grid.

An asymmetric two-column framework aligns an explicit 180-pixel left index column with flexible right-hand content bays. Discrete hairline borders delineate numbered municipal sections for the Sway wordmark, mission mandate, and passkey authentication entrypoint.

