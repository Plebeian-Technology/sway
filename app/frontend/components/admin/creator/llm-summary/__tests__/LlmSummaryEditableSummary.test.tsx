import { fireEvent, render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPatch = vi.fn<(url: string, data?: unknown, options?: unknown) => void>();
let mockPageProps: { errors?: Record<string, string>; news_articles?: unknown[]; review_draft_revision?: unknown } = {};

vi.mock("@inertiajs/react", () => ({
    router: { patch: (url: string, data?: unknown, options?: unknown) => mockPatch(url, data, options) },
    usePage: () => ({ props: mockPageProps }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(...args: unknown[]) => string>() }));

import LlmSummaryEditableSummary from "app/frontend/components/admin/creator/llm-summary/LlmSummaryEditableSummary";
import { markRegenerateRequested } from "app/frontend/components/admin/creator/llm-summary/summaryRunTabMemory";

const box = () => screen.getByTestId("textarea-llm-summary") as HTMLTextAreaElement;

describe("LlmSummaryEditableSummary — a run's new draft and the box", () => {
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it("puts a draft that arrives while the page is open into the box", () => {
        const { rerender } = render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );
        expect(box().value).toBe("Published.");

        rerender(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="Freshly generated."
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(box().value).toBe("Freshly generated.");
    });

    it("replaces one run's draft with the next run's", () => {
        const { rerender } = render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="First draft."
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        rerender(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="Second draft."
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(box().value).toBe("Second draft.");
    });

    it("leaves text the operator typed alone", () => {
        const { rerender } = render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );
        fireEvent.change(box(), { target: { value: "My own wording." } });

        rerender(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="Freshly generated."
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(box().value).toBe("My own wording.");
    });

    // The box seeds from the published column on load, not from a draft that was
    // already on the row when the page was served (C21-02).
    it("seeds from the published summary on first render even when a draft exists", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="An older draft."
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(box().value).toBe("Published.");
    });
});

// The tab rebuilds the whole summary subtree when a run lands, so the box is
// mounted fresh rather than re-rendered — this is the path a real regeneration
// actually takes.
describe("LlmSummaryEditableSummary — a run that landed while the tab was rebuilt", () => {
    beforeEach(() => window.sessionStorage.clear());

    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    it("mounts holding the new draft when this tab asked for the run", () => {
        markRegenerateRequested(1, "2026-09-05T10:00:00Z");

        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="What the run bought."
                llmProvider="claude"
                llmGeneratedAt="2026-09-05T11:00:00Z"
            />,
        );

        expect(box().value).toBe("What the run bought.");
    });

    it("mounts holding the published summary when no run of this tab's has landed", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="An older draft."
                llmProvider="claude"
                llmGeneratedAt="2026-09-05T11:00:00Z"
            />,
        );

        expect(box().value).toBe("Published.");
    });

    // The C21-02 case: a run that failed leaves the generation where it was, so
    // the draft on the row is still the old one and the box must not take it.
    it("mounts holding the published summary when the generation did not move", () => {
        markRegenerateRequested(1, "2026-09-05T11:00:00Z");

        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published."
                llmDraft="An older draft."
                llmProvider="claude"
                llmGeneratedAt="2026-09-05T11:00:00Z"
            />,
        );

        expect(box().value).toBe("Published.");
    });

    it("takes the landed run once, so a later rebuild does not re-seed the box", () => {
        markRegenerateRequested(1, "2026-09-05T10:00:00Z");
        const props = {
            billId: 1,
            publishedSummary: "Published.",
            llmDraft: "What the run bought.",
            llmProvider: "claude",
            llmGeneratedAt: "2026-09-05T11:00:00Z",
        };

        const first = render(<LlmSummaryEditableSummary {...props} />);
        first.unmount();
        render(<LlmSummaryEditableSummary {...props} />);

        expect(box().value).toBe("Published.");
    });
});

