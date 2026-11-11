import type {
    ActivityLogSeverityFilter,
    ActivityLogSubjectFilter,
    ActivityLogWindowFilter,
} from "app/frontend/types/activityLog";

interface ICurrentFilters {
    subject: ActivityLogSubjectFilter;
    severity: ActivityLogSeverityFilter;
    window: ActivityLogWindowFilter;
}

// @lat: [[activity-log-stream#Memoized rows and default-omitting filter URLs]]
export function buildFilterParams(
    current: ICurrentFilters,
    overrides: Partial<ICurrentFilters>,
): Record<string, string> {
    const subject = overrides.subject ?? current.subject;
    const severity = overrides.severity ?? current.severity;
    const window_ = overrides.window ?? current.window;
    const params: Record<string, string> = {};
    if (subject !== "all_bills") params.subject = subject;
    if (severity !== "all") params.severity = severity;
    if (window_ !== "7d") params.window = window_;
    return params;
}

export function chipClass(active: boolean) {
    return active ? "ring-2 ring-primary bg-primary/8 text-primary font-semibold" : "";
}
