import { cleanup, render, screen } from "@testing-library/react";
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("app/frontend/components/admin/creator/BillCreatorTestimonyPositions", () => ({
    __esModule: true,
    default: () => <div data-testid="section-BillCreatorTestimonyPositions">BillCreatorTestimonyPositions</div>,
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorOrganizations", () => ({
    __esModule: true,
    default: () => <div data-testid="section-BillCreatorOrganizations">BillCreatorOrganizations</div>,
}));

const usePageMock = vi.fn<() => Record<string, unknown>>();
const usePollMock = vi.fn<(...args: unknown[]) => void>();
const pollDestroySpy = vi.fn<() => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    usePoll: function usePoll(...args: unknown[]) {
        usePollMock(...args);
        React.useEffect(() => () => pollDestroySpy(), []);
    },
    router: { post: vi.fn<() => void>(), patch: vi.fn<() => void>(), reload: vi.fn<() => void>() },
}));
vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: () => ({ connected: true, downgraded: false, lastDisconnectedAt: null }),
}));

import BillCreatorPositions, { POSITIONS_ONLY_PROPS } from "app/frontend/components/admin/creator/BillCreatorPositions";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    usePollMock.mockReset();
    pollDestroySpy.mockReset();
});

describe("BillCreatorPositions", () => {
    it("renders the testimony region above the approved arguments when a bill is selected", () => {
        usePageMock.mockReturnValue({
            props: { bill: { id: 42 }, active_legislation_pipeline_run: null },
        });
        render(<BillCreatorPositions />);

        const sections = Array.from(document.querySelectorAll("[data-testid^='section-']")).map(
            (el) => el.getAttribute("data-testid")!,
        );
        expect(sections).toEqual(["section-BillCreatorTestimonyPositions", "section-BillCreatorOrganizations"]);
        expect(screen.getByRole("heading", { name: "Supporting / opposing arguments", level: 3 })).toBeTruthy();
    });

    it("renders the no-bill-selected empty state when bill.id is falsy", () => {
        usePageMock.mockReturnValue({ props: { bill: undefined, active_legislation_pipeline_run: null } });
        render(<BillCreatorPositions />);

        expect(screen.getByTestId("positions-no-bill-selected")).toBeTruthy();
        expect(screen.queryByTestId("section-BillCreatorTestimonyPositions")).toBeNull();
        expect(screen.queryByTestId("section-BillCreatorOrganizations")).toBeNull();
    });

    it("renders the no-bill-selected empty state when bill.id is 0 or negative", () => {
        usePageMock.mockReturnValue({ props: { bill: { id: 0 }, active_legislation_pipeline_run: null } });
        render(<BillCreatorPositions />);

        expect(screen.getByTestId("positions-no-bill-selected")).toBeTruthy();
    });

    // @lat: [[bill-creator-positions-tab#What the positions tab polls for]]
    it.each(["pending", "generating"])("mounts the poller while generation_status is %s", (status) => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: status } },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorPositions />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(usePollMock).toHaveBeenCalledWith(5000, { only: [...POSITIONS_ONLY_PROPS] });
    });

    it("mounts the poller while this bill's pipeline is busy", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    bill_llm_provisioning: { generation_status: "completed" },
                    bill_pipeline_refresh: { status: "cleaning_testimony" },
                },
                active_legislation_pipeline_run: null,
            },
        });
        render(<BillCreatorPositions />);

        expect(usePollMock).toHaveBeenCalledTimes(1);
    });

    // @lat: [[bill-creator-positions-tab#What the positions tab polls for]]
    it.each(["completed", "failed", "skipped", undefined, null])(
        "does NOT mount the poller when generation_status is %s and nothing is running",
        (status) => {
            usePageMock.mockReturnValue({
                props: {
                    bill: { id: 42, bill_llm_provisioning: { generation_status: status } },
                    active_legislation_pipeline_run: null,
                },
            });
            render(<BillCreatorPositions />);

            expect(usePollMock).not.toHaveBeenCalled();
        },
    );

    it("stops the poller once the run settles", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: "generating" } },
                active_legislation_pipeline_run: null,
            },
        });
        const { rerender } = render(<BillCreatorPositions />);
        expect(usePollMock).toHaveBeenCalledTimes(1);
        expect(pollDestroySpy).not.toHaveBeenCalled();

        usePollMock.mockClear();
        usePageMock.mockReturnValue({
            props: {
                bill: { id: 42, bill_llm_provisioning: { generation_status: "completed" } },
                active_legislation_pipeline_run: null,
            },
        });
        rerender(<BillCreatorPositions />);

        expect(usePollMock).not.toHaveBeenCalled();
        expect(pollDestroySpy).toHaveBeenCalledTimes(1);
    });

    // @lat: [[bill-creator-positions-tab#Splitting the tab split the poll list]]
    it("exports POSITIONS_ONLY_PROPS with the props the tab actually consumes", () => {
        expect([...POSITIONS_ONLY_PROPS]).toEqual([
            "bill",
            "organizations",
            "active_legislation_pipeline_run",
            "testimony_coverage",
            "testimony_campaign_drafts",
            "testimony_claimed_affiliations",
            "campaigns",
            "campaign_organization_candidates",
            "public_testimony_counts",
        ]);
    });

    it("asks for no prop only the summary tab reads", () => {
        expect([...POSITIONS_ONLY_PROPS]).not.toContain("summary_sources");
    });
});