describe("LlmSummaryEditableSummary — manual news evidence controls", () => {
    beforeEach(() => {
        mockPatch.mockReset();
        mockPageProps = {};
    });

    it("renders news_usage declaration radio controls defaulting to none", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published summary."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(screen.getByTestId("news-usage-none")).toBeInTheDocument();
        expect(screen.getByTestId("news-usage-cited")).toBeInTheDocument();
        expect(screen.getByTestId("news-usage-none")).toBeChecked();
    });

    it("sends news_usage: 'none' and empty source_uses on save when none is selected", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Published summary."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(mockPatch).toHaveBeenCalledWith(
            "/bills/1",
            expect.objectContaining({
                summary: "Published summary.",
                return_tab: "summary",
                news_usage: "none",
                source_uses: [],
            }),
            expect.anything(),
        );
    });

    it("displays a warning when news_usage is 'none' but prose contains external news links", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Summary citing [The Banner](https://thebaltimorebanner.com/transit)."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(screen.getByTestId("news-usage-none-warning")).toBeInTheDocument();
        expect(screen.getByTestId("news-usage-none-warning").className).toContain("text-foreground");
        expect(screen.getByTestId("news-usage-none-warning").className).not.toContain("text-warning-foreground");
        expect(screen.getByText(/external news citations require "cited" mode/i)).toBeInTheDocument();
    });

    it("sends news_usage: 'cited' without requiring source_uses metadata when cited mode is selected", () => {
        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="The city council approved 50 electric buses, according to [The Baltimore Banner](https://thebaltimorebanner.com/transit)."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        fireEvent.click(screen.getByTestId("news-usage-cited"));

        expect(screen.queryByTestId("btn-add-source-use")).not.toBeInTheDocument();
        expect(screen.queryByTestId("news-usage-none-warning")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(mockPatch).toHaveBeenCalledWith(
            "/bills/1",
            expect.objectContaining({
                summary:
                    "The city council approved 50 electric buses, according to [The Baltimore Banner](https://thebaltimorebanner.com/transit).",
                return_tab: "summary",
                news_usage: "cited",
                source_uses: [],
            }),
            expect.anything(),
        );
    });

    it("deduplicates identical summary and news_usage validation errors in the publication error banner", () => {
        const duplicateMessage =
            "Citation URL https://example.com/unapproved does not belong to an approved news article for this bill";
        mockPageProps = {
            errors: {
                summary: duplicateMessage,
                news_usage: duplicateMessage,
            },
        };

        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Summary draft prose."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        const publicationError = within(screen.getByTestId("summary-publication-error-banner"));
        expect(publicationError.getAllByText(duplicateMessage)).toHaveLength(1);
    });

    it("displays an alert banner when server returns validation errors and preserves user work", () => {
        mockPageProps = {
            errors: {
                summary: "Claim text 'nonexistent claim' was not found in summary prose",
                news_usage: "Declared cited news usage but claim is unsupported",
            },
        };

        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Summary draft prose."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(screen.getByTestId("summary-publication-error-banner")).toBeInTheDocument();
        const publicationError = within(screen.getByTestId("summary-publication-error-banner"));
        expect(publicationError.getByText(/Claim text 'nonexistent claim' was not found/i)).toBeInTheDocument();
        expect(publicationError.getByText(/Declared cited news usage but claim is unsupported/i)).toBeInTheDocument();
        expect(box().value).toBe("Summary draft prose.");
    });

    it("initializes editableSummary with review_draft_revision and displays review-draft-notice banner", () => {
        const draftRevision = {
            id: 88,
            bill_id: 1,
            summary_markdown: "Historical legacy draft prose needing evidence review.",
            origin: "restoration",
            actor_name: "Admin User",
            llm_provider: null,
            llm_model: null,
            publication_role: "draft",
            review_state: "unreviewed",
            restored_from_id: 42,
            has_snapshot: false,
            news_source_snapshot_id: null,
            created_at: "2026-09-24T12:00:00Z",
        };

        mockPageProps = { review_draft_revision: draftRevision };

        render(
            <LlmSummaryEditableSummary
                billId={1}
                publishedSummary="Current public summary."
                llmDraft={null}
                llmProvider="claude"
                llmGeneratedAt={null}
            />,
        );

        expect(box().value).toBe("Historical legacy draft prose needing evidence review.");
        expect(screen.getByTestId("review-draft-notice")).toBeInTheDocument();
        expect(screen.getByTestId("review-draft-notice").className).toContain("text-foreground");
        expect(screen.getByTestId("review-draft-notice").className).not.toMatch(/\bdark:/);
        expect(screen.getByText(/Historical draft loaded for review/i)).toBeInTheDocument();
        expect(screen.getByText(/#88/i)).toBeInTheDocument();

        fireEvent.click(screen.getByTestId("btn-save-summary"));
        expect(mockPatch).toHaveBeenCalledWith(
            "/bills/1",
            expect.objectContaining({
                summary: "Historical legacy draft prose needing evidence review.",
                return_tab: "summary",
                news_usage: "none",
            }),
            expect.anything(),
        );

        fireEvent.click(screen.getByRole("button", { name: /Reset to published summary/i }));
        expect(box().value).toBe("Current public summary.");
    });
});
