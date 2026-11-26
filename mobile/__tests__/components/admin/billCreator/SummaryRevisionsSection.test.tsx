import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { ApiRequestError } from "../../../../src/api/errors";

const mockApiGet = jest.fn();
const mockApiPost = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
        post: (...args: unknown[]) => mockApiPost(...args),
    },
}));

jest.mock("../../../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import SummaryRevisionsSection from "../../../../src/components/admin/billCreator/SummaryRevisionsSection";

const revision = (overrides: Record<string, unknown> = {}) => ({
    id: 1,
    bill_id: 42,
    summary_markdown: "Older summary",
    origin: "operator_edit",
    actor_name: "Ada Admin",
    llm_provider: null,
    llm_model: null,
    publication_role: "published",
    review_state: "reviewed",
    restored_from_id: null,
    news_source_snapshot_id: 5,
    has_snapshot: true,
    created_at: "2026-11-01T15:30:00Z",
    ...overrides,
});

const CURRENT = revision({ id: 2, summary_markdown: "Current summary", origin: "model_generation" });
const OLDER = revision();
const DRAFT = revision({ id: 3, summary_markdown: "Draft summary", publication_role: "draft", origin: "restoration" });
const LEGACY = revision({
    id: 4,
    summary_markdown: "Legacy summary",
    news_source_snapshot_id: null,
    has_snapshot: false,
    actor_name: null,
    llm_provider: "claude",
    llm_model: "sonnet",
    origin: "model_generation",
});

const tabData = (extra: Record<string, unknown> = {}) => ({
    bill: { id: 42, external_id: "25-0001", title: "A bill", summary: "Current summary" },
    ...extra,
});

const renderSection = (
    props: Partial<React.ComponentProps<typeof SummaryRevisionsSection>> = {},
    revisions: unknown[] = [CURRENT, OLDER, DRAFT, LEGACY],
) => {
    mockApiGet.mockResolvedValue({ summary_revisions: revisions });
    const refresh = jest.fn(async () => {});
    const onReviewDraft = jest.fn();
    render(
        <SummaryRevisionsSection
            billId={42}
            data={tabData()}
            refresh={refresh}
            onReviewDraft={onReviewDraft}
            {...props}
        />,
    );
    return { refresh, onReviewDraft };
};

const openHistory = async () => {
    fireEvent.press(screen.getByTestId("admin-summary-revisions-toggle"));
    await screen.findByTestId("admin-summary-revisions-list");
};

// @lat: [[mobile-bill-creator#Sections#The summary revisions section]]
describe("SummaryRevisionsSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        mockApiPost.mockResolvedValue({ revision: revision({ id: 9, origin: "restoration" }) });
    });

    it("asks to save the bill first when there is none", () => {
        renderSection({ billId: null });

        expect(screen.getByText("Save this bill to see its summary revisions.")).toBeTruthy();
        expect(mockApiGet).not.toHaveBeenCalled();
    });

    it("loads the list when the history opens and not before", async () => {
        renderSection();
        expect(mockApiGet).not.toHaveBeenCalled();

        await openHistory();

        expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/summary?summary_revisions=1");
    });

    it("describes each revision: date, role, review state, snapshot, origin and provenance", async () => {
        renderSection();
        await openHistory();

        expect(screen.getByTestId("admin-summary-revision-role-1")).toHaveTextContent("published");
        expect(screen.getByTestId("admin-summary-revision-review-1")).toHaveTextContent("reviewed");
        expect(screen.getByTestId("admin-summary-revision-snapshot-1")).toHaveTextContent("Evidence snapshot");
        expect(screen.getByTestId("admin-summary-revision-origin-1")).toHaveTextContent("Operator edit");
        expect(screen.getByTestId("admin-summary-revision-provenance-1")).toHaveTextContent("By Ada Admin");
        expect(screen.getByTestId("admin-summary-revision-role-3")).toHaveTextContent("draft");
        expect(screen.getByTestId("admin-summary-revision-origin-3")).toHaveTextContent("Restoration");
        expect(screen.getByTestId("admin-summary-revision-snapshot-4")).toHaveTextContent("Legacy (no snapshot)");
        expect(screen.getByTestId("admin-summary-revision-provenance-4")).toHaveTextContent("Model: claude / sonnet");
    });

    it("names an unknown provenance", async () => {
        renderSection({}, [revision({ actor_name: null })]);
        await openHistory();

        expect(screen.getByTestId("admin-summary-revision-unknown-provenance")).toHaveTextContent("Unknown provenance");
    });

    it("marks the revision whose text is the published summary as current and blocks its restore", async () => {
        renderSection();
        await openHistory();

        expect(screen.getByTestId("admin-summary-revision-current-2")).toHaveTextContent("Current");
        expect(screen.queryByTestId("admin-summary-revision-current-1")).toBeNull();
        expect(screen.getByTestId("admin-summary-revision-restore-2")).toBeDisabled();
        expect(screen.getByTestId("admin-summary-revision-restore-1")).not.toBeDisabled();
    });

    it("says so when no revision is recorded", async () => {
        mockApiGet.mockResolvedValue({ summary_revisions: [] });
        render(<SummaryRevisionsSection billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);
        fireEvent.press(screen.getByTestId("admin-summary-revisions-toggle"));

        expect(await screen.findByText("No previous summary revisions recorded for this bill.")).toBeTruthy();
    });

    it("shows a failed load and reloads on Refresh history", async () => {
        mockApiGet.mockRejectedValueOnce(new Error("offline"));
        render(<SummaryRevisionsSection billId={42} data={tabData()} refresh={jest.fn(async () => {})} />);
        fireEvent.press(screen.getByTestId("admin-summary-revisions-toggle"));

        expect(await screen.findByTestId("admin-summary-revisions-error")).toBeTruthy();

        mockApiGet.mockResolvedValue({ summary_revisions: [OLDER] });
        fireEvent.press(screen.getByTestId("admin-summary-revisions-refresh"));

        expect(await screen.findByTestId("admin-summary-revisions-list")).toBeTruthy();
        expect(screen.queryByTestId("admin-summary-revisions-error")).toBeNull();
    });

    it("previews the published summary until a revision is inspected, then the revision text", async () => {
        renderSection();
        await openHistory();

        expect(screen.getByTestId("admin-summary-revisions-preview-title")).toHaveTextContent(
            "Current published summary",
        );
        expect(screen.getByTestId("admin-summary-revisions-preview-text")).toHaveTextContent("Current summary");

        fireEvent.press(screen.getByTestId("admin-summary-revision-inspect-1"));

        expect(screen.getByTestId("admin-summary-revisions-preview-title")).toHaveTextContent(/^Historical preview:/);
        expect(screen.getByTestId("admin-summary-revisions-preview-text")).toHaveTextContent("Older summary");
        expect(screen.getByTestId("admin-summary-revision-inspect-1")).toHaveTextContent("Hide preview");

        fireEvent.press(screen.getByTestId("admin-summary-revision-inspect-1"));

        expect(screen.getByTestId("admin-summary-revisions-preview-text")).toHaveTextContent("Current summary");
    });

    it("posts the chosen revision and the summary it was listed against only after confirmation", async () => {
        const { refresh, onReviewDraft } = renderSection();
        await openHistory();

        fireEvent.press(screen.getByTestId("admin-summary-revision-restore-1"));

        expect(mockApiPost).not.toHaveBeenCalled();
        expect(screen.getByTestId("admin-summary-restore-confirm-title")).toHaveTextContent(
            "Restore summary revision?",
        );

        fireEvent.press(screen.getByTestId("admin-summary-restore-confirm-submit"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith("/bills/42/restore_summary_revision", {
                revision_id: 1,
                expected_summary: "Current summary",
            }),
        );
        await waitFor(() => expect(refresh).toHaveBeenCalled());
        expect(screen.queryByTestId("admin-summary-restore-confirm")).toBeNull();
        expect(screen.getByTestId("admin-summary-revisions-notice")).toHaveTextContent("Bill summary restored.");
        expect(onReviewDraft).not.toHaveBeenCalled();
    });

    it("restores the selected revision from the preview pane", async () => {
        renderSection();
        await openHistory();
        fireEvent.press(screen.getByTestId("admin-summary-revision-inspect-1"));

        fireEvent.press(screen.getByTestId("admin-summary-revisions-restore-selected"));
        fireEvent.press(screen.getByTestId("admin-summary-restore-confirm-submit"));

        await waitFor(() =>
            expect(mockApiPost).toHaveBeenCalledWith(
                "/bills/42/restore_summary_revision",
                expect.objectContaining({ revision_id: 1 }),
            ),
        );
    });

    it("posts nothing when the confirmation is cancelled", async () => {
        renderSection();
        await openHistory();

        fireEvent.press(screen.getByTestId("admin-summary-revision-restore-1"));
        fireEvent.press(screen.getByTestId("admin-summary-restore-confirm-cancel"));

        expect(screen.queryByTestId("admin-summary-restore-confirm")).toBeNull();
        expect(mockApiPost).not.toHaveBeenCalled();
    });

    it("warns that a revision without a snapshot becomes a review draft", async () => {
        renderSection();
        await openHistory();

        fireEvent.press(screen.getByTestId("admin-summary-revision-restore-4"));

        expect(screen.getByTestId("admin-summary-restore-confirm-title")).toHaveTextContent(
            "Restore legacy revision as review draft?",
        );
        expect(screen.getByTestId("admin-summary-restore-confirm-submit")).toHaveTextContent("Restore as review draft");
        expect(screen.getByTestId("admin-summary-restore-confirm-details")).toHaveTextContent(
            /Provenance: Model: claude \/ sonnet/,
        );
    });

    it("opens the draft the server made when a legacy revision is restored as a draft", async () => {
        mockApiPost.mockResolvedValue({ revision: revision({ id: 11, publication_role: "draft" }) });
        const { onReviewDraft } = renderSection();
        await openHistory();

        fireEvent.press(screen.getByTestId("admin-summary-revision-restore-4"));
        fireEvent.press(screen.getByTestId("admin-summary-restore-confirm-submit"));

        await waitFor(() => expect(onReviewDraft).toHaveBeenCalledWith(11));
        expect(screen.getByTestId("admin-summary-revisions-notice")).toHaveTextContent(
            "Legacy revision restored as draft. Please review and declare news usage before publishing.",
        );
    });

    it("keeps the confirmation open with the server's message when the restore is refused", async () => {
        mockApiPost.mockRejectedValue(
            new ApiRequestError(
                "validation_failed",
                "The bill summary was modified by another operator. Please review before restoring.",
                undefined,
                422,
            ),
        );
        const { refresh } = renderSection();
        await openHistory();

        fireEvent.press(screen.getByTestId("admin-summary-revision-restore-1"));
        fireEvent.press(screen.getByTestId("admin-summary-restore-confirm-submit"));

        expect(await screen.findByTestId("admin-summary-restore-confirm-error")).toHaveTextContent(
            "The bill summary was modified by another operator. Please review before restoring.",
        );
        expect(screen.getByTestId("admin-summary-restore-confirm")).toBeTruthy();
        expect(refresh).not.toHaveBeenCalled();
    });

    it("opens a draft row for review instead of restoring it", async () => {
        const { onReviewDraft } = renderSection();
        await openHistory();

        expect(screen.queryByTestId("admin-summary-revision-restore-3")).toBeNull();
        fireEvent.press(screen.getByTestId("admin-summary-revision-review-draft-3"));

        expect(onReviewDraft).toHaveBeenCalledWith(3);
    });

    it("opens the selected draft for review from the preview pane", async () => {
        const { onReviewDraft } = renderSection();
        await openHistory();
        fireEvent.press(screen.getByTestId("admin-summary-revision-inspect-3"));

        fireEvent.press(screen.getByTestId("admin-summary-revisions-review-selected-draft"));

        expect(onReviewDraft).toHaveBeenCalledWith(3);
    });

    it("shows the draft the address names, and closing it clears the address", () => {
        const { onReviewDraft } = renderSection({ data: tabData({ review_draft_revision: DRAFT }) });

        expect(screen.getByTestId("admin-summary-revisions-draft-title")).toHaveTextContent(
            "Historical draft loaded for review (#3)",
        );
        expect(screen.getByTestId("admin-summary-revisions-draft-text")).toHaveTextContent("Draft summary");

        fireEvent.press(screen.getByTestId("admin-summary-revisions-draft-close"));

        expect(onReviewDraft).toHaveBeenCalledWith(null);
    });
});
