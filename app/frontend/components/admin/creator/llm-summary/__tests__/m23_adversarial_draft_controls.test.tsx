import { act, fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPost = vi.fn<(...args: unknown[]) => void>();
const mockReload = vi.fn<(...args: unknown[]) => void>();
const mockGet = vi.fn<(...args: unknown[]) => void>();
const mockPatch = vi.fn<(...args: unknown[]) => void>();
const mockNotify = vi.fn<(...args: unknown[]) => string>();

let mockPageProps: {
    summary_revisions?: IBillSummaryRevision[] | null;
    review_draft_revision?: IBillSummaryRevision | null;
    news_articles?: unknown[];
    errors?: Record<string, string>;
    flash?: Record<string, unknown>;
} = {};

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => mockPost(...args),
        reload: (...args: unknown[]) => mockReload(...args),
        get: (...args: unknown[]) => mockGet(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
    },
    usePage: () => ({ props: mockPageProps }),
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => mockNotify(...args),
}));

import BillSummaryRevisionHistory from "app/frontend/components/admin/creator/llm-summary/BillSummaryRevisionHistory";
import LlmSummaryEditableSummary from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary";
import type { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";

const getSummaryTextarea = () => screen.getByTestId("textarea-llm-summary") as HTMLTextAreaElement;

// @lat: [[news-manual-evidence-ui#Historical legacy restoration#Editor review and explicit publication]]
describe("Adversarial Verification — Manual Summary Evidence Review Controls", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        mockPageProps = {};
        window.sessionStorage.clear();
    });

    describe("BillSummaryRevisionHistory — Stress-testing mixed revisions, draft reviews, and modal distinctions", () => {
        const mixedRevisions: IBillSummaryRevision[] = [
            {
                id: 206,
                bill_id: 42,
                summary_markdown: "Draft revision with unknown provenance and no snapshot.",
                origin: "operator_edit",
                actor_name: null,
                llm_provider: null,
                llm_model: null,
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: null,
                has_snapshot: false,
                news_source_snapshot_id: null,
                created_at: "2026-09-24T18:00:00Z",
            },
            {
                id: 205,
                bill_id: 42,
                summary_markdown: "Older published revision with model provenance and snapshot.",
                origin: "model_generation",
                actor_name: null,
                llm_provider: "claude",
                llm_model: "claude-3-5-sonnet",
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                has_snapshot: true,
                news_source_snapshot_id: 70,
                created_at: "2026-09-24T16:00:00Z",
            },
            {
                id: 204,
                bill_id: 42,
                summary_markdown: "Past published revision with no snapshot (legacy paste).",
                origin: "operator_paste",
                actor_name: "Staff Analyst",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                has_snapshot: false,
                news_source_snapshot_id: null,
                created_at: "2026-09-24T14:00:00Z",
            },
            {
                id: 203,
                bill_id: 42,
                summary_markdown: "Current active published summary with evidence snapshot.",
                origin: "operator_edit",
                actor_name: "Chief Editor",
                llm_provider: null,
                llm_model: null,
                publication_role: "published",
                review_state: "reviewed",
                restored_from_id: null,
                has_snapshot: true,
                news_source_snapshot_id: 89,
                created_at: "2026-09-24T12:00:00Z",
            },
            {
                id: 202,
                bill_id: 42,
                summary_markdown: "Draft revision generated from model with snapshot.",
                origin: "model_generation",
                actor_name: null,
                llm_provider: "llama",
                llm_model: "meta-llama-3-70b",
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: null,
                has_snapshot: true,
                news_source_snapshot_id: 88,
                created_at: "2026-09-24T10:00:00Z",
            },
            {
                id: 201,
                bill_id: 42,
                summary_markdown: "Restored legacy draft requiring news usage declaration.",
                origin: "restoration",
                actor_name: "Admin User",
                llm_provider: null,
                llm_model: null,
                publication_role: "draft",
                review_state: "unreviewed",
                restored_from_id: 100,
                has_snapshot: false,
                news_source_snapshot_id: null,
                created_at: "2026-09-24T08:00:00Z",
            },
        ];

        it("renders all revisions with truthful badges, snapshot states, and provenance markers", () => {
            mockPageProps = { summary_revisions: mixedRevisions };

            render(
                <BillSummaryRevisionHistory
                    billId={42}
                    currentSummary="Current active published summary with evidence snapshot."
                />,
            );

            fireEvent.click(screen.getByTestId("toggle-revision-history"));

            expect(screen.getByTestId("revision-row-206")).toBeInTheDocument();
            expect(screen.getByTestId("revision-row-205")).toBeInTheDocument();
            expect(screen.getByTestId("revision-row-204")).toBeInTheDocument();
            expect(screen.getByTestId("revision-row-203")).toBeInTheDocument();
            expect(screen.getByTestId("revision-row-202")).toBeInTheDocument();
            expect(screen.getByTestId("revision-row-201")).toBeInTheDocument();

            expect(screen.getByTestId("revision-role-206")).toHaveTextContent("draft");
            expect(screen.getByTestId("revision-snapshot-badge-206")).toHaveTextContent("Legacy (no snapshot)");
            expect(screen.getByTestId("revision-unknown-provenance")).toHaveTextContent("Unknown provenance");
            expect(screen.getByTestId("btn-review-draft-206")).toBeInTheDocument();

            expect(screen.getByTestId("revision-role-205")).toHaveTextContent("published");
            expect(screen.getByTestId("revision-snapshot-badge-205")).toHaveTextContent("Evidence snapshot");
            expect(screen.getByTestId("revision-provenance-205")).toHaveTextContent(
                "Model: claude / claude-3-5-sonnet",
            );
            expect(screen.getByTestId("btn-restore-revision-205")).toBeInTheDocument();

            expect(screen.getByTestId("revision-role-204")).toHaveTextContent("published");
            expect(screen.getByTestId("revision-snapshot-badge-204")).toHaveTextContent("Legacy (no snapshot)");
            expect(screen.getByTestId("revision-provenance-204")).toHaveTextContent("By Staff Analyst");
            expect(screen.getByTestId("btn-restore-revision-204")).toBeInTheDocument();

            expect(screen.getByTestId("current-summary-badge")).toBeInTheDocument();
            expect(screen.getByTestId("revision-snapshot-badge-203")).toHaveTextContent("Evidence snapshot");
            expect(screen.getByTestId("btn-restore-revision-203")).toBeDisabled();

            expect(screen.getByTestId("revision-role-202")).toHaveTextContent("draft");
            expect(screen.getByTestId("revision-snapshot-badge-202")).toHaveTextContent("Evidence snapshot");
            expect(screen.getByTestId("btn-review-draft-202")).toBeInTheDocument();

            expect(screen.getByTestId("revision-role-201")).toHaveTextContent("draft");
            expect(screen.getByTestId("revision-snapshot-badge-201")).toHaveTextContent("Legacy (no snapshot)");
            expect(screen.getByTestId("btn-review-draft-201")).toBeInTheDocument();
        });

        it("triggers onSelectDraft callback for draft revisions from both list item and preview pane", () => {
            mockPageProps = { summary_revisions: mixedRevisions };
            const onSelectDraftMock = vi.fn<(draft: IBillSummaryRevision) => void>();

            render(
                <BillSummaryRevisionHistory
                    billId={42}
                    currentSummary="Current active published summary with evidence snapshot."
                    onSelectDraft={onSelectDraftMock}
                />,
            );

            fireEvent.click(screen.getByTestId("toggle-revision-history"));

            fireEvent.click(screen.getByTestId("btn-review-draft-201"));
            expect(onSelectDraftMock).toHaveBeenCalledTimes(1);
            expect(onSelectDraftMock).toHaveBeenLastCalledWith(mixedRevisions[5]);

            fireEvent.click(screen.getByTestId("btn-inspect-revision-202"));
            expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent(
                "Draft revision generated from model with snapshot.",
            );
            const previewDraftBtn = screen.getByTestId("btn-review-selected-draft");
            expect(previewDraftBtn).toBeInTheDocument();
            fireEvent.click(previewDraftBtn);

            expect(onSelectDraftMock).toHaveBeenCalledTimes(2);
            expect(onSelectDraftMock).toHaveBeenLastCalledWith(mixedRevisions[4]);

            expect(mockGet).not.toHaveBeenCalled();
        });

        it("falls back to router.get navigation when onSelectDraft is omitted", () => {
            mockPageProps = { summary_revisions: mixedRevisions };

            render(
                <BillSummaryRevisionHistory
                    billId={42}
                    currentSummary="Current active published summary with evidence snapshot."
                />,
            );

            fireEvent.click(screen.getByTestId("toggle-revision-history"));

            fireEvent.click(screen.getByTestId("btn-review-draft-206"));

            expect(mockGet).toHaveBeenCalledWith(
                "/admin/bill_creator/42/summary",
                { draft_revision_id: 206 },
                { preserveScroll: true },
            );

            fireEvent.click(screen.getByTestId("btn-inspect-revision-201"));
            fireEvent.click(screen.getByTestId("btn-review-selected-draft"));

            expect(mockGet).toHaveBeenCalledWith(
                "/admin/bill_creator/42/summary",
                { draft_revision_id: 201 },
                { preserveScroll: true },
            );
        });

        it("presents distinct confirmation dialogs for snapshot restorations vs legacy review draft restorations", () => {
            mockPageProps = { summary_revisions: mixedRevisions };

            render(
                <BillSummaryRevisionHistory
                    billId={42}
                    currentSummary="Current active published summary with evidence snapshot."
                />,
            );

            fireEvent.click(screen.getByTestId("toggle-revision-history"));

            fireEvent.click(screen.getByTestId("btn-restore-revision-204"));
            expect(screen.getByTestId("restore-confirm-dialog")).toBeInTheDocument();
            expect(screen.getByText("Restore legacy revision as review draft?")).toBeInTheDocument();
            expect(screen.getByText(/This historical revision has no evidence snapshot/i)).toBeInTheDocument();
            expect(screen.getByTestId("btn-restore-confirm")).toHaveTextContent("Restore as review draft");

            fireEvent.click(screen.getByTestId("btn-restore-cancel"));
            expect(screen.queryByTestId("restore-confirm-dialog")).not.toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-restore-revision-205"));
            expect(screen.getByTestId("restore-confirm-dialog")).toBeInTheDocument();
            expect(screen.getByText("Restore summary revision?")).toBeInTheDocument();
            expect(screen.getByText(/will restore the published summary to the version recorded/i)).toBeInTheDocument();
            expect(screen.getByTestId("btn-restore-confirm")).toHaveTextContent("Restore summary");

            fireEvent.click(screen.getByTestId("btn-restore-confirm"));
            expect(mockPost).toHaveBeenCalledWith(
                "/bills/42/restore_summary_revision",
                {
                    revision_id: 205,
                    expected_summary: "Current active published summary with evidence snapshot.",
                },
                expect.objectContaining({ preserveScroll: true }),
            );

            const lastCallArgs = mockPost.mock.calls[mockPost.mock.calls.length - 1];
            const postOptions = lastCallArgs[2] as { onFinish?: () => void };
            act(() => {
                postOptions.onFinish?.();
            });

            fireEvent.click(screen.getByTestId("btn-restore-revision-204"));
            fireEvent.click(screen.getByTestId("btn-restore-confirm"));
            expect(mockPost).toHaveBeenLastCalledWith(
                "/bills/42/restore_summary_revision",
                {
                    revision_id: 204,
                    expected_summary: "Current active published summary with evidence snapshot.",
                },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        it("gracefully handles empty currentSummary and toggling inspections", () => {
            mockPageProps = { summary_revisions: mixedRevisions };

            render(<BillSummaryRevisionHistory billId={42} currentSummary="" />);

            fireEvent.click(screen.getByTestId("toggle-revision-history"));

            expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("(No published summary)");

            fireEvent.click(screen.getByTestId("btn-inspect-revision-205"));
            expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent(
                "Older published revision with model provenance and snapshot.",
            );

            fireEvent.click(screen.getByTestId("btn-inspect-revision-205"));
            expect(screen.getByTestId("revision-preview-pane")).toHaveTextContent("(No published summary)");
        });
    });

    describe("LlmSummaryEditableSummary — Stress-testing reset to published, manual evidence controls, and 422 preservation", () => {
        const legacyDraftRevision: IBillSummaryRevision = {
            id: 99,
            bill_id: 42,
            summary_markdown:
                "According to [The Banner](https://thebaltimorebanner.com/transit), the city allocated 20m for clean buses.",
            origin: "restoration",
            actor_name: "Staff Admin",
            llm_provider: null,
            llm_model: null,
            publication_role: "draft",
            review_state: "unreviewed",
            restored_from_id: 50,
            has_snapshot: false,
            news_source_snapshot_id: null,
            created_at: "2026-09-24T15:00:00Z",
        };

        const sampleArticles = [
            {
                id: 1,
                bill_id: 42,
                news_article_id: 10,
                title: "Transit Allocation Report",
                url: "https://thebaltimorebanner.com/transit",
                source_name: "The Baltimore Banner",
                approved: true,
                has_text: true,
                current_text_version_id: 101,
            },
        ];

        it("loads review draft revision, displays review notice, allows user edits, and resets to published summary", () => {
            const { rerender } = render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Official statutory summary enacted by council."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={legacyDraftRevision}
                />,
            );

            expect(getSummaryTextarea().value).toBe(legacyDraftRevision.summary_markdown);

            expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
            expect(screen.getByText(/Historical draft loaded for review \(#99\)/i)).toBeInTheDocument();

            fireEvent.change(getSummaryTextarea(), {
                target: { value: "Refined text by operator: city allocated 20m for clean buses." },
            });
            expect(getSummaryTextarea().value).toBe("Refined text by operator: city allocated 20m for clean buses.");

            const resetBtn = screen.getByRole("button", { name: /Reset to published summary/i });
            fireEvent.click(resetBtn);

            expect(getSummaryTextarea().value).toBe("Official statutory summary enacted by council.");

            expect(screen.queryByTestId("review-draft-notice")).not.toBeInTheDocument();

            const newDraftRevision: IBillSummaryRevision = {
                ...legacyDraftRevision,
                id: 100,
                summary_markdown: "Brand new draft text for revision #100.",
            };

            rerender(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Official statutory summary enacted by council."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={newDraftRevision}
                />,
            );

            expect(getSummaryTextarea().value).toBe("Brand new draft text for revision #100.");
            expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
            expect(screen.getByText(/Historical draft loaded for review \(#100\)/i)).toBeInTheDocument();
        });

        it("detects external URLs in legacy draft, shows warning under 'none', and saves under 'cited' without requiring source-use form inputs", () => {
            mockPageProps = {
                news_articles: sampleArticles,
            };

            render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Official statutory summary enacted by council."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={legacyDraftRevision}
                />,
            );

            expect(screen.getByTestId("news-usage-none")).toBeChecked();
            expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
            expect(screen.getByText(/Notice: External links detected in summary prose/i)).toBeInTheDocument();

            fireEvent.click(screen.getByTestId("news-usage-cited"));
            expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();
            expect(screen.queryByTestId("btn-add-source-use")).not.toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-save-summary"));

            expect(mockPatch).toHaveBeenCalledWith(
                "/bills/42",
                {
                    summary: legacyDraftRevision.summary_markdown,
                    return_tab: "summary",
                    news_usage: "cited",
                    source_uses: [],
                },
                expect.objectContaining({
                    preserveScroll: true,
                    preserveState: true,
                }),
            );

            fireEvent.click(screen.getByTestId("news-usage-none"));
            fireEvent.click(screen.getByTestId("btn-save-summary"));

            expect(mockPatch).toHaveBeenLastCalledWith(
                "/bills/42",
                expect.objectContaining({
                    news_usage: "none",
                    source_uses: [],
                }),
                expect.anything(),
            );
        });

        it("preserves operator draft in textarea upon 422 validation errors, router.patch onError, and expired flash", () => {
            const { rerender } = render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Official statutory summary."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={legacyDraftRevision}
                />,
            );

            fireEvent.change(getSummaryTextarea(), {
                target: { value: "Custom modified summary that triggered server validation failure." },
            });
            expect(getSummaryTextarea().value).toBe(
                "Custom modified summary that triggered server validation failure.",
            );

            mockPageProps = {
                errors: {
                    summary: "Claim 'city allocated 20m' does not match source excerpt",
                    news_usage: "Evidence grounding failed for cited article",
                },
            };

            rerender(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Official statutory summary."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={legacyDraftRevision}
                />,
            );

            expect(screen.getByTestId("summary-publication-error-banner")).toBeInTheDocument();
            expect(screen.getByText("Claim 'city allocated 20m' does not match source excerpt")).toBeInTheDocument();
            expect(screen.getByText("Evidence grounding failed for cited article")).toBeInTheDocument();

            expect(getSummaryTextarea().value).toBe(
                "Custom modified summary that triggered server validation failure.",
            );

            fireEvent.click(screen.getByTestId("btn-save-summary"));
            expect(mockPatch).toHaveBeenCalled();

            const lastCallArgs = mockPatch.mock.calls[mockPatch.mock.calls.length - 1];
            const options = lastCallArgs[2] as { onError?: () => void; onSuccess?: (page: unknown) => void };

            expect(options.onError).toBeDefined();
            options.onError?.();

            expect(mockNotify).toHaveBeenCalledWith({
                level: "error",
                title: "Summary could not be saved. See the errors below.",
            });
            expect(getSummaryTextarea().value).toBe(
                "Custom modified summary that triggered server validation failure.",
            );

            const expiredPage = {
                props: { flash: { page_expired: true } },
                url: "/admin/bill_creator/42/summary",
            };
            options.onSuccess?.(expiredPage);

            expect(mockNotify).toHaveBeenCalledWith({
                level: "error",
                title: "The page expired, so the summary was not saved. Your text is still here — save again.",
            });
            expect(getSummaryTextarea().value).toBe(
                "Custom modified summary that triggered server validation failure.",
            );
        });

        it("accepts reviewDraftRevision via camelCase prop, snake_case prop, or Inertia page props", () => {
            const { unmount: unmount1 } = render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Published."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    reviewDraftRevision={legacyDraftRevision}
                />,
            );
            expect(getSummaryTextarea().value).toBe(legacyDraftRevision.summary_markdown);
            expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
            unmount1();

            const { unmount: unmount2 } = render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Published."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                    review_draft_revision={legacyDraftRevision}
                />,
            );
            expect(getSummaryTextarea().value).toBe(legacyDraftRevision.summary_markdown);
            expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
            unmount2();

            mockPageProps = { review_draft_revision: legacyDraftRevision };
            const { unmount: unmount3 } = render(
                <LlmSummaryEditableSummary
                    billId={42}
                    publishedSummary="Published."
                    llmDraft={null}
                    llmProvider="claude"
                    llmGeneratedAt={null}
                />,
            );
            expect(getSummaryTextarea().value).toBe(legacyDraftRevision.summary_markdown);
            expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
            unmount3();
        });
    });
});
