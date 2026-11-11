// @lat: [[pipeline-failure-timing-missing-value-rule#Why failureTiming.ts returns null, not an empty string]]
import { formatDateTime, isValidDate, relativeTime } from "app/frontend/sway_utils/datetimes";

const parseOrNull = (iso: string | null | undefined): Date | null => {
    if (iso === null || iso === undefined) return null;
    const trimmed = iso.trim();
    if (trimmed === "") return null;
    const d = new Date(trimmed);
    return isValidDate(d) ? d : null;
};

export const failureAge = (iso: string | null | undefined): string | null => {
    const d = parseOrNull(iso);
    return d ? relativeTime(d.toISOString()) : null;
};

export const exactTime = (iso: string | null | undefined): string | null => {
    const d = parseOrNull(iso);
    return d ? formatDateTime(d) : null;
};

export const failureTiming = (iso: string | null | undefined): string | null => {
    const d = parseOrNull(iso);
    return d ? `Failed ${relativeTime(d.toISOString())} — ${formatDateTime(d)}` : null;
};
