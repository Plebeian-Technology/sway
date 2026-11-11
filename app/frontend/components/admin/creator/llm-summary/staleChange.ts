import { relativeTime } from "app/frontend/sway_utils/datetimes";

// @lat: [[stale-change-detection#staleChangeLabel's fallback wording]]
export const TESTIMONY_CHANGE = "testimony";
export const PIPELINE_DATA_CHANGE = "pipeline_data";

export type TStaleChangeKind = typeof TESTIMONY_CHANGE | typeof PIPELINE_DATA_CHANGE;

// @lat: [[stale-change-detection#staleChangeLabel's fallback wording]]
export const staleChangeLabel = (kind: TStaleChangeKind | null, at: string | null): string => {
    if (kind === null || at === null) return "Stale: last update unknown";

    const subject = kind === TESTIMONY_CHANGE ? "testimony" : "pipeline data";
    return `Stale: ${subject} updated ${relativeTime(at)}`;
};
