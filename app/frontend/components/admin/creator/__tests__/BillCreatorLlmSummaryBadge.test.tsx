// @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]

import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import BillCreatorLlmSummaryBadge from "app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge";

describe("BillCreatorLlmSummaryBadge — reclaimable", () => {
    it("stamps 'Queued…' for a pending row nothing has abandoned", () => {
        render(<BillCreatorLlmSummaryBadge status="pending" reclaimable={false} />);
        expect(screen.getByText("Queued…")).toBeInTheDocument();
    });

    it("stamps 'Generating…' for a generating row nothing has abandoned", () => {
        render(<BillCreatorLlmSummaryBadge status="generating" reclaimable={false} />);
        expect(screen.getByText("Generating…")).toBeInTheDocument();
    });

    it("does not say 'Queued…' for a pending row the server calls reclaimable", () => {
        render(<BillCreatorLlmSummaryBadge status="pending" reclaimable={true} />);
        expect(screen.queryByText("Queued…")).not.toBeInTheDocument();
    });

    it("does not say 'Generating…' for a generating row the server calls reclaimable", () => {
        render(<BillCreatorLlmSummaryBadge status="generating" reclaimable={true} />);
        expect(screen.queryByText("Generating…")).not.toBeInTheDocument();
    });

    it("still says 'Ready' for a completed row, reclaimable or not", () => {
        render(<BillCreatorLlmSummaryBadge status="completed" reclaimable={true} />);
        expect(screen.getByText("Ready")).toBeInTheDocument();
    });
});
