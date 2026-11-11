import consumer from "app/frontend/channels/consumer";
import { notify } from "app/frontend/sway_utils";
import type { ActivityLogEntry } from "app/frontend/types/activityLog";

// @lat: [[pipeline-activity-logger-overview#How PipelineActivityLogEntry triggers delivery]]
const TOAST_SUPPRESSED_EVENT_TYPES: ReadonlySet<string> = new Set(["bill_state_transition"]);

export function subscribeActivityLog(runId: string, onAppend: (entry: ActivityLogEntry) => void): () => void {
    const subscription = consumer.subscriptions.create(
        { channel: "PipelineRunChannel", run_id: runId },
        {
            received(data: { event: string; entry?: ActivityLogEntry }) {
                if (data.event === "activity_log_entry" && data.entry) {
                    const entry = data.entry;
                    if (!TOAST_SUPPRESSED_EVENT_TYPES.has(entry.event_type)) {
                        notify({
                            id: `activity-log-${entry.id}`,
                            level: entry.severity,
                            title: entry.title,
                            message: entry.message,
                            duration: entry.severity === "error" ? 8000 : 5000,
                        });
                    }
                    onAppend(entry);
                }
            },
        },
    );
    return () => subscription.unsubscribe();
}
