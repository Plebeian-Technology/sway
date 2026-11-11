import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPost = vi.fn<(...args: unknown[]) => void>();
const mockReload = vi.fn<(...args: unknown[]) => void>();
const mockGet = vi.fn<(...args: unknown[]) => void>();
let mockPageProps: { summary_revisions?: unknown } = {};

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => mockPost(...args),
        reload: (...args: unknown[]) => mockReload(...args),
        get: (...args: unknown[]) => mockGet(...args),
    },
    usePage: () => ({ props: mockPageProps }),
}));

import BillSummaryRevisionHistory from "app/frontend/components/admin/creator/llm-summary/BillSummaryRevisionHistory";
import { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";

describe("BillSummaryRevisionHistory", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockPageProps = {};
    });

    it("renders the toggle button and does not fetch until opened", () => {
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
        expect(screen.queryByTestId("revision-history-content")).not.toBeInTheDocument();
        expect(mockReload).not.toHaveBeenCalled();

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        expect(screen.getByTestId("revision-history-content")).toBeInTheDocument();
        expect(mockReload).toHaveBeenCalledWith({
            only: ["summary_revisions"],
            onFinish: expect.any(Function),
        });
    });

    it("displays empty state when revisions list is empty", () => {
        mockPageProps = { summary_revisions: [] };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        expect(screen.getByTestId("revisions-empty")).toBeInTheDocument();
        expect(screen.getByText("No previous summary revisions recorded for this bill.")).toBeInTheDocument();
    });

    it("renders revisions with truthful provenance, role, review state, and distinguishes unknown provenance", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 101,
                bill_id: 42,
                summary_markdown: "Current published summary",
                origin: "operator_edit",
                actor_name: "Jane Doe",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T01:00:00Z",
            },
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "First model draft",
                origin: "model_generation",
                actor_name: null,
                llm_provider: "claude",
                llm_model: "claude-3-5-sonnet",
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: null,
                created_at: "2026-09-14T00:30:00Z",
            },
            {
                id: 99,
                bill_id: 42,
                summary_markdown: "Old baseline text",
                origin: "initial_baseline",
                actor_name: null,
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "unknown",
                restored_from_id: null,
                created_at: "2026-09-14T00:00:00Z",
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        expect(screen.getByTestId("revision-row-101")).toBeInTheDocument();
        expect(screen.getByTestId("revision-row-100")).toBeInTheDocument();
        expect(screen.getByTestId("revision-row-99")).toBeInTheDocument();

        // 101: Current summary badge
        expect(screen.getByTestId("current-summary-badge")).toBeInTheDocument();
        expect(screen.getByTestId("revision-provenance-101")).toHaveTextContent("By Jane Doe");
        expect(screen.getByTestId("revision-origin-101")).toHaveTextContent("Operator edit");
        expect(screen.getByTestId("revision-role-101")).toHaveTextContent("published");
        expect(screen.getByTestId("revision-review-101")).toHaveTextContent("reviewed");

        // 100: Known model provenance
        expect(screen.getByTestId("revision-provenance-100")).toHaveTextContent("Model: claude / claude-3-5-sonnet");
        expect(screen.getByTestId("revision-origin-100")).toHaveTextContent("Model generation");
        expect(screen.getByTestId("revision-role-100")).toHaveTextContent("draft");
        expect(screen.getByTestId("revision-review-100")).toHaveTextContent("unreviewed");

        // 99: Unknown provenance clearly distinguished
        expect(screen.getByTestId("revision-unknown-provenance")).toHaveTextContent("Unknown provenance");
        expect(screen.getByTestId("revision-unknown-provenance").className).toContain("text-warning");
        expect(screen.getByTestId("revision-unknown-provenance").className).not.toContain("text-warning-foreground");
        expect(screen.getByTestId("revision-origin-99")).toHaveTextContent("Initial baseline");
        expect(screen.getByTestId("revision-review-99")).toHaveTextContent("unknown");
    });

    it("inspects historical Markdown in the preview pane without altering current summary", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 101,
                bill_id: 42,
                summary_markdown: "Current published summary",
                origin: "operator_edit",
                actor_name: "Jane Doe",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T01:00:00Z",
            },
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "Historical text from previous draft",
                origin: "model_generation",
                actor_name: null,
                llm_provider: "claude",
                llm_model: "claude-3-5-sonnet",
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: null,
                created_at: "2026-09-14T00:30:00Z",
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        // Default preview pane shows current published summary
        expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("Current published summary");

        // Inspect revision 100
        fireEvent.click(screen.getByTestId("btn-inspect-revision-100"));
        expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("Historical text from previous draft");

        // Inspect toggle hides preview and reverts to current summary view
        fireEvent.click(screen.getByTestId("btn-inspect-revision-100"));
        expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("Current published summary");
    });

    it("disables restore on current version, and opens confirm dialog for previous version", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 101,
                bill_id: 42,
                summary_markdown: "Current published summary",
                origin: "operator_edit",
                actor_name: "Jane Doe",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T01:00:00Z",
            },
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "Historical text to restore",
                origin: "model_generation",
                actor_name: null,
                llm_provider: "claude",
                llm_model: "claude-3-5-sonnet",
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T00:30:00Z",
                news_source_snapshot_id: 1,
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        // Current revision has disabled restore button
        expect(screen.getByTestId("btn-restore-revision-101")).toBeDisabled();

        // Past revision has enabled restore button
        const restoreBtn = screen.getByTestId("btn-restore-revision-100");
        expect(restoreBtn).not.toBeDisabled();

        fireEvent.click(restoreBtn);

        // Confirm dialog opens
        expect(screen.getByTestId("restore-confirm-dialog")).toBeInTheDocument();
        expect(screen.getByText("Restore summary revision?")).toBeInTheDocument();

        // Cancel closes dialog without request
        fireEvent.click(screen.getByTestId("btn-restore-cancel"));
        expect(screen.queryByTestId("restore-confirm-dialog")).not.toBeInTheDocument();
        expect(mockPost).not.toHaveBeenCalled();

        // Re-open and confirm restore
        fireEvent.click(restoreBtn);
        fireEvent.click(screen.getByTestId("btn-restore-confirm"));

        expect(mockPost).toHaveBeenCalledWith(
            "/bills/42/restore_summary_revision",
            {
                revision_id: 100,
                expected_summary: "Current published summary",
            },
            {
                preserveScroll: true,
                onFinish: expect.any(Function),
            },
        );
    });

    it("distinguishes legacy snapshotless revisions and restores them as review drafts", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 101,
                bill_id: 42,
                summary_markdown: "Current published summary",
                origin: "operator_edit",
                actor_name: "Jane Doe",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T01:00:00Z",
                news_source_snapshot_id: 55,
            },
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "Legacy baseline without snapshot",
                origin: "initial_baseline",
                actor_name: null,
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "unknown",
                restored_from_id: null,
                created_at: "2026-09-14T00:30:00Z",
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        expect(screen.getByTestId("revision-snapshot-badge-101")).toHaveTextContent("Evidence snapshot");
        expect(screen.getByTestId("revision-snapshot-badge-100")).toHaveTextContent("Legacy (no snapshot)");

        fireEvent.click(screen.getByTestId("btn-restore-revision-100"));

        expect(screen.getByTestId("restore-confirm-dialog")).toBeInTheDocument();
        expect(screen.getByText("Restore legacy revision as review draft?")).toBeInTheDocument();
        expect(screen.getByText(/This historical revision has no evidence snapshot/i)).toBeInTheDocument();
        expect(screen.getByTestId("btn-restore-confirm")).toHaveTextContent("Restore as review draft");
    });

    it("offers explicit 'Review draft in editor' action for draft revisions instead of restore", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 101,
                bill_id: 42,
                summary_markdown: "Current published summary",
                origin: "operator_edit",
                actor_name: "Jane Doe",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                created_at: "2026-09-14T01:00:00Z",
            },
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "Restored unreviewed draft text",
                origin: "restoration",
                actor_name: null,
                llm_provider: null,
                llm_model: null,
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: 90,
                created_at: "2026-09-14T00:30:00Z",
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        const onSelectDraft = vi.fn<(draft: IBillSummaryRevision) => void>();
        render(
            <BillSummaryRevisionHistory
                billId={42}
                currentSummary="Current published summary"
                onSelectDraft={onSelectDraft}
            />,
        );

        fireEvent.click(screen.getByTestId("toggle-revision-history"));

        expect(screen.queryByTestId("btn-restore-revision-100")).not.toBeInTheDocument();
        const reviewBtn = screen.getByTestId("btn-review-draft-100");
        expect(reviewBtn).toBeInTheDocument();
        expect(reviewBtn).toHaveTextContent("Review draft in editor");

        fireEvent.click(reviewBtn);
        expect(onSelectDraft).toHaveBeenCalledWith(revisions[1]);

        fireEvent.click(screen.getByTestId("btn-inspect-revision-100"));
        expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("Restored unreviewed draft text");
        const previewReviewBtn = screen.getByTestId("btn-review-selected-draft");
        expect(previewReviewBtn).toBeInTheDocument();
        expect(previewReviewBtn).toHaveTextContent("Review draft in editor");

        fireEvent.click(previewReviewBtn);
        expect(onSelectDraft).toHaveBeenCalledTimes(2);
    });

    it("navigates via router.get when onSelectDraft is omitted and Review draft is clicked", () => {
        const revisions: IBillSummaryRevision[] = [
            {
                id: 100,
                bill_id: 42,
                summary_markdown: "Restored draft text",
                origin: "restoration",
                actor_name: null,
                llm_provider: null,
                llm_model: null,
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: 90,
                created_at: "2026-09-14T00:30:00Z",
            },
        ];

        mockPageProps = { summary_revisions: revisions };
        render(<BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />);

        fireEvent.click(screen.getByTestId("toggle-revision-history"));
        fireEvent.click(screen.getByTestId("btn-review-draft-100"));

        expect(mockGet).toHaveBeenCalledWith(
            "/admin/bill_creator/42/summary",
            { draft_revision_id: 100 },
            { preserveScroll: true },
        );
    });

    it("automatically refetches revisions when panel is open and summary_revisions resets to undefined on redirect", () => {
        mockPageProps = {
            summary_revisions: [
                {
                    id: 101,
                    bill_id: 42,
                    summary_markdown: "Current published summary",
                    origin: "operator_edit",
                    actor_name: "Jane Doe",
                    llm_provider: null,
                    llm_model: null,
                    publication_role: "published",
                    review_state: "reviewed",
                    restored_from_id: null,
                    created_at: "2026-09-14T01:00:00Z",
                },
            ],
        };
        const { rerender } = render(
            <BillSummaryRevisionHistory billId={42} currentSummary="Current published summary" />,
        );

        fireEvent.click(screen.getByTestId("toggle-revision-history"));
        expect(mockReload).not.toHaveBeenCalled();

        mockPageProps = {};
        rerender(<BillSummaryRevisionHistory billId={42} currentSummary="Updated summary" />);

        expect(mockReload).toHaveBeenCalledWith({
            only: ["summary_revisions"],
            onFinish: expect.any(Function),
        });
    });
});
