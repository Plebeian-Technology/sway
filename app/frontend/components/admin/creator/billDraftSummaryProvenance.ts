export interface IStoredBillDraft {
    summary?: string;
    // @lat: [[bill-creator-initial-values-and-draft-restore#billDraftSummaryProvenance.ts internals#Why summary_at_draft_time is captured, not read live]]
    summary_at_draft_time?: string;
}

export interface IReconciledDraftSummaryValues {
    summary: string;
    // @lat: [[bill-creator-initial-values-and-draft-restore#billDraftSummaryProvenance.ts internals#Why summary_at_draft_time is cleared on the reconciled values]]
    summary_at_draft_time: undefined;
}

export interface IReconciledDraftSummary {
    values: IReconciledDraftSummaryValues;
    // @lat: [[bill-creator-initial-values-and-draft-restore#billDraftSummaryProvenance.ts internals#Why yielded only reports when something was actually lost]]
    yielded: boolean;
}

// @lat: [[bill-creator-initial-values-and-draft-restore#Why the draft's summary yields to a newer published one]]
export const stampSummaryProvenance = <TDraft extends object>(
    draft: TDraft,
    summaryWrittenAgainst: string,
): TDraft & { summary_at_draft_time: string } => ({ ...draft, summary_at_draft_time: summaryWrittenAgainst });

// @lat: [[bill-creator-initial-values-and-draft-restore#billDraftSummaryProvenance.ts internals#Why yielded exists on IReconciledDraftSummary]]
export const reconciledDraftSummary = (stored: IStoredBillDraft, publishedSummary: string): IReconciledDraftSummary => {
    const stamp = stored.summary_at_draft_time;
    const kept = stamp !== undefined && stamp === publishedSummary;
    const summary = kept ? (stored.summary ?? "") : publishedSummary;
    // @lat: [[bill-creator-initial-values-and-draft-restore#billDraftSummaryProvenance.ts internals#Why yielded only reports when something was actually lost]]
    const yielded = !kept && (stored.summary ?? "") !== summary;

    return { values: { summary, summary_at_draft_time: undefined }, yielded };
};
