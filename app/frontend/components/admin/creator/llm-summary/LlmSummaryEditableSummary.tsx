import { router, usePage } from "@inertiajs/react";
import { useCallback, useState } from "react";
import { notify } from "app/frontend/sway_utils";
import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { Separator } from "app/frontend/components/ui/separator";
import { Textarea } from "app/frontend/components/ui/textarea";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import LlmSummaryDraftNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryDraftNotice";
import ManualNewsEvidenceControls from "app/frontend/components/admin/creator/llm-summary/ManualNewsEvidenceControls";
import { PUBLIC_SUMMARY_TITLE_ID } from "app/frontend/components/admin/creator/llm-summary/summaryTitleIds";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";
import { takeLandedRegenerate } from "app/frontend/components/admin/creator/llm-summary/summaryRunTabMemory";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import type { ISourceUseInput, NewsUsage } from "app/frontend/types/bill_creator";
import type { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    billId: number;
    // @lat: [[bill-summary-published-vs-draft-box-bug#publishedSummary prop notes]]
    publishedSummary: string;
    llmDraft: string | null;
    llmProvider: string | null;
    llmGeneratedAt: string | null;
    statusSlot?: React.ReactNode;
    runActions?: React.ReactNode;
    reviewDraftRevision?: IBillSummaryRevision | null;
    review_draft_revision?: IBillSummaryRevision | null;
}

interface IPageProps extends Record<string, unknown> {
    errors?: Record<string, string>;
}

