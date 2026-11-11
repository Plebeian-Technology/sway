---
lat:
  mode: explanation
---
# News mobile testimony

Native bill detail and Bill of the Month screens present administrator-approved published opinion commentary alongside legislative positions with source attribution and clickable citations.

## Placement of published commentary inside support and oppose cards

Opinion pieces from columnists, contributors, and editorial boards provide policy arguments that assist voters in evaluating legislation.

Mobile bill surfaces place published commentary inside organizational position cards. Seating commentary within the existing support and opposition containers presents editorial arguments alongside stakeholder perspectives while preserving vertical hierarchy and screen layout order.

## Clear visual demarcation and distinction from organization positions

Published opinion commentary carries distinct stamp badging to prevent readers from confusing external journalism with official committee filings.

Every commentary entry carries a dedicated news commentary badge in a warning tone. While organizational positions represent official submissions from registered groups, commentary represents published opinion pieces. Distinguishing individual authors from publishers prevents an individual columnist's column from being interpreted as an institutional endorsement.

The badge is [[mobile/src/components/WarningStamp.tsx#WarningStamp]], shared with the related-news cards, which use it for opinion pieces, op-eds and editorials ([[news-mobile-links#Placement outside summary and testimony]]). It reads the warning token for the active colour scheme from `swayTokens` and applies it inline, because the Tailwind `warning` colour is one flat yellow that does not change with the scheme and fails contrast as text on a light card. The text and border take the token itself, and the fill is the token at a low opacity, so the label keeps at least 4.5:1 contrast against its tint in both modes.

## Attribution fidelity and institutional fallback

Commentary blocks display explicit author bylines and fall back to institutional editorial board attribution when individual authors are absent.

Articles with a named columnist render an explicit byline. When an author is omitted, the presentation attributes the perspective to the publisher's editorial board without creating redundant duplicate labels. This attribution design ensures that unsigned institutional editorials remain distinct from signed columns.

## URL safety and markdown citation parsing

External citation links and in-prose commentary citations undergo strict URL scheme validation before invoking platform navigation handlers.

Native devices route external navigation through operating system URL handlers. Using WHATWG URL parsing, the component confirms citation links use HTTP or HTTPS protocols and contain no embedded credentials. Dangerous schemes like JavaScript or file URIs render as inert text. In-prose links within commentary arguments are parsed via cited markdown rendering.

The argument text is selectable, so a reader can long-press to copy it. Selection is set on the argument's root text only; the citation links inside it stay tappable, which the tests check with a press on each link.

## Zero-node suppression and screen lifecycle

Native bill screens emit zero native nodes when commentary is absent or when transitioning between bills and locales.

When a bill has no approved commentary for a stance, the component returns null, avoiding empty cards or extraneous margins. On the featured bill screen, switching locales refreshes bootstrap state, and the newly featured bill remounts the screen's keyed detail body, which drops the previous bill's commentary until the new bill's detail arrives. On the bill detail screen, route transitions reset cached testimony, preventing stale commentary from persisting across bill views. The constituent-letter card follows a rule of its own, tied to sign-in and to counts ([[mobile-bill-surface-components-design#PublicTestimonySection]]).
