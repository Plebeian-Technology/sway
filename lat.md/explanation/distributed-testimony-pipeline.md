---
lat:
  mode: explanation
---

# Distributed bill testimony processing

Bill testimony processing splits work across `clean-testimony` and `summarize-bill` so large hearing bundles do not drop letters at the single-prompt character cap.

See [[bill-positions-prompt-architecture]], [[lat.md/explanation/bill-positions-prompt-limits]], [[lat.md/reference/bill-positions-prompt-limits]], [[testimony-letters]], and [[testimony-coverage-report-invariants]] for the surrounding prompt, splitting, and coverage invariants.

## Before vs. after: why single-prompt truncation dropped hearing letters

Joining every letter and multi-page attachment into one 150,000-character prompt exhausted the budget on early reports and constituent mail, leaving later organization letters out of [[app/services/testimony/coverage_report.rb#CoverageReport]].

<!-- Mermaid diagram temporarily removed due to analysis timeout -->
        L4 --> L6
    end

    subgraph Distributed["AFTER: Cheapest-Per-Step Distributed Pipeline"]
        direction TB
        D1(["104 Cleaned Letters<br/>(Bill 169)"]):::neutralFill
        D2["Batch Classify (25/call)<br/>purpose: :decision<br/>scaledown/classify-1"]:::modelFill
        D3["Stage 1: Clean-Testimony<br/>Per-letter org extract<br/>scaledown/extract"]:::modelFill
        D4["Stage 2a: Prompt Filter<br/>Skip self + repeats<br/>Credit both as reached"]:::accentFill
        D5["Stage 2b: Hints & Window<br/>Add extracted_org hints<br/>Window 12k+ to 9k + 3k"]:::accentFill
        D6["Stage 2c: Chunking<br/>Pack org letters into<br/>1 to 10 whole chunks"]:::accentFill
        D7["Stage 3: Chunk Synthesis<br/>Per-chunk synthesis<br/>deepseek-flash-latest"]:::modelFill
        D8["104 of 104 processed<br/>0 letters left out<br/>Approval Unblocked"]:::goodFill

        D1 --> D2 --> D3 --> D4 --> D5 --> D6 --> D7 --> D8
    end
-->

## End-to-end distributed pipeline across stages

[[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]] classifies and extracts organization entities per letter during `clean-testimony`, while [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] and [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] window and chunk organization letters during `summarize-bill`.


<!-- Mermaid diagram temporarily removed due to analysis timeout -->
    classDef routeNode fill:#fef3c7,stroke:#d97706,stroke-width:2px,color:#78350f
    classDef successNode fill:#dcfce7,stroke:#15803d,stroke-width:2px,color:#14532d
    classDef warnNode fill:#fee2e2,stroke:#b91c1c,stroke-width:2px,color:#7f1d1d

    subgraph S1["1. Clean-Testimony Stage (CleanAndGroupService)"]
        direction TB
        RawBundle(["Raw extracted_testimony<br/>from FetchHearingsService"]):::stageBox
        Split["LetterSplitter:<br/>split into letters 0..N<br/>(Deterministic Ruby)"]:::stageBox
        Dedup["DuplicateLetterMarker:<br/>mark repeat: true<br/>(Deterministic SHA256)"]:::stageBox
        Campaigns["CampaignDraftFinder:<br/>group shared campaigns<br/>(Deterministic n-gram)"]:::stageBox
        BatchKind["SourceKindClassifier:<br/>25 letters per batch<br/>purpose: :decision<br/>scaledown/classify-1"]:::modelNode
        BatchStance["StanceClassifier:<br/>support / oppose / neutral<br/>purpose: :decision<br/>scaledown/classify-1"]:::modelNode

        RawBundle --> Split --> Dedup --> Campaigns --> BatchKind --> BatchStance
    end

    BatchStance --> Router{"Check repeat status<br/>and source_kind"}:::routeNode

    subgraph S2["2. Per-Letter Entity Extraction Stage"]
        direction TB
        SkipRepeat["Repeat letter:<br/>extracted_org = nil<br/>(0 LLM calls)"]:::stageBox
        SkipSelf["Constituent self-letter:<br/>extracted_org = nil<br/>(0 LLM calls)"]:::stageBox
        Window6k["Nameable org letter:<br/>window to 4.5k + 1.5k<br/>if over 6,000 chars"]:::taskNode
        ScaleDown["OrgEntityExtractor:<br/>per-letter entity map<br/>purpose: :extraction<br/>scaledown/extract"]:::modelNode
        ArtifactOut(["Stored cleaned_testimony<br/>on BillLlmProvisioning"]):::stageBox

        Window6k --> ScaleDown --> ArtifactOut
        SkipRepeat --> ArtifactOut
        SkipSelf --> ArtifactOut
    end

    Router -->|"repeat: true"| SkipRepeat
    Router -->|"person_speaking_for_self"| SkipSelf
    Router -->|"org / public_body"| Window6k

    subgraph S3["3. Prompt Assembly & Chunking (BillPositionsPromptBuilder)"]
        direction TB
        FilterSelf["labeled_letters:<br/>skips repeats and<br/>self-letters"]:::taskNode
        CreditSelf["labeled_reach:<br/>credits repeats and<br/>self-letters as reached"]:::taskNode
        HeaderHint["letter_heading:<br/>appends extracted_org<br/>organization hint"]:::taskNode
        LengthCheck{"Letter body over<br/>12,000 chars?"}:::routeNode
        KeepFull["Keep full stripped<br/>letter body"]:::stageBox
        Window12k["window_letter_body:<br/>keeps 9k head + 3k tail"]:::taskNode
        PackChunks["prompt_payloads:<br/>pack whole letters into<br/>1 to 10 chunks"]:::taskNode
        Chunk0["Chunk 0 Payload:<br/>Context + Paste + Orgs 0<br/>+ Opinion + Reporting"]:::taskNode
        ChunkK["Chunks 1..9 Payloads:<br/>Context + Org Batches<br/>(150k chars per chunk)"]:::taskNode

        ArtifactOut --> FilterSelf
        FilterSelf --> CreditSelf
        FilterSelf --> HeaderHint --> LengthCheck
        LengthCheck -->|"12k or under"| KeepFull --> PackChunks
        LengthCheck -->|"Over 12k"| Window12k --> PackChunks
        PackChunks --> Chunk0
        PackChunks --> ChunkK
    end

    subgraph S4["4. Map-Reduce Synthesis & Coverage Gate"]
        direction TB
        CallChunk0["Chunk 0 Synthesis:<br/>generate_bill_positions<br/>deepseek-flash-latest<br/>or gemini-flash-latest"]:::modelNode
        CallChunkK["Chunks 1..K Synthesis:<br/>generate_bill_positions<br/>deepseek-flash-latest<br/>or gemini-flash-latest"]:::modelNode
        ConcatRaw["Merge Chunk Results:<br/>concatenate org positions<br/>+ dedupe news drafts"]:::taskNode
        DedupeOrgs["GroundingService:<br/>ground quotes + dedupe<br/>by canonical org_name"]:::successNode
        CapPositions["Slice to top 30<br/>(MAX_DRAFT_POSITIONS)<br/>& save on provisioning"]:::successNode

        CoverageSum["CoverageReport:<br/>sums reach across<br/>all chunks"]:::taskNode
        OverflowCheck{"Any org letter cut<br/>after Chunk 10?"}:::routeNode
        NoGap["coverage_gap? = false<br/>Approval Unblocked"]:::successNode
        HasGap["coverage_gap? = true<br/>Ack Required"]:::warnNode

        Chunk0 --> CallChunk0 --> ConcatRaw
        ChunkK --> CallChunkK --> ConcatRaw
        ConcatRaw --> DedupeOrgs --> CapPositions

        CreditSelf --> CoverageSum
        PackChunks --> CoverageSum
        CoverageSum --> OverflowCheck
        OverflowCheck -->|"No (100% reached)"| NoGap
        OverflowCheck -->|"Yes (over 10 chunks)"| HasGap
    end
-->

## OpenRouter model routing by pipeline step

[[app/services/llm/route_resolver.rb#RouteResolver]] pairs each pipeline step with its narrowest model purpose on [[app/models/admin_setting.rb#AdminSetting]] so classification and extraction use ScaleDown endpoints rather than full chat-completion models.


<!-- mermaid
<!-- Mermaid diagram temporarily removed due to analysis timeout -->
    S_Stance["Step 1b: StanceClassifier<br/>(25 letters per batch)<br/>support / oppose / neutral"]:::stepCol
    S_Extract["Step 2: OrgEntityExtractor<br/>(1 call per org letter)<br/>6k-char head+tail window"]:::stepCol
    S_Pos["Step 3: Positions Chunks<br/>(up to 150k chars/chunk)<br/>JSON schema + quote ground"]:::stepCol

    P_Dec["RouteResolver<br/>purpose: :decision"]:::purposeCol
    P_Ext["RouteResolver<br/>purpose: :extraction"]:::purposeCol
    P_Sum["RouteResolver<br/>purpose: :summary"]:::purposeCol

    M_Dec["Decision Model (Cheapest)<br/>scaledown/classify-1<br/>(ScaleDown Classify Latest)<br/>Alt: pplx-decider-flash"]:::modelCol
    M_Ext["Extraction Model (Cheapest)<br/>scaledown/extract<br/>(ScaleDown Extract Latest)<br/>Pulls org_name + summary"]:::modelCol
    M_Sum["Low-Cost JSON Synthesis<br/>~deepseek/deepseek-flash-latest<br/>(Deepseek Flash Latest)<br/>Alt: gemini-flash-latest"]:::modelCol

    S_Kind --> P_Dec
    S_Stance --> P_Dec
    P_Dec --> M_Dec

    S_Extract --> P_Ext --> M_Ext
    S_Pos --> P_Sum --> M_Sum
-->

| Pipeline Step | Service / Job | `Llm::RouteResolver` Purpose | OpenRouter Model (`ModelCatalog`) | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **1a. Source Kind (25 letters/batch)** | [[app/services/testimony/source_kind_classifier.rb#SourceKindClassifier]] | `purpose: :decision` | `scaledown/classify-1` (**ScaleDown Classify Latest**) | Uses OpenRouter's decision endpoint (`generate_decisions`) to classify 25 letters per batch into `named_organization`, `person_speaking_for_org`, or `person_speaking_for_self`. |
| **1b. Stance (25 letters/batch)** | [[app/services/testimony/stance_classifier.rb#StanceClassifier]] | `purpose: :decision` | `scaledown/classify-1` (**ScaleDown Classify Latest**) | Uses `generate_decisions` to classify 25 letters per batch into `support`, `oppose`, or `neutral` without chat-completion token overhead. |
| **2. Per-Letter Org Entity Map** | `Testimony::OrganizationEntityExtractor` | `purpose: :extraction` | `scaledown/extract` (**ScaleDown Extract Latest**) | Uses OpenRouter's entity extraction endpoint (`generate_entity_extraction`) on non-repeat organization and public-body letters (windowed to 6,000 chars) to extract `org_name` and `summary`. |
| **3. Chunked Positions Synthesis** | [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] | `purpose: :summary` | `~deepseek/deepseek-flash-latest` (**Deepseek Flash Latest**) or `~google/gemini-flash-latest` (**Gemini Flash Latest**) | With `org_name`, `summary`, and `stance` pre-extracted per letter in Steps 1–2, chunk synthesis uses a low-cost JSON-schema model to consolidate positions and ground quotes. |

## Runtime sequence across clean-testimony and summarize-bill

The runtime sequence traces how `clean-testimony` persists per-letter classifications and extracted organization entities on `cleaned_testimony` before `summarize-bill` chunks, synthesizes, and grounds organization positions.


<!-- mermaid


%% lat-lint: ignore
%%{init: {
  "theme": "dark",
  "themeVariables": {
    "background": "#0f172a",
    "primaryColor": "#1e293b",
<!-- Mermaid diagram temporarily removed due to analysis timeout -->

    Job->>Ground: filter_draft_positions(combined_draft_positions)
    Ground-->>Job: Deduplicated and grounded positions (max 30)
    Job->>Job: Save draft_org_positions and deduped draft_news_testimonies

    Note over Builder,Report: Admin Bill Creator Positions Tab
    Report->>Builder: testimony_reach
    Builder-->>Report: Reached letters + chars across repeats, self-letters, and all chunks
    Report-->>Report: left_out_letters = 0, coverage_gap = false
-->
