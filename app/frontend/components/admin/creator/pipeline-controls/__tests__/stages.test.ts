import { describe, expect, it } from "vitest";
import {
    DEFAULT_STAGE_KEYS,
    isInFlightRunStatus,
    isTerminalRunStatus,
    STAGES,
    STAGE_DISPLAY_NAMES,
    type StageKey,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";

describe("STAGES", () => {
    it("has exactly 8 entries (fetch-bills, fetch-law, extract-text, parse-sections, generate-diffs, fetch-hearings, clean-testimony, summarize-bill)", () => {
        expect(STAGES).toHaveLength(8);
    });

    it("lists stage keys in canonical DAG order", () => {
        const expectedOrder: StageKey[] = [
            "fetch-bills",
            "fetch-law",
            "extract-text",
            "parse-sections",
            "generate-diffs",
            "fetch-hearings",
            "clean-testimony",
            "summarize-bill",
        ];
        expect(STAGES.map((s) => s.key)).toEqual(expectedOrder);
    });

    it("excludes summarize-bill from DEFAULT_STAGE_KEYS so summarizing is off by default", () => {
        expect(DEFAULT_STAGE_KEYS).toEqual([
            "fetch-bills",
            "fetch-law",
            "extract-text",
            "parse-sections",
            "generate-diffs",
            "fetch-hearings",
            "clean-testimony",
        ]);
        expect(DEFAULT_STAGE_KEYS).not.toContain("summarize-bill");
    });

    it("declares fetch-law subtext verbatim per UI-SPEC Copywriting Contract", () => {
        const fetchLaw = STAGES.find((s) => s.key === "fetch-law");
        expect(fetchLaw?.subtext).toBe("Downloads/refreshes statutory law corpus (network)");
    });

    it("declares summarize-bill subtext verbatim per UI-SPEC Copywriting Contract", () => {
        const summarize = STAGES.find((s) => s.key === "summarize-bill");
        expect(summarize?.subtext).toBe("Generate LLM summary + reasoning per bill (calls llama.cpp)");
    });

    it("labels clean-testimony as 'Process testimony' and mentions Clean, Repair, Classify, and Extract steps", () => {
        const processTestimony = STAGES.find((s) => s.key === "clean-testimony");
        expect(processTestimony?.label).toBe("Process testimony");
        expect(processTestimony?.subtext).toMatch(/clean/i);
        expect(processTestimony?.subtext).toMatch(/repair/i);
        expect(processTestimony?.subtext).toMatch(/classify/i);
        expect(processTestimony?.subtext).toMatch(/extract/i);
    });
});

describe("STAGE_DISPLAY_NAMES", () => {
    it("maps summarize-bill to 'Summarize bill'", () => {
        expect(STAGE_DISPLAY_NAMES["summarize-bill"]).toBe("Summarize bill");
    });

    it("maps fetch-law to 'Fetch law'", () => {
        expect(STAGE_DISPLAY_NAMES["fetch-law"]).toBe("Fetch law");
    });

    it("maps clean-testimony to 'Process testimony'", () => {
        expect(STAGE_DISPLAY_NAMES["clean-testimony"]).toBe("Process testimony");
    });
});

describe("isInFlightRunStatus", () => {
    it("treats awaiting_summary_batch as in-flight", () => {
        expect(isInFlightRunStatus("awaiting_summary_batch")).toBe(true);
    });

    it("treats summarizing as in-flight", () => {
        expect(isInFlightRunStatus("summarizing")).toBe(true);
    });

    it("treats completed as not in-flight", () => {
        expect(isInFlightRunStatus("completed")).toBe(false);
    });
});

describe("isTerminalRunStatus", () => {
    it("does not treat awaiting_summary_batch as terminal", () => {
        expect(isTerminalRunStatus("awaiting_summary_batch")).toBe(false);
    });
});
