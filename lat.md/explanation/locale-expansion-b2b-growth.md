---
lat:
  mode: explanation
---
# Locale expansion as the B2B growth axis

Strategic evaluation framework governing geographic expansion beyond Maryland by balancing data ingestion costs, roll-call voting fidelity, newsroom partner demand, and single-host hardware limits.

## Strategic context

Sway's initial jurisdiction coverage spans Baltimore City, the State of Maryland, and the United States Congress, establishing a regional beachhead for civic engagement.

Geographic expansion represents Sway's primary business-to-business growth vector. Each new legislative locale unlocks a fresh cohort of prospective newsroom publishers, philanthropic foundations, and civic organizations. However, speculative geographic expansion without sustained local distribution risks diluting engineering resources across disparate legislative data pipelines. To maximize civic impact and operational sustainability, Sway evaluates prospective jurisdictions against four strategic pillars.

## Pillar 1: Upstream data source costs

Each legislative body exposes data through unique technical interfaces that dictate recurring engineering and pipeline maintenance overhead.

Upstream legislative sources exhibit wide variance in accessibility and consistency:

- Modern Legistar API endpoints provide structured JSON data for legislation, committee calendars, and voting actions, minimizing custom scraping logic.
- Jurisdictions relying on legacy web portals, unindexed PDF publications, or dynamic HTML calendars require bespoke scrapers and ongoing pipeline maintenance.
- Ingestion pipelines also parse committee hearing testimony PDFs, which demand reliable text extraction and optical character recognition.
- Prospective locales are evaluated on data accessibility, schema stability, and whether automated pipeline workers can reliably ingest bills without human remediation.

## Pillar 2: Honest-data constraint

Sway prioritizes jurisdictions with transparent individual roll-call votes over bodies that rely heavily on unrecorded voice votes.

Constituent accountability tracking depends directly on comparing citizen votes against the recorded voting actions of their specific elected officials:

- Jurisdictions with granular roll-call records (such as the Maryland General Assembly and the United States Congress) enable robust alignment scoring.
- Conversely, bodies that conduct significant business via unrecorded voice votes, consent calendars, or pass/fail committee procedures obscure lawmaker positions.
- While unrecorded legislation remains educational, jurisdictions lacking recorded roll-call votes are deprioritized relative to bodies providing transparent roll-call tallies.

## Pillar 3: Partner-driven demand pull

Geographic expansion is driven by firm newsroom commitments to syndicate Sway widgets rather than speculative administrative builds.

Rather than building jurisdiction pipelines speculatively, geographic rollout requires verified pull from local journalism outlets:

- Sway enters a new jurisdiction only when an established news outlet or civic media consortium commits to embedding Sway widgets into regular coverage.
- Active newsroom distribution ensures immediate audience reach, generating the constituent volume necessary to meet $k \ge 5$ k-anonymity privacy thresholds.
- Publisher commitment guarantees that pipeline engineering investments are backed by guaranteed distribution and civic participation.

## Pillar 4: Infrastructure capacity ceilings

Expansion must respect the hardware limits of Sway's single-node Raspberry Pi architecture and SQLite concurrency budgets.

Sway operates deliberately on bounded, energy-efficient hardware—a single Raspberry Pi running SQLite in write-ahead logging (WAL) mode:

- Each new locale introduces recurring Solid Queue jobs for bill ingestion, AI bill summarization, and score updates.
- Database write transactions must stay well within SQLite's single-writer throughput limits, preventing worker thread contention.
- CDN edge caching absorbs public iframe traffic spikes, but background ingestion workloads must remain within memory and CPU envelopes.
- Growth is bounded by the volume of legislative activity that can comfortably execute within the single-node maintenance window.
