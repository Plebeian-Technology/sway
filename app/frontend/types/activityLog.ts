export interface ActivityLogEntry {
    id: number;
    event_type: string;
    severity: "info" | "warning" | "error";
    title: string;
    message: string;
    subject_type: string | null;
    subject_id: string | null;
    subject_label: string | null;
    actor_user_id: number | null;
    payload: Record<string, unknown>;
    inspect_query: string;
    // @lat: [[pipeline-activity-log-serialize-entry-quirks#Why created_at is written with iso8601(6), not plain iso8601]]
    created_at: string;
}

export interface ActivityLogProps {
    activity_log_entries: ActivityLogEntry[];
    activity_log_next_cursor: string | null;
    activity_log_has_more: boolean;
}

export type ActivityLogSubjectFilter = "this_bill" | "all_bills";
export type ActivityLogSeverityFilter = "all" | "errors";
export type ActivityLogWindowFilter = "24h" | "7d" | "30d" | "all";
