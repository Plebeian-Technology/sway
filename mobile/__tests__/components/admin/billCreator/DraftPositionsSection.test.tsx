import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiPost = jest.fn();
const mockApiPatch = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        post: (...args: unknown[]) => mockApiPost(...args),
        patch: (...args: unknown[]) => mockApiPatch(...args),
        delete: jest.fn(),
        get: jest.fn(),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

jest.mock("expo-document-picker", () => ({ getDocumentAsync: jest.fn() }));

import DraftPositionsSection from "../../../../src/components/admin/billCreator/DraftPositionsSection";
import PositionsTab from "../../../../src/screens/admin/billCreator/tabs/PositionsTab";

const draftB = { org_name: "Org B", stance: "support", summary: "Supports the bill.", draft_token: "tok-b" };
const draftC = { org_name: "Org C", stance: "oppose", summary: "Opposes the bill.", draft_token: "tok-c" };

const tabData = (
    provisioningOverrides: Record<string, unknown> = {},
    overrides: Record<string, unknown> = {},
    billOverrides: Record<string, unknown> = {},
) => ({
    bill: {
        id: 42,
        external_id: "25-0001",
        title: "A bill",
        organizations: [],
        bill_llm_provisioning: {
            generation_status: "completed",
            has_testimony: true,
            reclaimable: false,
            draft_org_positions: [draftB, draftC],
            ...provisioningOverrides,
        },
        bill_pipeline_refresh: null,
        ...billOverrides,
    },
    organizations: [],
    tab_key: "positions",
    active_legislation_pipeline_run: null,
    testimony_coverage: null,
    ...overrides,
});

const renderSection = (data: ReturnType<typeof tabData>) => {
    const refresh = jest.fn(async () => {});
    const view = render(<DraftPositionsSection billId={42} data={data} refresh={refresh} />);
    return { refresh, rerender: view.rerender };
};

