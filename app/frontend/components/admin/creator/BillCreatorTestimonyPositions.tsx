import { router, usePage } from "@inertiajs/react";
import { useCallback, useMemo, useState } from "react";
import type { sway } from "sway";
import LlmSummaryOrgPositions from "app/frontend/components/admin/creator/llm-summary/LlmSummaryOrgPositions";
import LlmSummaryPositionsErrorNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryPositionsErrorNotice";
import LlmSummaryTestimonyAttachmentWarning from "app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyAttachmentWarning";
import PositionsRunInFlightNotice from "app/frontend/components/admin/creator/llm-summary/PositionsRunInFlightNotice";
import SupplementalTestimonyField from "app/frontend/components/admin/creator/llm-summary/SupplementalTestimonyField";
import { TESTIMONY_REGION_TITLE_ID } from "app/frontend/components/admin/creator/llm-summary/summaryTitleIds";
import { TBill, TDraftOrgPosition } from "app/frontend/components/admin/creator/llm-summary/types";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";
import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import { pageExpired } from "app/frontend/sway_utils/pageExpired";
import { notify } from "app/frontend/sway_utils";
import { useConfirm } from "@/components/ui/confirm-dialog";

interface IPageProps {
    bill: TBill;
    active_legislation_pipeline_run?: { status?: string | null; bill_id?: number | null } | null;
    public_testimony_counts?: sway.IPublicTestimonyCounts | null;
    public_testimony_letters?: sway.IPublicTestimonyLetter[] | null;
    [key: string]: unknown;
}

