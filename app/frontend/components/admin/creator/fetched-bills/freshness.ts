// @lat: [[bill-creator-pipeline-llm-tab#Fetched-bills freshness thresholds]]
export const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
export const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

export type FreshnessTone = "success" | "warning" | "danger";
export type FreshnessFilter = "all" | FreshnessTone;

export const freshnessTone = (fetchedAt: string): FreshnessTone => {
    const ageMs = Date.now() - new Date(fetchedAt).getTime();
    if (ageMs < SEVEN_DAYS_MS) return "success";
    if (ageMs < THIRTY_DAYS_MS) return "warning";
    return "danger";
};

export const freshnessLabel = (tone: FreshnessTone): string => {
    switch (tone) {
        case "success":
            return "fresh";
        case "warning":
            return "stale";
        case "danger":
            return "very stale";
    }
};

export const FILTER_CHIPS: ReadonlyArray<{ key: FreshnessFilter; label: string }> = [
    { key: "all", label: "All" },
    { key: "success", label: "Fresh" },
    { key: "warning", label: "Stale" },
    { key: "danger", label: "Very stale" },
];
