import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: jest.fn(),
        delete: jest.fn(),
        get: (...args: unknown[]) => mockApiGet(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import TestimonyCoverageSection from "../../../../src/components/admin/billCreator/TestimonyCoverageSection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const coverage = (overrides: Record<string, unknown> = {}) => ({
    state: "cleaned",
    coverage_gap: true,
    total_chars: 5000,
    reached_chars: 1000,
    left_out_chars: 4000,
    total_letters: 12,
    left_out_letters: 3,
    digest: "digest-abc",
    acknowledged: false,
    acknowledged_by_email: null,
    acknowledged_at: null,
    ...overrides,
});

const tabData = (testimonyCoverage: unknown = coverage(), overrides: Record<string, unknown> = {}) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        organizations: [],
        bill_llm_provisioning: {
            generation_status: "completed",
            has_testimony: true,
            reclaimable: false,
            draft_org_positions: [],
        },
        bill_pipeline_refresh: null,
    },
    organizations: [],
    tab_key: "positions",
    active_legislation_pipeline_run: null,
    testimony_coverage: testimonyCoverage,
    ...overrides,
});

const renderSection = (data: Record<string, unknown>) => {
    const refresh = jest.fn(async () => {});
    render(<TestimonyCoverageSection billId={42} data={data} refresh={refresh} />);
    return { refresh };
};

const notice = "admin-testimony-coverage";

// @lat: [[mobile-bill-creator#Sections#The testimony coverage section#The coverage notice]]
describe("TestimonyCoverageSection notice", () => {
    it("renders nothing without a coverage report", () => {
        renderSection(tabData(null));

        expect(screen.queryByTestId(notice)).toBeNull();
    });

    it("renders nothing when the bill has no testimony", () => {
        renderSection(tabData(coverage({ state: "no_testimony", coverage_gap: false })));

        expect(screen.queryByTestId(notice)).toBeNull();
    });

    it.each([
        [
            "a running stage",
            { state: "running" },
            "The clean-testimony stage is running",
            "These numbers come from the last run.",
        ],
        [
            "a stage that never ran",
            { state: "never_run" },
            "This testimony was not cleaned",
            "The clean-testimony stage has not run on this bill. The model read the first 1,000 characters of 5,000.",
        ],
        [
            "a failed stage with earlier letter counts",
            { state: "failed" },
            "The clean-testimony stage failed",
            "The model read the raw testimony instead. 3 of 12 letters did not reach the model.",
        ],
        [
            "a failed stage with no letter counts",
            { state: "failed", total_letters: null, left_out_letters: null },
            "The clean-testimony stage failed",
            "The model read the raw testimony instead. It read the first 1,000 characters of 5,000.",
        ],
        [
            "a stale cleaning",
            { state: "stale" },
            "This testimony needs to be cleaned again",
            "Newer hearing testimony arrived after this bill was last cleaned, so the model read the raw testimony " +
                "instead. It read the first 1,000 characters of 5,000. Re-run the clean-testimony stage.",
        ],
        [
            "a cleaning where every letter reached the model",
            { coverage_gap: false, left_out_letters: 0, left_out_chars: 0 },
            "Testimony coverage",
            "All 12 letters reached the model. Repeated text was removed first.",
        ],
        [
            "a cleaning where every letter reached the model but not in full",
            { left_out_letters: 0 },
            "Some testimony did not reach the model",
            "12 letters reached the model, but not in full. The prompt reached its size limit. Approval is blocked " +
                "until you acknowledge this.",
        ],
        [
            "a cleaning that left letters out",
            {},
            "Some testimony did not reach the model",
            "3 of 12 letters did not reach the model. The prompt reached its size limit. Approval is blocked until " +
                "you acknowledge this.",
        ],
        [
            "a single letter",
            { coverage_gap: false, total_letters: 1, left_out_letters: 0, left_out_chars: 0 },
            "Testimony coverage",
            "All 1 letter reached the model. Repeated text was removed first.",
        ],
    ])("states the web's copy for %s", (_label, overrides, title, body) => {
        renderSection(tabData(coverage(overrides)));

        expect(screen.getByTestId(`${notice}-title`)).toHaveTextContent(title);
        expect(screen.getByTestId(`${notice}-body`)).toHaveTextContent(body);
    });

    it("offers no acknowledgement when nothing was left out", () => {
        renderSection(tabData(coverage({ coverage_gap: false, left_out_letters: 0, left_out_chars: 0 })));

        expect(screen.queryByTestId(`${notice}-acknowledge`)).toBeNull();
        expect(screen.queryByTestId(`${notice}-acknowledged`)).toBeNull();
    });
});

