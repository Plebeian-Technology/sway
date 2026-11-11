// @lat: [[bill-as-introduced-title-split#shortBillTitle must keep the clause searchable even though it drops it from the label]]

const headOf = (title: string): string =>
    title
        .trim()
        .split(/\s+FOR\s+the\s+purpose\s+of\s+/i)[0]
        .trim();

// @lat: [[bill-as-introduced-title-split#billTitle.ts helpers]]
export const hasLegalClause = (title: string): boolean => /\sFOR\s+the\s+purpose\s+of\s/i.test(title.trim());

export interface SplitBillTitle {
    headline: string;
    deck: string | null;
}

export const splitBillTitle = (title: string): SplitBillTitle => {
    const head = headOf(title);
    const dash = head.match(/^(.+?)\s+[–—-]\s+(.+)$/);
    if (dash) return { headline: dash[1].trim(), deck: dash[2].trim() };
    return { headline: head || title.trim(), deck: null };
};

// @lat: [[bill-as-introduced-title-split#shortBillTitle must keep the clause searchable even though it drops it from the label]]
export const shortBillTitle = (title: string): string => {
    const { headline, deck } = splitBillTitle(title);
    return deck ? `${headline} — ${deck}` : headline;
};

export const briefSummary = (summary: string | undefined, maxLen: number): string =>
    summary
        ? summary
              .replace(/NEWLINE|ENDING/g, " ")
              .replace(/\s+/g, " ")
              .trim()
              .slice(0, maxLen)
        : "";
