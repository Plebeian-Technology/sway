// @lat: [[pipeline-busy-terminal-status-inversion#pipeline-controls/stages.ts definitions]]
export type StageKey =
    | "fetch-bills"
    | "fetch-law"
    | "extract-text"
    | "parse-sections"
    | "generate-diffs"
    | "fetch-hearings"
    | "clean-testimony"
    | "summarize-bill";

export const STAGES: ReadonlyArray<{ key: StageKey; label: string; subtext: string }> = [
    { key: "fetch-bills", label: "Fetch bills", subtext: "Downloads bill metadata + PDFs from Legistar (network)" },
    {
        key: "fetch-law",
        label: "Fetch law",
        subtext: "Downloads/refreshes statutory law corpus (network)",
    },
    {
        key: "extract-text",
        label: "Extract text",
        subtext: "Runs OCR (tesseract) on the downloaded PDFs — this is the slow one you're watching",
    },
    {
        key: "parse-sections",
        label: "Parse sections",
        subtext:
            "Takes the OCR'd text and splits it into structured sections (§ 4-101, etc.) using fuzzy matching — pure CPU on already-extracted text",
    },
    {
        key: "generate-diffs",
        label: "Generate diffs",
        subtext: "Computes added/removed/modified text between current bill and prior law",
    },
    { key: "fetch-hearings", label: "Fetch hearings", subtext: "Hits Legistar for hearing schedules (network)" },
    {
        key: "clean-testimony",
        label: "Process testimony",
        subtext:
            "Clean, repair, split, group, classify (speaker + stance), and extract organization entities from fetched hearing testimony",
    },
    {
        key: "summarize-bill",
        label: "Summarize bill",
        subtext: "Generate LLM summary + reasoning per bill (calls llama.cpp)",
    },
];

// @lat: [[bill-creator-pipeline-controls-panel#The page's control props follow URL precedence]]
export const DEFAULT_STAGE_KEYS: ReadonlyArray<StageKey> = STAGES.map((s) => s.key).filter(
    (key) => key !== "summarize-bill",
);

// @lat: [[pipeline-stage-auto-include-reduced-work#Why the auto-included stage chips are comma-separated with a screen-reader-only comma]]
export const REDUCED_WHEN_AUTO_INCLUDED: ReadonlyArray<StageKey> = [
    "fetch-bills",
    "extract-text",
    "parse-sections",
    "generate-diffs",
    "fetch-hearings",
    "clean-testimony",
    "summarize-bill",
];

export const STAGE_DISPLAY_NAMES: Record<string, string> = {
    "fetch-bills": "Fetch bills",
    "fetch-law": "Fetch law",
    "extract-text": "Extract text",
    "parse-sections": "Parse sections",
    "generate-diffs": "Generate diffs",
    "fetch-hearings": "Fetch hearings",
    "clean-testimony": "Process testimony",
    "summarize-bill": "Summarize bill",
};

// @lat: [[pipeline-busy-terminal-status-inversion#pipeline-controls/stages.ts definitions]]
export const PHASE_52_STAGE_STATUSES = [
    "fetching_bills",
    "fetching_law",
    "extracting_text",
    "parsing_sections",
    "generating_diffs",
    "fetching_hearings",
    "cleaning_testimony",
    "summarizing",
    "awaiting_summary_batch",
] as const;

export type Phase52StageStatus = (typeof PHASE_52_STAGE_STATUSES)[number];

// @lat: [[pipeline-busy-terminal-status-inversion#pipeline-controls/stages.ts definitions]]
export const PHASE_52_STAGE_STATUS_LABELS: Record<Phase52StageStatus, string> = {
    fetching_bills: "Fetching bills",
    fetching_law: "Fetching law",
    extracting_text: "Extracting text",
    parsing_sections: "Parsing sections",
    generating_diffs: "Generating diffs",
    fetching_hearings: "Fetching hearings",
    cleaning_testimony: "Cleaning testimony",
    summarizing: "Summarizing",
    awaiting_summary_batch: "Awaiting summary batch",
};

// @lat: [[pipeline-busy-terminal-status-inversion#pipeline-controls/stages.ts definitions]]
export const PHASE_52_NON_TERMINAL_STATUSES = ["queued", "running", ...PHASE_52_STAGE_STATUSES] as const;

export type Phase52NonTerminalStatus = (typeof PHASE_52_NON_TERMINAL_STATUSES)[number];

// @lat: [[pipeline-busy-terminal-status-inversion#Listing FINISHED statuses, not busy ones]]
export const TERMINAL_RUN_STATUSES = ["completed", "succeeded", "partial", "failed", "cancelled"] as const;

export type TerminalRunStatus = (typeof TERMINAL_RUN_STATUSES)[number];

export type TPipelineRunStatus = Phase52NonTerminalStatus | TerminalRunStatus;

export const isTerminalRunStatus = (status: string | null | undefined): boolean =>
    typeof status === "string" && (TERMINAL_RUN_STATUSES as readonly string[]).includes(status);

export const isInFlightRunStatus = (status: string | null | undefined): boolean =>
    typeof status === "string" && (PHASE_52_NON_TERMINAL_STATUSES as readonly string[]).includes(status);