const LlmSummaryEditableSummary: React.FC<IProps> = ({
    billId,
    publishedSummary,
    llmDraft,
    llmProvider,
    llmGeneratedAt,
    statusSlot,
    runActions,
    reviewDraftRevision,
    review_draft_revision,
}) => {
    // @lat: [[bill-creator-summary-tab#How summary-save errors reach the editor]]
    const pageProps = usePage<IPageProps>().props;
    const pageErrors = pageProps.errors ?? {};
    const effectiveReviewDraft =
        reviewDraftRevision ??
        review_draft_revision ??
        (pageProps.review_draft_revision as IBillSummaryRevision | null) ??
        null;

    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
    const [seed] = useState<string>(() => {
        if (effectiveReviewDraft) return effectiveReviewDraft.summary_markdown;
        return llmDraft && takeLandedRegenerate(billId, llmGeneratedAt) ? llmDraft : publishedSummary;
    });
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
    const [lastPublishedSummary, setLastPublishedSummary] = useState<string>(publishedSummary);
    const [editableSummary, setEditableSummary] = useState<string>(seed);
    const [newsUsage, setNewsUsage] = useState<NewsUsage>("none");
    const [sourceUses, setSourceUses] = useState<ISourceUseInput[]>([]);
    const [dismissedReviewDraftId, setDismissedReviewDraftId] = useState<number | null>(null);

    const [lastLlmDraft, setLastLlmDraft] = useState<string | null>(llmDraft);
    const [lastReviewDraftId, setLastReviewDraftId] = useState<number | null>(effectiveReviewDraft?.id ?? null);

    if (effectiveReviewDraft && effectiveReviewDraft.id !== lastReviewDraftId) {
        setLastReviewDraftId(effectiveReviewDraft.id);
        setDismissedReviewDraftId(null);
        setEditableSummary(effectiveReviewDraft.summary_markdown);
    }

    if (publishedSummary !== lastPublishedSummary) {
        setLastPublishedSummary(publishedSummary);
        if (editableSummary === lastPublishedSummary) setEditableSummary(publishedSummary);
    }

    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    if (llmDraft !== lastLlmDraft) {
        setLastLlmDraft(llmDraft);
        const untouched = editableSummary === lastLlmDraft || editableSummary === lastPublishedSummary;
        if (llmDraft && untouched) setEditableSummary(llmDraft);
    }

    const handleSaveSummary = useCallback(() => {
        router.patch(
            `/bills/${billId}`,
            // @lat: [[bill-save-return-tab-routing#Why a bill save carries its own return tab]]
            {
                summary: editableSummary,
                return_tab: "summary",
                news_usage: newsUsage,
                source_uses: (newsUsage === "cited" ? sourceUses : []) as never,
            },
            {
                preserveScroll: true,
                preserveState: true,
                // @lat: [[bill-creator-landed-write-detection#One reachable case, not two#LlmSummaryEditableSummary's defensive non-bill-landing test]]
                onSuccess: (page: any) => {
                    // @lat: [[page-expired-flash-flag-and-c21-01#LlmSummaryEditableSummary's page-expired test note]]
                    if (pageExpired(page)) {
                        notify({
                            level: "error",
                            title: "The page expired, so the summary was not saved. Your text is still here — save again.",
                        });
                        return;
                    }
                    if (!landedOnBillCreator(page.url, billId)) {
                        notify({
                            level: "error",
                            title: "The summary was not saved to this bill. Sign in as an admin and try again.",
                        });
                        return;
                    }
                    notify({ level: "success", title: "Summary saved." });
                },
                onError: () =>
                    notify({
                        level: "error",
                        title: "Summary could not be saved. See the errors below.",
                    }),
            },
        );
    }, [billId, editableSummary, newsUsage, sourceUses]);

    return (
        <div className="flex flex-col gap-3">
            <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="flex min-w-0 items-center gap-1.5">
                    <h3 id={PUBLIC_SUMMARY_TITLE_ID} className="text-lg font-semibold">
                        Public summary{" "}
                        <span className="text-sm font-normal text-muted-foreground">
                            (editable — this is what users see)
                        </span>
                    </h3>
                    <FeatureInfo note="summary.publicSummary" />
                </div>
                {statusSlot}
            </div>
            <Textarea
                id="llm-summary"
                aria-labelledby={PUBLIC_SUMMARY_TITLE_ID}
                rows={10}
                value={editableSummary}
                onChange={(e) => setEditableSummary(e.target.value)}
                data-testid="textarea-llm-summary"
            />
            {Object.entries(pageErrors).length > 0 && (
                <Alert variant="destructive" data-testid="summary-save-errors">
                    <AlertTitle>Summary wasn’t saved</AlertTitle>
                    <AlertDescription>
                        <ul className="list-disc pl-4">
                            {Object.entries(pageErrors).map(([field, message]) => (
                                <li key={field}>
                                    {field}: {String(message)}
                                </li>
                            ))}
                        </ul>
                    </AlertDescription>
                </Alert>
            )}
            <p className="text-xs text-muted-foreground">
                Saving writes this text to the bill. The model&apos;s draft is stored separately and is not changed by
                saving.
            </p>

            {effectiveReviewDraft && dismissedReviewDraftId !== effectiveReviewDraft.id && (
                <div
                    data-testid="review-draft-notice"
                    className="rounded-xl border-neo border-warning bg-warning/12 p-3 text-xs text-foreground flex flex-col gap-1.5"
                >
                    <div className="flex items-center justify-between gap-2">
                        <span className="font-semibold">
                            Historical draft loaded for review (#{effectiveReviewDraft.id})
                        </span>
                        <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            className="h-6 px-2 text-[10px]"
                            onClick={() => {
                                setEditableSummary(publishedSummary);
                                setDismissedReviewDraftId(effectiveReviewDraft.id);
                            }}
                        >
                            Reset to published summary
                        </Button>
                    </div>
                    <p>
                        This historical revision was restored as a draft. Review the summary, declare news usage below,
                        and save to publish. The live public summary remains unchanged until you save.
                    </p>
                </div>
            )}

            <LlmSummaryDraftNotice
                llmDraft={llmDraft}
                llmProvider={llmProvider}
                publishedSummary={publishedSummary}
                onUseDraft={() => setEditableSummary(llmDraft ?? "")}
            />

            <ManualNewsEvidenceControls
                summary={editableSummary}
                newsUsage={newsUsage}
                onChangeNewsUsage={setNewsUsage}
                sourceUses={sourceUses}
                onChangeSourceUses={setSourceUses}
            />

            {(pageErrors.summary || pageErrors.news_usage) && (
                <div
                    data-testid="summary-publication-error-banner"
                    className="rounded-xl border-neo border-destructive bg-destructive/12 p-3 text-xs text-destructive flex flex-col gap-1"
                >
                    <span className="font-semibold">Publication validation error:</span>
                    {pageErrors.summary && <span>{pageErrors.summary}</span>}
                    {pageErrors.news_usage && pageErrors.news_usage !== pageErrors.summary && (
                        <span>{pageErrors.news_usage}</span>
                    )}
                </div>
            )}

            {/* @lat: [[bill-creator-summary-tab#One action bar, one filled button]] */}
            <div className="flex flex-col items-stretch gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:gap-3">
                <div className="flex items-center gap-1.5">
                    <Button
                        type="button"
                        size="sm"
                        variant="default"
                        onClick={handleSaveSummary}
                        data-testid="btn-save-summary"
                        className="flex-1 sm:flex-none"
                    >
                        Save summary
                    </Button>
                    <FeatureInfo note="summary.saveSummary" />
                </div>
                {runActions ? (
                    <>
                        <Separator
                            orientation="vertical"
                            className="hidden h-8! self-center bg-border-strong sm:block"
                        />
                        {runActions}
                    </>
                ) : null}
            </div>
        </div>
    );
};

export default LlmSummaryEditableSummary;
