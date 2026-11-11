import { usePage } from "@inertiajs/react";
import { ExternalLink, Flag } from "lucide-react";
import React, { useState } from "react";
import { sway } from "sway";

import { Button } from "app/frontend/components/ui/button";
import ReportSummaryDialog from "app/frontend/components/bill/ReportSummaryDialog";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";

interface IProps {
    unreviewed: boolean | undefined;
    className?: string;
    billId?: number;
    billLink?: string | null;
    genericPortalUrls?: string[];
}

const AiUnreviewedNotice: React.FC<IProps> = ({ unreviewed, className, billId, billLink, genericPortalUrls }) => {
    const [reportModalOpen, setReportModalOpen] = useState(false);
    let pageLocaleUrls: string[] | undefined;
    let isArchivedBill = false;
    try {
        // oxlint-disable-next-line react-hooks/rules-of-hooks -- fallback in non-Inertia test environments
        const page = usePage<
            sway.IPageProps & { bill?: { active?: boolean; scheduled_release_date_utc?: string | null } }
        >();
        pageLocaleUrls = page?.props?.sway_locale?.generic_portal_urls;
        isArchivedBill = isArchivedHistoricalBill(page?.props?.bill);
    } catch {
        pageLocaleUrls = undefined;
    }
    const portalUrls = genericPortalUrls ?? pageLocaleUrls;
    const canReportSummary = !isArchivedBill;

    if (!billId) {
        if (!unreviewed) return null;

        return (
            <p
                className={`mt-2 text-xs font-semibold text-muted-foreground ${className ?? ""}`}
                data-testid="ai-unreviewed-notice"
            >
                {PARITY_COPY.bill.aiUnreviewedNotice}
            </p>
        );
    }

    const hasSourceLink = hasValidSourceLink(billLink, portalUrls);

    // @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]
    // @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries]]
    return (
        <>
            <div
                className={`mt-3 flex flex-col gap-2 rounded-xl border border-border bg-surface-2 px-3 py-2.5 sm:flex-row sm:items-center sm:justify-between ${className ?? ""}`}
                data-testid="ai-summary-notice-bar"
            >
                <div className="flex flex-col gap-0.5 text-xs text-muted-foreground">
                    {unreviewed && (
                        <span className="font-semibold text-foreground" data-testid="ai-unreviewed-notice">
                            {PARITY_COPY.bill.aiUnreviewedNotice}
                        </span>
                    )}
                    {hasSourceLink ? (
                        <a
                            href={billLink as string}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
                            data-testid="bill-source-text-link"
                        >
                            <span>{PARITY_COPY.bill.viewOriginalText}</span>
                            <ExternalLink className="size-3" aria-hidden="true" />
                        </a>
                    ) : (
                        <span
                            className="text-xs font-semibold text-muted-foreground"
                            data-testid="summary-no-source-link"
                        >
                            {PARITY_COPY.bill.officialSourceUnavailable}
                        </span>
                    )}
                </div>

                {canReportSummary && (
                    <div className="flex shrink-0 items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            onClick={() => setReportModalOpen(true)}
                            className="min-h-11 cursor-pointer gap-1.5 text-xs font-semibold"
                            data-testid="btn-report-inaccurate-summary"
                            aria-label={PARITY_COPY.bill.reportInaccurateSummary}
                        >
                            <Flag className="size-3.5 text-muted-foreground" aria-hidden="true" />
                            <span>{PARITY_COPY.bill.reportInaccurateSummary}</span>
                        </Button>
                    </div>
                )}
            </div>

            {canReportSummary && (
                <ReportSummaryDialog
                    open={reportModalOpen}
                    onOpenChange={setReportModalOpen}
                    billId={billId}
                    billLink={billLink}
                />
            )}
        </>
    );
};

export default AiUnreviewedNotice;
