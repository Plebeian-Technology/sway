import { logDev } from "app/frontend/sway_utils";

export type OfflineEventName =
    | "offline_session_started"
    | "offline_vote_attempt_blocked"
    | "sw_update_prompt_shown"
    | "sw_update_prompt_accepted";

// @lat: [[offline-telemetry#Why offline events never leave the browser]]
export function trackOfflineEvent(name: OfflineEventName, attrs: Record<string, unknown> = {}): void {
    logDev("[offline-telemetry]", name, attrs);
}
