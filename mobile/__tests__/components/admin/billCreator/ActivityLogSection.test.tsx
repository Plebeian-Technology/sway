import React from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";

const mockApiGet = jest.fn();
jest.mock("../../../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockApiGet(...args),
    },
}));

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import ActivityLogSection, {
    type ActivityLogEntry,
} from "../../../../src/components/admin/billCreator/ActivityLogSection";

const entry = (id: number, overrides: Partial<ActivityLogEntry> = {}): ActivityLogEntry => ({
    id,
    event_type: "stage_finished",
    severity: "info",
    title: `Event ${id}`,
    message: "",
    subject_type: null,
    subject_id: null,
    subject_label: null,
    actor_user_id: null,
    payload: {},
    inspect_query: "",
    created_at: "2026-11-24T11:00:00.000000Z",
    ...overrides,
});

const open = () => fireEvent.press(screen.getByTestId("admin-activity-log-toggle"));

// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
describe("ActivityLogSection", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => jest.useRealTimers());

    it("shows severity, title, subject, actor, age and message", () => {
        render(
            <ActivityLogSection
                billId={42}
                entries={[
                    entry(1, {
                        severity: "error",
                        title: "Fetch failed",
                        subject_label: "Bill 25-0001",
                        actor_user_id: 9,
                        message: "Timed out",
                    }),
                    entry(2),
                ]}
                nextCursor={null}
                hasMore={false}
            />,
        );
        open();

        const first = screen.getByTestId("admin-activity-log-entry-1");
        expect(first).toHaveTextContent(/error/);
        expect(first).toHaveTextContent(/Fetch failed/);
        expect(first).toHaveTextContent(/Bill 25-0001/);
        expect(first).toHaveTextContent(/User #9/);
        expect(first).toHaveTextContent(/1h ago/);
        expect(first).toHaveTextContent(/Timed out/);
        expect(screen.getByTestId("admin-activity-log-entry-2")).toHaveTextContent(/System/);
    });

    it("keeps the payload and inspect query behind a details toggle", () => {
        render(
            <ActivityLogSection
                billId={42}
                entries={[
                    entry(1, { payload: { stage: "fetch-law" }, inspect_query: "PipelineActivityLogEntry.find(1)" }),
                ]}
                nextCursor={null}
                hasMore={false}
            />,
        );
        open();
        expect(screen.queryByTestId("admin-activity-log-details-1")).toBeNull();

        fireEvent.press(screen.getByTestId("admin-activity-log-details-toggle-1"));

        expect(screen.getByTestId("admin-activity-log-details-1")).toHaveTextContent(/"stage": "fetch-law"/);
        expect(screen.getByTestId("admin-activity-log-details-1")).toHaveTextContent(
            /PipelineActivityLogEntry\.find\(1\)/,
        );
    });

    it("says there is no activity when the log is empty", () => {
        render(<ActivityLogSection billId={42} entries={[]} nextCursor={null} hasMore={false} />);
        open();

        expect(screen.getByText("No activity yet")).toBeTruthy();
        expect(screen.getByText("Pipeline events will appear here as they happen.")).toBeTruthy();
        expect(screen.queryByTestId("admin-activity-log-load-more")).toBeNull();
    });

    it("loads older entries with the next cursor and appends them", async () => {
        mockApiGet.mockResolvedValue({
            activity_log_entries: [entry(2), entry(3)],
            activity_log_next_cursor: null,
            activity_log_has_more: false,
        });
        render(<ActivityLogSection billId={42} entries={[entry(1)]} nextCursor="abc_-" hasMore />);
        open();

        fireEvent.press(screen.getByTestId("admin-activity-log-load-more"));

        await waitFor(() => expect(mockApiGet).toHaveBeenCalledWith("/admin/bill_creator/42/pipeline?cursor=abc_-"));
        expect(await screen.findByTestId("admin-activity-log-entry-3")).toBeTruthy();
        expect(screen.getByTestId("admin-activity-log-entry-1")).toBeTruthy();
        expect(screen.queryByTestId("admin-activity-log-load-more")).toBeNull();
    });

    it("keeps paging with the cursor each response returns", async () => {
        mockApiGet
            .mockResolvedValueOnce({
                activity_log_entries: [entry(2)],
                activity_log_next_cursor: "second",
                activity_log_has_more: true,
            })
            .mockResolvedValueOnce({
                activity_log_entries: [entry(3)],
                activity_log_next_cursor: null,
                activity_log_has_more: false,
            });
        render(<ActivityLogSection billId={null} entries={[entry(1)]} nextCursor="first" hasMore />);
        open();

        fireEvent.press(screen.getByTestId("admin-activity-log-load-more"));
        await screen.findByTestId("admin-activity-log-entry-2");
        fireEvent.press(screen.getByTestId("admin-activity-log-load-more"));
        await screen.findByTestId("admin-activity-log-entry-3");

        expect(mockApiGet).toHaveBeenNthCalledWith(1, "/admin/bill_creator/new?bill_creator_tab=pipeline&cursor=first");
        expect(mockApiGet).toHaveBeenNthCalledWith(
            2,
            "/admin/bill_creator/new?bill_creator_tab=pipeline&cursor=second",
        );
    });

    it("shows the error and keeps the entries when loading older entries fails", async () => {
        mockApiGet.mockRejectedValue(new Error("Offline"));
        render(<ActivityLogSection billId={42} entries={[entry(1)]} nextCursor="abc" hasMore />);
        open();

        fireEvent.press(screen.getByTestId("admin-activity-log-load-more"));

        expect(await screen.findByTestId("admin-activity-log-load-more-error")).toHaveTextContent(/Offline/);
        expect(screen.getByTestId("admin-activity-log-entry-1")).toBeTruthy();
        expect(screen.getByTestId("admin-activity-log-load-more")).toBeTruthy();
    });

    it("does not show an entry twice when a refresh returns one already loaded", async () => {
        mockApiGet.mockResolvedValue({
            activity_log_entries: [entry(2)],
            activity_log_next_cursor: null,
            activity_log_has_more: false,
        });
        const { rerender } = render(<ActivityLogSection billId={42} entries={[entry(1)]} nextCursor="abc" hasMore />);
        open();
        fireEvent.press(screen.getByTestId("admin-activity-log-load-more"));
        await screen.findByTestId("admin-activity-log-entry-2");

        rerender(<ActivityLogSection billId={42} entries={[entry(2), entry(1)]} nextCursor="abc" hasMore />);

        expect(screen.getAllByTestId("admin-activity-log-entry-2")).toHaveLength(1);
    });
});
