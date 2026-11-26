---
lat:
  mode: explanation
---
# News web testimony

Web bill pages present administrator-approved published opinion commentary alongside legislative support and opposition reasoning across all theme layouts.

## Why published opinion commentary sits alongside support and oppose reasoning

Opinion pieces from journalists and community leaders offer substantive policy arguments that help residents weigh the merits and drawbacks of legislation.

Inertia web layouts seat published opinion commentary within the support and opposition sections of bill detail pages. Rather than isolating editorial arguments into a separate generic news feed, placing them directly alongside organizational positions gives voters immediate access to public arguments surrounding the bill.

## Clear demarcation from legislative hearing testimony and organizational positions

Published commentary carries clear visual labeling to prevent readers from conflating external opinion journalism with official committee submissions.

Testimony entries carry explicit news commentary stamps. While organizational positions are stances Sway records for advocacy groups, most of them compiled from public testimony and news reporting ([[organization-affiliation-labels]]), news commentary represents published perspectives from columnists, guest contributors, or editorial boards. Preserving distinct author and publisher attribution prevents an individual columnist's viewpoint from being mistaken for an official newspaper endorsement.

## Attribution fidelity and secure citation navigation

Every commentary block provides explicit author attribution, outlet naming, and validated external navigation to the primary source text.

External citation links undergo strict scheme validation, restricting interactive navigation to HTTP and HTTPS protocols. Unsafe protocols such as JavaScript or data URIs render as inert text. All active links open in new tabs with window isolation attributes and screen reader accessibility cues.

## Multi-theme layout integration

Each visual theme renders published commentary using its native structural conventions without mutating underlying position counts or vote tallies.

Default layout seats commentary within support and opposition cards alongside organization summaries. Ballot layout renders commentary within ballot provision rows. Banner layout displays commentary alongside organization provision articles. Cornerstore layout integrates commentary into its wide position card. Monochrome, Service Manual, and Swiss Grid layouts render commentary inside their dedicated support and opposition sections. Empty testimony collections return null across all layouts, preventing empty containers.
