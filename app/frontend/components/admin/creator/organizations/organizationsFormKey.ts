// @lat: [[bill-creator-summary-tab#Why the organizations panel carries a remount key]]
export const organizationsFormKey = (bill?: {
    id?: number | null;
    organizations?: ReadonlyArray<{ id: number }>;
}): string => {
    const ids = (bill?.organizations ?? []).map((o) => o.id).sort((a, b) => a - b);
    return `${bill?.id ?? 0}:${ids.length > 0 ? ids.join(",") : "none"}`;
};
