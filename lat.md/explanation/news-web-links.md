---
lat:
  mode: explanation
---
# News web links

Web bill pages present administrator-approved news articles as independent reading links outside summary and testimony blocks across all theme layouts.

## Why approved news links sit outside summary and testimony

Related articles provide broader reportage and surrounding community context without coupling external claims directly to generated bill synthesis or hearing records.

Inertia web bill layouts display approved articles in their own dedicated card or section. Summaries synthesize legislative provisions, while hearing testimonies document formal stakeholder positions. Related news articles offer external press coverage, investigation, and contextual reporting. Separating them from summary text preserves independent editorial grounding while allowing readers to consult primary coverage.

## URL scheme safety and external navigation

External article links undergo client-side scheme validation to prevent script execution, restricting navigable anchors exclusively to standard web protocols.

Web readers only navigate to URLs beginning with `http:` or `https:`. If an article entry carries an unsafe or non-standard protocol such as `javascript:`, `data:`, or `file:`, the component renders the headline as inert text rather than an active anchor. All active external links specify `target="_blank"` with `rel="noopener noreferrer"` and screen reader accessibility cues, preventing reverse tabnabbing and maintaining window isolation. The same scheme validation protects admin Bill Creator surfaces and markdown rendering, ensuring local file paths cannot be linked or prefetched.

## Multi-theme presentation parity

Every web bill theme adapts related news presentation to its own visual conventions while rendering identical underlying evidence.

Default layout seats articles within a standard card component between Sway summary and organization positions. Ballot layout renders a ballot section (`bal-section`) alongside the voting count. Banner layout applies newspaper-style eyebrow headers (`bn-section`). Cornerstore layout incorporates a wide card container (`cs-card--wide`). Monochrome layout uses a proof-sheet section (`mcb-section`), Service Manual uses an institutional reference section (`smb-section`), and Swiss Grid organizes news in a hairline grid row (`sgb-row`). Empty article arrays return null across all layouts, preventing blank cards or orphaned headings.