// @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
const BillCreatorTestimonyPositions: React.FC = () => {
    const pageProps = usePage<IPageProps>().props;
    const bill = pageProps.bill;
    const billId = bill.id;
    const provisioning = bill.bill_llm_provisioning;

    // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run#The box takes a newer server value only when nothing is unsaved in it]]
    const serverSupplemental = provisioning?.supplemental_testimony || "";
    const [lastServerSupplemental, setLastServerSupplemental] = useState<string>(serverSupplemental);
    const [supplementalText, setSupplementalText] = useState<string>(serverSupplemental);

    if (serverSupplemental !== lastServerSupplemental) {
        setLastServerSupplemental(serverSupplemental);
        if (supplementalText === lastServerSupplemental) setSupplementalText(serverSupplemental);
    }

    const confirm = useConfirm();

    const orgPositions: TDraftOrgPosition[] = useMemo(
        () =>
            (provisioning?.draft_org_positions || [])
                .map((p, rawIndex) => ({ ...p, rawIndex }))
                .filter((p) => !p.rejected),
        [provisioning?.draft_org_positions],
    );

    const activeRun = pageProps.active_legislation_pipeline_run;
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id === null || activeRun.bill_id === billId);
    const summaryRunInFlight =
        provisioning?.generation_status === "pending" || provisioning?.generation_status === "generating";
    const runInFlight = !!summaryRunInFlight || !!cleanTestimonyRunning;

    // @lat: [[bill-creator-summary-tab#Supplemental testimony is replaced, never appended]]
    const replacesStoredTestimony =
        serverSupplemental.trim().length > 0 && !supplementalText.includes(serverSupplemental);

    const testimonyPositionsCount = useMemo(
        () =>
            orgPositions.filter(
                (p) =>
                    (p.bill_news_article_id === null || p.bill_news_article_id === undefined) &&
                    (p.text_version_id === null || p.text_version_id === undefined) &&
                    !p.evidence_excerpt,
            ).length,
        [orgPositions],
    );

    const handleSaveSupplemental = useCallback(async () => {
        if (!billId) return;

        if (testimonyPositionsCount > 0 && replacesStoredTestimony) {
            const confirmed = await confirm({
                title: "Save and block these positions?",
                description:
                    `Saving replaces the testimony the ${testimonyPositionsCount} draft position` +
                    `${testimonyPositionsCount === 1 ? "" : "s"} on this bill ` +
                    `${testimonyPositionsCount === 1 ? "was" : "were"} written from, so ` +
                    `${testimonyPositionsCount === 1 ? "it" : "they"} can no longer be approved. ` +
                    "Regenerate or reject them instead of pasting the old testimony back.",
                confirmLabel: "Save testimony",
                tone: "destructive",
            });
            if (!confirmed) return;
        }

        router.patch(
            `/bills/${billId}/supplemental_testimony`,
            { supplemental_testimony: supplementalText },
            {
                preserveScroll: true,
                onSuccess: (page) => {
                    if (pageExpired(page)) {
                        notify({
                            level: "error",
                            title: "The page expired, so the testimony was not saved. Your text is still here — save again.",
                        });
                        return;
                    }
                    if (landedOnBillCreator(page.url, billId)) return;

                    notify({
                        level: "error",
                        title: "The testimony was not saved to this bill. Sign in as an admin and try again.",
                    });
                },
                onError: () =>
                    notify({
                        level: "error",
                        title: "Could not save the supplemental testimony — it is not on this bill yet.",
                    }),
            },
        );
    }, [billId, supplementalText, testimonyPositionsCount, replacesStoredTestimony, confirm]);

    const handleClearSupplemental = useCallback(async () => {
        if (!billId) return;

        if (testimonyPositionsCount > 0) {
            const confirmed = await confirm({
                title: "Clear the testimony and block these positions?",
                description:
                    `Clearing removes the testimony the ${testimonyPositionsCount} draft position` +
                    `${testimonyPositionsCount === 1 ? "" : "s"} on this bill ` +
                    `${testimonyPositionsCount === 1 ? "was" : "were"} written from, so ` +
                    `${testimonyPositionsCount === 1 ? "it" : "they"} can no longer be approved. ` +
                    "Pasting the testimony back does not restore them — regenerate or reject them instead.",
                confirmLabel: "Clear testimony",
                tone: "destructive",
            });
            if (!confirmed) return;
        }

        router.patch(
            `/bills/${billId}/supplemental_testimony`,
            { clear_supplemental_testimony: true },
            {
                preserveScroll: true,
                onSuccess: (page) => {
                    if (pageExpired(page)) {
                        notify({
                            level: "error",
                            title: "The page expired, so the testimony was not cleared. Clear it again.",
                        });
                        return;
                    }
                    if (landedOnBillCreator(page.url, billId)) return;

                    notify({
                        level: "error",
                        title: "The testimony was not cleared on this bill. Sign in as an admin and try again.",
                    });
                },
                onError: () =>
                    notify({
                        level: "error",
                        title: "Could not clear the supplemental testimony — it is still on this bill.",
                    }),
            },
        );
    }, [billId, testimonyPositionsCount, confirm]);

    return (
        <section aria-labelledby={TESTIMONY_REGION_TITLE_ID} data-testid="region-testimony-and-positions">
            <div className="flex flex-col gap-4">
                <h3 id={TESTIMONY_REGION_TITLE_ID} className="text-lg font-semibold">
                    Testimony and positions
                </h3>

                {/* @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]] */}
                <p className="text-sm text-muted-foreground" data-testid="positions-testimony-save-first">
                    Testimony never reaches the summary model. It is what the draft positions below are written from,
                    and a run reads only what Save testimony has written to this bill.
                </p>

                <p className="text-xs text-muted-foreground" data-testid="positions-news-opinion-notice">
                    For news opinion commentary, assign stances in the News articles review section on the Summary tab.
                </p>

                <LlmSummaryTestimonyAttachmentWarning attachments={provisioning?.testimony_attachments ?? null} />

                <SupplementalTestimonyField
                    value={supplementalText}
                    onChange={setSupplementalText}
                    onClear={handleClearSupplemental}
                    onSave={handleSaveSupplemental}
                    storedValue={serverSupplemental}
                />

                <LlmSummaryPositionsErrorNotice
                    generationStatus={provisioning?.generation_status ?? null}
                    generationError={provisioning?.generation_error ?? null}
                    hasDrafts={orgPositions.length > 0}
                />

                <PositionsRunInFlightNotice
                    summaryRunInFlight={!!summaryRunInFlight}
                    cleanTestimonyRunning={!!cleanTestimonyRunning}
                    draftCount={orgPositions.length}
                    abandoned={!!provisioning?.reclaimable}
                />

                <LlmSummaryOrgPositions
                    billId={billId}
                    orgPositions={orgPositions}
                    hasTestimony={!!provisioning?.has_testimony}
                    runInFlight={runInFlight}
                />

                <PublicTestimonySection
                    counts={pageProps.public_testimony_counts ?? null}
                    letters={pageProps.public_testimony_letters ?? null}
                    billTitle={bill.title ?? undefined}
                    billId={billId}
                    canOverrideStance={true}
                />
            </div>
        </section>
    );
};

export default BillCreatorTestimonyPositions;
