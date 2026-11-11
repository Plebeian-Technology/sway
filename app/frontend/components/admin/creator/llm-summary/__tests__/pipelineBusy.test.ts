import { describe, expect, it } from "vitest";

import {
    PHASE_52_NON_TERMINAL_STATUSES,
    TERMINAL_RUN_STATUSES,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { isPipelineBusy } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";

// @lat: [[pipeline-busy-terminal-status-inversion#LlmSummaryPipelineBusyNotice.test.tsx notes]]
describe("isPipelineBusy", () => {
    it.each([...PHASE_52_NON_TERMINAL_STATUSES])("is busy while the run is %s", (status) => {
        expect(isPipelineBusy(status)).toBe(true);
    });

    it.each([...TERMINAL_RUN_STATUSES])("is not busy once the run is %s", (status) => {
        expect(isPipelineBusy(status)).toBe(false);
    });

    it("is not busy when the bill has never been refreshed", () => {
        expect(isPipelineBusy(null)).toBe(false);
    });

    // @lat: [[pipeline-busy-terminal-status-inversion#Listing FINISHED statuses, not busy ones]]
    it("treats an unrecognised status as in flight", () => {
        expect(isPipelineBusy("retrying" as never)).toBe(true);
    });
});
