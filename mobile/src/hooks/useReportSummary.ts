// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
import { useCallback, useState } from "react";

import { apiClient } from "../api/client";
import { ApiRequestError, NetworkError, RateLimitedError } from "../api/errors";
import { Routes } from "../api/routes";
import type { SummaryReportReason } from "../types/bill";

export type ReportSummaryOutcome = "submitted" | "duplicate" | "rate_limited" | "offline" | "failed";

export interface UseReportSummaryResult {
    submit: (reason: SummaryReportReason, details: string) => Promise<ReportSummaryOutcome>;
    submitting: boolean;
}

const HTTP_UNPROCESSABLE = 422;

const outcomeOf = (error: unknown): Exclude<ReportSummaryOutcome, "submitted"> => {
    if (error instanceof RateLimitedError) return "rate_limited";
    if (error instanceof NetworkError) return "offline";
    // @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
    if (error instanceof ApiRequestError && error.status === HTTP_UNPROCESSABLE) return "duplicate";
    return "failed";
};

export function useReportSummary(billId: number): UseReportSummaryResult {
    const [submitting, setSubmitting] = useState(false);

    const submit = useCallback(
        async (reason: SummaryReportReason, details: string): Promise<ReportSummaryOutcome> => {
            setSubmitting(true);
            try {
                await apiClient.post(Routes.billSummaryReports(billId), {
                    bill_summary_report: { reason, details: details.trim() },
                });
                return "submitted";
            } catch (error: unknown) {
                return outcomeOf(error);
            } finally {
                setSubmitting(false);
            }
        },
        [billId],
    );

    return { submit, submitting };
}
