import { usePage, usePoll } from "@inertiajs/react";
import { useEffect, useState } from "react";
import { isPipelineBusy, TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import type { ISummarySources } from "app/frontend/components/admin/creator/llm-summary/types";
import { usePipelineRunSubscription } from "app/frontend/hooks/usePipelineRunSubscription";
import BillCategoryOverride from "app/frontend/components/admin/creator/BillCategoryOverride";
import BillCreatorLlmSummary from "app/frontend/components/admin/creator/BillCreatorLlmSummary";
import BillCreatorNewsArticles from "app/frontend/components/admin/creator/BillCreatorNewsArticles";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

// @lat: [[bill-creator-positions-tab#Splitting the tab split the poll list]]
const SUMMARY_ONLY_PROPS = ["bill", "active_legislation_pipeline_run", "summary_sources"] as const;

interface ILegislationPipelineRun {
    remote_run_id?: string | null;
    status?: string | null;
}

interface IPageProps {
    bill?: {
        id?: number | null;
        bill_llm_provisioning?: {
            llm_generated_at?: string | null;
            generation_status?: string | null;
        };
        bill_pipeline_refresh?: { status?: TBillPipelineStatus } | null;
    };
    active_legislation_pipeline_run?: ILegislationPipelineRun | null;
    // @lat: [[partial-reload-poll-lists#What a tab's list has to carry besides its own props]]
    summary_sources?: ISummarySources | null;
    [key: string]: unknown;
}

const CATEGORIES_TITLE_ID = "bill-categories-title";
const NEWS_ARTICLES_TITLE_ID = "bill-news-articles-title";

const POLL_INTERVAL_MS = 5000;

// @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
const NO_PROVISIONING_POLL_ATTEMPTS = 12;

// @lat: [[bill-creator-summary-tab#Why the poller is a mounted component]]
const SummaryGenerationPoller: React.FC<Record<string, never>> = () => {
    usePoll(POLL_INTERVAL_MS, { only: [...SUMMARY_ONLY_PROPS] });
    return null;
};

// @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
const BillCreatorSummary: React.FC = () => {
    const { props } = usePage<IPageProps>();
    const bill = props.bill;
    const run = props.active_legislation_pipeline_run ?? null;
    const isNoBillId = !(bill?.id && bill.id > 0);

    usePipelineRunSubscription(run?.remote_run_id ?? null, SUMMARY_ONLY_PROPS);

    // @lat: [[bill-creator-summary-tab#Why the poller is a mounted component]]
    const isGenerating =
        bill?.bill_llm_provisioning?.generation_status === "pending" ||
        bill?.bill_llm_provisioning?.generation_status === "generating";

    const hasNoProvisioning = !bill?.bill_llm_provisioning;

    // @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
    const isBillPipelineRunning = isPipelineBusy(bill?.bill_pipeline_refresh?.status ?? null);

    // @lat: [[bill-creator-summary-tab#Why the no-provisioning poll runs out]]
    const watchKey = String(bill?.id ?? 0);
    const [spentWatchKey, setSpentWatchKey] = useState<string | null>(null);
    const noProvisioningWatchSpent = spentWatchKey === watchKey;
    useEffect(() => {
        if (!hasNoProvisioning) return;

        const timer = setTimeout(() => setSpentWatchKey(watchKey), NO_PROVISIONING_POLL_ATTEMPTS * POLL_INTERVAL_MS);
        return () => clearTimeout(timer);
    }, [hasNoProvisioning, watchKey]);

    if (isNoBillId) {
        return (
            <div className="flex flex-col gap-8" data-testid="summary-tab">
                <p className="text-sm text-muted-foreground" data-testid="summary-no-bill-selected">
                    Select a bill above to view or edit its LLM summary.
                </p>
            </div>
        );
    }

    return (
        <div className="flex flex-col gap-8" data-testid="summary-tab">
            {(isGenerating || (hasNoProvisioning && !noProvisioningWatchSpent) || isBillPipelineRunning) && (
                <SummaryGenerationPoller />
            )}
            {/* @lat: [[bill-creator-summary-tab#Why the summary card is keyed on the generation time]] */}
            <BillCreatorLlmSummary
                key={`${bill?.id ?? "new"}:${bill?.bill_llm_provisioning?.llm_generated_at ?? "none"}`}
            />

            {/* @lat: [[news-admin-ui#Integration into the Bill Creator summary tab]] */}
            <section
                aria-labelledby={NEWS_ARTICLES_TITLE_ID}
                className="flex flex-col gap-4 border-t-neo border-border pt-6"
                data-testid="section-BillCreatorNewsArticles"
            >
                <div className="flex min-w-0 items-center gap-1.5">
                    <h3 id={NEWS_ARTICLES_TITLE_ID} className="text-lg font-semibold">
                        News articles
                    </h3>
                </div>
                <BillCreatorNewsArticles billId={bill?.id} />
            </section>

            {bill?.bill_llm_provisioning && (
                <section
                    aria-labelledby={CATEGORIES_TITLE_ID}
                    className="flex flex-col gap-4 border-t-neo border-border pt-6"
                    data-testid="section-BillCategoryOverride"
                >
                    <div className="flex min-w-0 items-center gap-1.5">
                        <h3 id={CATEGORIES_TITLE_ID} className="text-lg font-semibold">
                            Categories
                        </h3>
                        <FeatureInfo note="summary.categories" />
                    </div>
                    <BillCategoryOverride />
                </section>
            )}
        </div>
    );
};

export default BillCreatorSummary;
export { SUMMARY_ONLY_PROPS };