// @lat: [[mobile-bill-creator#Sections#The testimony coverage section#Acknowledging the left-out testimony]]
describe("TestimonyCoverageSection acknowledgement", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        mockApiGet.mockResolvedValue([]);
    });

    it("acknowledging posts the coverage digest and reloads the tab", async () => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${notice}-acknowledge`));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/testimony_coverage_acknowledgement", {
                digest: "digest-abc",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalled());
    });

    it("keeps the button off while a summary run is in flight", () => {
        const data = tabData();
        renderSection({
            ...data,
            bill: {
                ...data.bill,
                bill_llm_provisioning: { ...data.bill.bill_llm_provisioning, generation_status: "generating" },
            },
        });

        expect(screen.getByTestId(`${notice}-acknowledge`)).toBeDisabled();
    });

    it("keeps the button off while a clean-testimony run covers the bill", () => {
        renderSection(
            tabData(coverage(), { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 42 } }),
        );

        expect(screen.getByTestId(`${notice}-acknowledge`)).toBeDisabled();
    });

    it("shows the acknowledged stamp with who acknowledged it and when", () => {
        renderSection(
            tabData(
                coverage({
                    acknowledged: true,
                    acknowledged_by_email: "admin@example.com",
                    acknowledged_at: "2026-11-20T15:30:00Z",
                }),
            ),
        );

        expect(screen.queryByTestId(`${notice}-acknowledge`)).toBeNull();
        expect(screen.getByTestId(`${notice}-acknowledged`)).toHaveTextContent(/^ACKNOWLEDGED/);
        expect(screen.getByTestId(`${notice}-acknowledged-by`)).toHaveTextContent(
            "Acknowledged by admin@example.com on November 20, 2026 at 03:30 PM.",
        );
    });

    it("leaves the date out of the stamp when none was recorded", () => {
        renderSection(tabData(coverage({ acknowledged: true, acknowledged_by_email: "admin@example.com" })));

        expect(screen.getByTestId(`${notice}-acknowledged-by`)).toHaveTextContent("Acknowledged by admin@example.com.");
    });

    it("shows the server's reason when it refuses", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                {
                    testimony_coverage:
                        "The testimony coverage numbers changed since this page loaded — reload and try again.",
                },
                422,
            ),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId(`${notice}-acknowledge`));

        expect(await screen.findByTestId(`${notice}-error`)).toHaveTextContent(
            "The testimony coverage numbers changed since this page loaded — reload and try again.",
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("re-enables Approve on the draft, campaign and claimed-affiliation cards once the tab reloads", async () => {
        const data = {
            ...tabData(),
            bill: {
                ...tabData().bill,
                bill_llm_provisioning: {
                    ...tabData().bill.bill_llm_provisioning,
                    draft_org_positions: [
                        { org_name: "Org B", stance: "support", summary: "Supports.", draft_token: "tok-b" },
                    ],
                },
            },
            testimony_campaign_drafts: [
                {
                    content_hash: "grp1",
                    sender_count: 3,
                    letter_count: 2,
                    added_words_characters: 0,
                    senders_added_words_left_out: 0,
                    domain: "everyactioncustom.com",
                    rejected: false,
                    marked_individual: false,
                },
            ],
            campaigns: [],
            testimony_claimed_affiliations: [
                { position: 3, phrase: "I speak for the Block Association.", role: "Chair", sender: "Pat Doe" },
            ],
        };
        const refresh = jest.fn(async () => {});
        const { rerender } = render(<PositionsTab billId={42} data={data} refresh={refresh} />);
        for (const card of ["admin-campaign-draft-grp1", "admin-claimed-affiliation-3"]) {
            fireEvent.press(screen.getByTestId(`${card}-edit`));
            fireEvent.changeText(screen.getByTestId(`${card}-edit-summary`), "Backs the bill.");
        }
        const approves = ["admin-draft-position-0", "admin-campaign-draft-grp1", "admin-claimed-affiliation-3"].map(
            (card) => `${card}-approve`,
        );
        for (const approve of approves) expect(screen.getByTestId(approve)).toBeDisabled();

        fireEvent.press(screen.getByTestId(`${notice}-acknowledge`));
        await waitFor(() => expect(refresh).toHaveBeenCalled());
        rerender(
            <PositionsTab
                billId={42}
                data={{ ...data, testimony_coverage: coverage({ acknowledged: true }) }}
                refresh={refresh}
            />,
        );

        for (const approve of approves) expect(screen.getByTestId(approve)).toBeEnabled();
    });
});
