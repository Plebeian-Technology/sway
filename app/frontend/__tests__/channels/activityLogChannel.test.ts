import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ActivityLogEntry } from "app/frontend/types/activityLog";

// Grab the handlers object handed to consumer.subscriptions.create, so the test
// can call received() itself.
const { createMock, unsubscribeMock } = vi.hoisted(() => ({
    createMock: vi.fn<(...args: unknown[]) => unknown>(),
    unsubscribeMock: vi.fn<() => void>(),
}));
vi.mock("app/frontend/channels/consumer", () => ({
    default: { subscriptions: { create: (...args: unknown[]) => createMock(...args) } },
}));

const notifyMock = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({ notify: (...args: unknown[]) => notifyMock(...args) }));

import { subscribeActivityLog } from "app/frontend/channels/activityLogChannel";

type ReceivedHandler = (data: { event: string; entry?: ActivityLogEntry }) => void;

const makeEntry = (overrides: Partial<ActivityLogEntry>): ActivityLogEntry => ({
    id: 1,
    event_type: "state_transition",
    severity: "info",
    title: "Stage advanced",
    message: "fetch_bills → extract",
    subject_type: null,
    subject_id: null,
    subject_label: null,
    actor_user_id: null,
    payload: {},
    inspect_query: "",
    created_at: "2026-06-03T00:00:00.000000Z",
    ...overrides,
});

// Subscribe once, then hand back the captured received() handler and a fresh
// onAppend to watch.
const setup = () => {
    createMock.mockReturnValue({ unsubscribe: unsubscribeMock });
    const onAppend = vi.fn<(entry: unknown) => void>();
    subscribeActivityLog("run-123", onAppend);
    const handlers = createMock.mock.calls.at(-1)?.[1] as { received: ReceivedHandler };
    return { received: handlers.received, onAppend };
};

describe("subscribeActivityLog", () => {
    beforeEach(() => {
        createMock.mockReset();
        notifyMock.mockReset();
        unsubscribeMock.mockReset();
    });

    it("does NOT toast for the bill_state_transition per-bill flood but still appends it", () => {
        const { received, onAppend } = setup();
        const entry = makeEntry({ id: 7, event_type: "bill_state_transition" });

        received({ event: "activity_log_entry", entry });

        expect(notifyMock).not.toHaveBeenCalled();
        expect(onAppend).toHaveBeenCalledWith(entry);
    });

    it.each([
        ["state_transition", "info"], // progress of the run itself — the "which stage am I in" signal
        ["org_position_decision", "info"],
        ["summary_regenerate_triggered", "info"],
        ["stage_budget_tripped", "warning"],
        ["stage_failed", "error"],
    ] as const)("toasts and appends for %s (%s)", (event_type, severity) => {
        const { received, onAppend } = setup();
        const entry = makeEntry({ id: 9, event_type, severity });

        received({ event: "activity_log_entry", entry });

        expect(notifyMock).toHaveBeenCalledTimes(1);
        expect(notifyMock.mock.calls[0][0]).toMatchObject({
            id: "activity-log-9",
            level: severity,
            title: entry.title,
        });
        expect(onAppend).toHaveBeenCalledWith(entry);
    });

    it("uses an 8s duration for errors and 5s otherwise", () => {
        const { received } = setup();

        received({ event: "activity_log_entry", entry: makeEntry({ event_type: "stage_failed", severity: "error" }) });
        received({
            event: "activity_log_entry",
            entry: makeEntry({ event_type: "paste_summary_rejected", severity: "warning" }),
        });

        expect(notifyMock.mock.calls[0][0]).toMatchObject({ duration: 8000 });
        expect(notifyMock.mock.calls[1][0]).toMatchObject({ duration: 5000 });
    });

    it("ignores non activity_log_entry events", () => {
        const { received, onAppend } = setup();

        received({ event: "webhook" });

        expect(notifyMock).not.toHaveBeenCalled();
        expect(onAppend).not.toHaveBeenCalled();
    });
});