// @lat: [[mobile-bill-creator#Sections#The draft positions section]]
describe("DraftPositionsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({});
        mockApiPatch.mockResolvedValue({});
    });

    it("renders above the organizations section on the Positions tab", () => {
        render(<PositionsTab billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.getByTestId("admin-draft-positions")).toBeTruthy();
        expect(screen.getByTestId("admin-organizations")).toBeTruthy();
        expect(screen.getByText("Supporting / opposing arguments")).toBeTruthy();
    });

    it("rebuilds the organizations section when an approval adds an organization to the bill", () => {
        const refresh = jest.fn(async () => {});
        const view = render(<PositionsTab billId={42} data={tabData()} refresh={refresh} />);
        expect(screen.queryByTestId("admin-organizations-row-0")).toBeNull();

        const approved = {
            id: 9,
            name: "Org B",
            icon_url: null,
            positions: [{ id: 90, bill_id: 42, support: "FOR", summary: "Supports the bill." }],
        };
        view.rerender(
            <PositionsTab billId={42} data={tabData({}, {}, { organizations: [approved] })} refresh={refresh} />,
        );

        expect(screen.getByTestId("admin-organizations-row-0")).toHaveTextContent(/Org B/);
    });

    it("asks for a saved bill when the bill is new", () => {
        render(<PositionsTab billId={null} data={tabData()} refresh={jest.fn(async () => {})} />);

        expect(screen.queryByTestId("admin-draft-positions")).toBeNull();
        expect(screen.getByTestId("admin-bill-creator-positions-no-bill")).toBeTruthy();
    });

    it("lists each draft that is not rejected with its name, stance and summary", () => {
        renderSection(tabData({ draft_org_positions: [{ ...draftB, rejected: true }, draftC] }));

        expect(screen.queryByTestId("admin-draft-position-0")).toBeNull();
        expect(screen.getByTestId("admin-draft-position-1-name")).toHaveTextContent("Org C");
        expect(screen.getByTestId("admin-draft-position-1-stance")).toHaveTextContent("Oppose");
        expect(screen.getByTestId("admin-draft-position-1-summary")).toHaveTextContent("Opposes the bill.");
    });

    it("labels a neutral draft Neutral and an unknown stance by its stored word", () => {
        renderSection(
            tabData({
                draft_org_positions: [
                    { ...draftB, stance: "neutral" },
                    { ...draftC, stance: "undecided" },
                ],
            }),
        );

        expect(screen.getByTestId("admin-draft-position-0-stance")).toHaveTextContent("Neutral");
        expect(screen.getByTestId("admin-draft-position-1-stance")).toHaveTextContent("undecided");
    });

    it("says no drafts were generated when testimony exists and the list is empty", () => {
        renderSection(tabData({ draft_org_positions: [] }));

        expect(screen.getByTestId("admin-draft-positions-empty")).toHaveTextContent("No draft positions generated.");
    });

    it("approves a draft with its original identity and reloads the tab", async () => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-1-approve"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/approve_org_position", {
                org_name: "Org C",
                support: "oppose",
                summary: "Opposes the bill.",
                index: 1,
                draft_org_name: "Org C",
                draft_token: "tok-c",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("applies edits on the card and sends them with the approval", async () => {
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-edit"));
        fireEvent.changeText(screen.getByTestId("admin-draft-position-0-edit-name"), "Org B Renamed");
        fireEvent.press(screen.getByTestId("admin-draft-position-0-edit-stance-neutral"));
        fireEvent.changeText(screen.getByTestId("admin-draft-position-0-edit-summary"), "Takes no side.");
        fireEvent.press(screen.getByTestId("admin-draft-position-0-apply"));

        expect(mockApiPatch).not.toHaveBeenCalled();
        expect(screen.getByTestId("admin-draft-position-0-name")).toHaveTextContent("Org B Renamed");
        expect(screen.getByTestId("admin-draft-position-0-stance")).toHaveTextContent("Neutral");

        fireEvent.press(screen.getByTestId("admin-draft-position-0-approve"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/approve_org_position", {
                org_name: "Org B Renamed",
                support: "neutral",
                summary: "Takes no side.",
                index: 0,
                draft_org_name: "Org B",
                draft_token: "tok-b",
            }),
        );
    });

    it("discards edits on Cancel edit", () => {
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-edit"));
        fireEvent.changeText(screen.getByTestId("admin-draft-position-0-edit-name"), "Something else");
        fireEvent.press(screen.getByTestId("admin-draft-position-0-cancel"));

        expect(screen.getByTestId("admin-draft-position-0-name")).toHaveTextContent("Org B");
    });

    it("rejects a draft with its original identity and reloads the tab", async () => {
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-1-reject"));

        await waitFor(() =>
            expect(mockApiPatch).toHaveBeenCalledWith("/bill_draft_org_positions/42-1", {
                rejected: true,
                draft_org_name: "Org C",
                draft_token: "tok-c",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("shows the server's reason on the card when an approval is refused", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { org_position: "This draft list has changed." },
                422,
            ),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-approve"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-draft-position-0-error")).toHaveTextContent(
                "This draft list has changed.",
            ),
        );
        expect(refresh).not.toHaveBeenCalled();
    });

    it("shows the server's message on the card when a reject is refused", async () => {
        mockApiPatch.mockRejectedValue(
            new ApiRequestError("identity_required", "Send draft_token (preferred)", undefined, 422),
        );
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-reject"));

        await waitFor(() =>
            expect(screen.getByTestId("admin-draft-position-0-error")).toHaveTextContent(
                "Send draft_token (preferred)",
            ),
        );
    });

    it("offers to approve a private individual anyway and resends with the override", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { org_position: "Reads Org B as a person.", private_individual_refusal: true },
                422,
            ),
        );
        const { refresh } = renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-approve"));

        await waitFor(() => expect(screen.getByTestId("admin-draft-position-0-override")).toBeTruthy());
        expect(screen.getByTestId("admin-draft-position-0-override")).toHaveTextContent(
            /^Approve anyway\?Reads Org B as a person\. Approving publishes this name as a followable organization\./,
        );
        fireEvent.press(screen.getByTestId("admin-draft-position-0-override-confirm"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenLastCalledWith(
                "/bills/42/approve_org_position",
                expect.objectContaining({ org_name: "Org B", override_private_individual: true }),
            ),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalledTimes(1));
    });

    it("shows the refusal when the operator cancels the private-individual override", async () => {
        mockApiPost.mockRejectedValueOnce(
            new ApiRequestError(
                "validation_failed",
                "Validation failed.",
                { org_position: "Reads Org B as a person.", private_individual_refusal: true },
                422,
            ),
        );
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-approve"));
        await waitFor(() => expect(screen.getByTestId("admin-draft-position-0-override")).toBeTruthy());
        fireEvent.press(screen.getByTestId("admin-draft-position-0-override-cancel"));

        expect(screen.queryByTestId("admin-draft-position-0-override")).toBeNull();
        expect(screen.getByTestId("admin-draft-position-0-error")).toHaveTextContent("Reads Org B as a person.");
        expect(mockApiPost).toHaveBeenCalledTimes(1);
    });

    it("shows a refusal that survives the override instead of asking again", async () => {
        const refusal = new ApiRequestError(
            "validation_failed",
            "Validation failed.",
            { org_position: "Reads Org B as a person.", private_individual_refusal: true },
            422,
        );
        mockApiPost.mockRejectedValue(refusal);
        renderSection(tabData());

        fireEvent.press(screen.getByTestId("admin-draft-position-0-approve"));
        await waitFor(() => expect(screen.getByTestId("admin-draft-position-0-override")).toBeTruthy());
        fireEvent.press(screen.getByTestId("admin-draft-position-0-override-confirm"));

        await waitFor(() => expect(mockApiPost).toHaveBeenCalledTimes(2));
        await waitFor(() =>
            expect(screen.getByTestId("admin-draft-position-0-error")).toHaveTextContent("Reads Org B as a person."),
        );
        expect(screen.queryByTestId("admin-draft-position-0-override")).toBeNull();
    });

    it("keeps Approve off for a draft whose evidence was retracted, and says why", () => {
        renderSection(tabData({ draft_org_positions: [{ ...draftB, evidence_retracted_at: "2026-11-01T00:00:00Z" }] }));

        expect(screen.getByTestId("admin-draft-position-0-approve")).toBeDisabled();
        expect(screen.getByTestId("admin-draft-position-0-reject")).not.toBeDisabled();
        expect(screen.getByTestId("admin-draft-position-0-edit")).not.toBeDisabled();
        expect(screen.getByTestId("admin-draft-position-0-retracted")).toHaveTextContent(
            "The testimony this draft was drawn from is no longer on this bill, so it cannot be approved. " +
                "Regenerate the positions once testimony is available, or reject this draft.",
        );
    });

    it("keeps Approve off without testimony, unless the draft was drawn from the news", () => {
        renderSection(
            tabData({
                has_testimony: false,
                draft_org_positions: [draftB, { ...draftC, bill_news_article_id: 5, evidence_excerpt: "We oppose." }],
            }),
        );

        expect(screen.getByTestId("admin-draft-position-0-approve")).toBeDisabled();
        expect(screen.getByTestId("admin-draft-position-1-approve")).not.toBeDisabled();
        expect(screen.getByTestId("admin-draft-positions-no-testimony")).toHaveTextContent(
            /drawn from testimony that is no longer on file/,
        );
    });

    it("names the retracted drafts when every draft's evidence is gone and there is no testimony", () => {
        renderSection(
            tabData({
                has_testimony: false,
                draft_org_positions: [{ ...draftB, evidence_retracted_at: "2026-11-01T00:00:00Z" }],
            }),
        );

        expect(screen.getByTestId("admin-draft-positions-no-testimony")).toHaveTextContent(
            /drawn from testimony that has been withdrawn/,
        );
    });

    it("says positions are not generated without testimony when there are no drafts", () => {
        renderSection(tabData({ has_testimony: false, draft_org_positions: [] }));

        expect(screen.getByTestId("admin-draft-positions-no-testimony")).toHaveTextContent(
            /positions are not generated without testimony/,
        );
        expect(screen.queryByTestId("admin-draft-positions-empty")).toBeNull();
    });

    it("keeps Approve off while testimony left out of the run is unacknowledged", () => {
        renderSection(tabData({}, { testimony_coverage: { coverage_gap: true, acknowledged: false } }));

        expect(screen.getByTestId("admin-draft-position-0-approve")).toBeDisabled();
    });

    it("keeps Approve off and says why while a summary run is in flight", () => {
        renderSection(tabData({ generation_status: "generating" }));

        expect(screen.getByTestId("admin-draft-position-0-approve")).toBeDisabled();
        expect(screen.getByTestId("admin-draft-positions-run-in-flight")).toHaveTextContent(
            /A new set of draft positions is on the way/,
        );
        expect(screen.getByTestId("admin-draft-positions-run-in-flight")).toHaveTextContent(
            /You are looking at 2 draft positions already on this bill\./,
        );
    });

    it("keeps Approve off while a clean-testimony run covers this bill", () => {
        renderSection(tabData({}, { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 42 } }));

        expect(screen.getByTestId("admin-draft-position-0-approve")).toBeDisabled();
        expect(screen.getByTestId("admin-draft-positions-run-in-flight")).toHaveTextContent(
            /The testimony behind these positions is being rewritten/,
        );
    });

    it("leaves Approve on while a clean-testimony run covers another bill", () => {
        renderSection(tabData({}, { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 7 } }));

        expect(screen.getByTestId("admin-draft-position-0-approve")).not.toBeDisabled();
        expect(screen.queryByTestId("admin-draft-positions-run-in-flight")).toBeNull();
    });

    it("shows a news-sourced draft's excerpt, speaker, source and locator", () => {
        renderSection(
            tabData({
                draft_org_positions: [
                    {
                        ...draftB,
                        bill_news_article_id: 5,
                        evidence_excerpt: "We back this bill.",
                        speaker_name: "Pat Doe",
                        speaker_role: "Director",
                        source_url: "https://www.baltimoresun.com/story",
                        outlet_name: "The Sun",
                        excerpt_page: 2,
                        excerpt_paragraph: 4,
                        excerpt_offset: null,
                    },
                ],
            }),
        );

        expect(screen.getByTestId("admin-draft-position-0-excerpt")).toHaveTextContent(/“We back this bill\.”/);
        expect(screen.getByTestId("admin-draft-position-0-excerpt")).toHaveTextContent(/— Pat Doe, Director/);
        expect(screen.getByTestId("admin-draft-position-0-source")).toHaveTextContent("The Sun");
        expect(screen.getByTestId("admin-draft-position-0-excerpt")).toHaveTextContent(/p\. 2, para\. 4/);
    });

    it("refreshes the tab every five seconds while a summary run is in flight", () => {
        jest.useFakeTimers();
        const { refresh } = renderSection(tabData({ generation_status: "pending" }));

        jest.advanceTimersByTime(5000);

        expect(refresh).toHaveBeenCalledTimes(1);
        jest.useRealTimers();
    });

    it("does not poll when nothing is running", () => {
        jest.useFakeTimers();
        const { refresh } = renderSection(tabData());

        jest.advanceTimersByTime(10000);

        expect(refresh).not.toHaveBeenCalled();
        jest.useRealTimers();
    });
});
