// @lat: [[testimony-attachment-warning-lists#Why countNoun is separate from attachmentCountText]]
export const countNoun = (count: number = 0, singular: string, plural: string): string => {
    const safeCount = typeof count === "number" && !isNaN(count) ? count : 0;
    return `${safeCount.toLocaleString()} ${safeCount === 1 ? singular : plural}`;
};
