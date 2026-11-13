// @lat: [[bill-title-display#Where only the subject is shown]]

const headOf = (title: string): string =>
    title
        .trim()
        .split(/\s+FOR\s+the\s+purpose\s+of\s+/i)[0]
        .trim();

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

export const billHeadline = (title?: string | null): string => {
    if (!title) return "";
    return splitBillTitle(title).headline;
};

export const shortBillTitle = (title: string): string => {
    const { headline, deck } = splitBillTitle(title);
    return deck ? `${headline} — ${deck}` : headline;
};

export const hasMoreThanHeadline = (title: string): boolean => title.trim() !== billHeadline(title);
