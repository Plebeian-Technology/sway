import { describe, expect, it } from "vitest";
import { failedStageInfo } from "app/frontend/components/admin/creator/pipeline-controls/failedStageInfo";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

const run = (overrides: Partial<ILegislationPipelineRun>): ILegislationPipelineRun =>
    overrides as ILegislationPipelineRun;

describe("failedStageInfo", () => {
    it("returns nulls / unknown for a null run", () => {
        const info = failedStageInfo(null);
        expect(info.failedStageNumber).toBeNull();
        expect(info.failedStageName).toBe("unknown");
        expect(info.parentShortId).toBe("");
    });

    it("prefers the failed pipeline_run_stages row", () => {
        const info = failedStageInfo(
            run({
                pipeline_run_stages: [
                    { stage_name: "fetch-bills", status: "succeeded", position: 1 },
                    { stage_name: "extract-text", status: "failed", position: 2 },
                ],
            }),
        );
        expect(info.failedStageNumber).toBe(2);
        expect(info.failedStageName).toBe("extract-text");
        expect(info.failedStageDisplay).toBe("Extract text");
    });

    it("falls back to the STAGES index of current_stage when no failed stage row exists", () => {
        // The stage list grew from five entries to seven: "fetch-law" went in
        // as the second row, between fetch-bills and extract-text, which pushed
        // parse-sections from third place to fourth (counting from 1).
        const info = failedStageInfo(run({ current_stage: "parse-sections" }));
        expect(info.failedStageNumber).toBe(4);
        expect(info.failedStageName).toBe("parse-sections");
    });

    it("returns a null stage number when current_stage is not a known stage", () => {
        const info = failedStageInfo(run({ current_stage: "bogus" }));
        expect(info.failedStageNumber).toBeNull();
        expect(info.failedStageName).toBe("bogus");
    });

    it("truncates parent_run_id to the last 8 chars", () => {
        expect(failedStageInfo(run({ parent_run_id: "abcdef1234567890" })).parentShortId).toBe("34567890");
    });
});
