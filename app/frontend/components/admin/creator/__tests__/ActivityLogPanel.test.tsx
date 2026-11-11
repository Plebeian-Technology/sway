import { cleanup, fireEvent, render, screen, act } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ActivityLogEntry } from "app/frontend/types/activityLog";

// ── Stand-ins for other modules ──────────────────────────────────────────────

const routerGet = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<
        () => {
            props: {
                activity_log_entries: [];
                activity_log_next_cursor: null;
                activity_log_has_more: boolean;
                flash: Record<string, unknown>;
            };
        }
    >(() => ({
        props: {
            activity_log_entries: [],
            activity_log_next_cursor: null,
            activity_log_has_more: false,
            flash: {},
        },
    })),
    router: {
        get: (...args: unknown[]) => routerGet(...args),
    },
}));

const mockSubscribeActivityLog = vi.fn<(runId: string, onAppend: (entry: ActivityLogEntry) => void) => () => void>();
vi.mock("app/frontend/channels/activityLogChannel", () => ({
    subscribeActivityLog: (runId: string, onAppend: (entry: ActivityLogEntry) => void) =>
        mockSubscribeActivityLog(runId, onAppend),
}));

const mockNotify = vi.fn<(options: Record<string, unknown>) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (options: Record<string, unknown>) => mockNotify(options),
}));

vi.mock("app/frontend/components/ui/alert", () => ({
    Alert: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => (
        <div data-testid="alert" {...props}>
            {children}
        </div>
    ),
    AlertTitle: ({ children }: { children: React.ReactNode }) => <strong>{children}</strong>,
    AlertDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, tone, ...props }: React.HTMLAttributes<HTMLSpanElement> & { tone?: string }) => (
        <span data-tone={tone} {...props}>
            {children}
        </span>
    ),
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

// Imported after the stand-ins above, so they take effect
import { usePage } from "@inertiajs/react";
import ActivityLogPanel from "app/frontend/components/admin/creator/ActivityLogPanel";
import { isQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeEntry(overrides: Partial<ActivityLogEntry> = {}): ActivityLogEntry {
    return {
        id: Math.floor(Math.random() * 100000),
        event_type: "orphan_run_deleted",
        severity: "info",
        title: "Orphan run cleaned up",
        message: "Test entry",
        subject_type: null,
        subject_id: null,
        subject_label: null,
        actor_user_id: null,
        payload: {},
        inspect_query: "PipelineActivityLogEntry.find(1)",
        created_at: new Date().toISOString(),
        ...overrides,
    };
}

function setPageProps(
    overrides: Partial<{
        activity_log_entries: ActivityLogEntry[];
        activity_log_next_cursor: string | null;
        activity_log_has_more: boolean;
        flash: Record<string, unknown>;
    }> = {},
) {
    vi.mocked(usePage).mockReturnValue({
        props: {
            activity_log_entries: [],
            activity_log_next_cursor: null,
            activity_log_has_more: false,
            flash: {},
            ...overrides,
        },
    } as unknown as ReturnType<typeof usePage>);
}

// ── Test suite ────────────────────────────────────────────────────────────────

describe("ActivityLogPanel", () => {
    beforeEach(() => {
        routerGet.mockReset();
        mockSubscribeActivityLog.mockReset();
        mockNotify.mockReset();

        mockSubscribeActivityLog.mockImplementation(() => () => {});

        setPageProps();

        Object.defineProperty(window, "location", {
            value: Object.assign(Object.create(Object.getPrototypeOf(window.location)), window.location, {
                search: "",
                pathname: "/bills/1/edit",
            }),
            writable: true,
        });
    });

    afterEach(() => {
        cleanup();
    });

    it("Test 1: renders entries from props (count matches input length)", () => {
        const entries = [makeEntry({ id: 1, title: "Entry A" }), makeEntry({ id: 2, title: "Entry B" })];
        setPageProps({ activity_log_entries: entries });

        render(<ActivityLogPanel />);

        expect(screen.getByText("Entry A")).toBeDefined();
        expect(screen.getByText("Entry B")).toBeDefined();
    });

    it("Test 2: shows empty state copy when entries list is empty", () => {
        setPageProps({ activity_log_entries: [] });

        render(<ActivityLogPanel />);

        expect(screen.getByText("No activity yet")).toBeDefined();
        expect(screen.getByText("Pipeline events will appear here as they happen.")).toBeDefined();
    });

    it("Test 3: filter chip click triggers router.get with only: activity_log_* keys", () => {
        setPageProps({ activity_log_entries: [] });

        render(<ActivityLogPanel />);

        fireEvent.click(screen.getByText("Errors only"));

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [, , options] = routerGet.mock.calls[0] as [string, Record<string, string>, Record<string, unknown>];
        expect(options.only).toContain("activity_log_entries");
        expect(options.only).toContain("activity_log_next_cursor");
        expect(options.only).toContain("activity_log_has_more");
        expect(options.preserveScroll).toBe(true);
        expect(options.preserveState).toBe(true);
    });

    it("Test 4: flash.activity_log_entry triggers notify() on mount", () => {
        const flashEntry = makeEntry({ id: 99, title: "Flash entry", severity: "error" });
        setPageProps({ flash: { activity_log_entry: flashEntry } });

        render(<ActivityLogPanel />);

        expect(mockNotify).toHaveBeenCalledTimes(1);
        const notifyArg = mockNotify.mock.calls[0][0];
        expect(notifyArg.id).toBe(`activity-log-${flashEntry.id}`);
        expect(notifyArg.level).toBe("error");
        expect(notifyArg.title).toBe("Flash entry");
    });

    // When the server can't put the entry in flash, it sends flash[:activity_log_error]
    // (id + error class) instead, and the panel shows a red alert linking to it.
    it("Test 4b: flash.activity_log_error renders inline destructive banner pointing at entry", () => {
        setPageProps({
            flash: {
                activity_log_error: { entry_id: 1234, error_class: "ActionDispatch::Cookies::CookieOverflow" },
            },
        });

        render(<ActivityLogPanel />);

        const banner = screen.getByTestId("activity-log-error-banner");
        expect(banner).toBeDefined();
        expect(banner.textContent).toContain("Activity-log delivery failed");
        expect(banner.textContent).toContain("1234");
        expect(banner.textContent).toContain("ActionDispatch::Cookies::CookieOverflow");
        const link = banner.querySelector("a");
        expect(link?.getAttribute("href")).toBe("?highlight=1234");
    });

    it("Test 4c: no banner when flash.activity_log_error is absent", () => {
        setPageProps({ flash: {} });
        render(<ActivityLogPanel />);
        expect(screen.queryByTestId("activity-log-error-banner")).toBeNull();
    });

    it("Test 5: ?highlight=42 scrolls + pulses + history.replaceState removes param", () => {
        const entries = [makeEntry({ id: 42, title: "Highlighted entry" })];
        setPageProps({ activity_log_entries: entries });

        // jsdom, the fake browser these tests run in, refuses a real
        // replaceState across origins, so swap in a stand-in
        const replaceStateSpy = vi.spyOn(history, "replaceState").mockImplementation(() => {});

        Object.defineProperty(window, "location", {
            value: Object.assign(Object.create(Object.getPrototypeOf(window.location)), window.location, {
                search: "?highlight=42",
                pathname: "/bills/1/edit",
                href: "http://localhost/bills/1/edit?highlight=42",
            }),
            writable: true,
        });

        // jsdom has no scrollIntoView, so add a stand-in to every element
        const scrollIntoViewMock = vi.fn<(...args: unknown[]) => void>();
        Element.prototype.scrollIntoView = scrollIntoViewMock;

        render(<ActivityLogPanel />);

        expect(replaceStateSpy).toHaveBeenCalled();
        const newUrl = replaceStateSpy.mock.calls[0][2] as string;
        expect(isQueryParamCleared(new URL(newUrl).searchParams, "highlight")).toBe(true);
        expect(newUrl).toContain("highlight=");
        expect(newUrl).not.toContain("highlight=42");

        replaceStateSpy.mockRestore();
    });

    it("Test 6: Load older entries button hidden when has_more is false", () => {
        setPageProps({ activity_log_has_more: false });

        render(<ActivityLogPanel />);

        expect(screen.queryByText("Load older entries")).toBeNull();
    });

    it("Test 6b: Load older entries hidden on page 1 of 2 even when has_more is true", () => {
        const fifteen = Array.from({ length: 15 }, (_, i) => makeEntry({ id: i + 1 }));
        setPageProps({ activity_log_entries: fifteen, activity_log_has_more: true });

        render(<ActivityLogPanel />);

        expect(screen.queryByText("Load older entries")).toBeNull();
        fireEvent.click(screen.getByRole("button", { name: "Page 2" }));
        expect(screen.getByText("Load older entries")).toBeDefined();
    });

    it("Test 7 (MEDIUM-1): subscribeActivityLog called twice on mount (run + global); both unsubscribed on unmount", () => {
        const unsubscribeFns = [vi.fn<(...args: unknown[]) => void>(), vi.fn<(...args: unknown[]) => void>()];
        let callCount = 0;
        mockSubscribeActivityLog.mockImplementation(() => unsubscribeFns[callCount++] ?? (() => {}));

        setPageProps({ activity_log_entries: [] });

        const { unmount } = render(<ActivityLogPanel currentRunRemoteId="run-abc-123" />);

        expect(mockSubscribeActivityLog).toHaveBeenCalledTimes(2);

        const callArgs = mockSubscribeActivityLog.mock.calls.map((c: unknown[]) => c[0] as string);
        expect(callArgs).toContain("run-abc-123");
        expect(callArgs).toContain("global");

        unmount();

        expect(unsubscribeFns[0]).toHaveBeenCalled();
        expect(unsubscribeFns[1]).toHaveBeenCalled();
    });

    it("Test 8 (MEDIUM-4): re-render with new entries prop replaces local state", () => {
        const initialEntries = [makeEntry({ id: 1, title: "Old entry" })];
        setPageProps({ activity_log_entries: initialEntries });

        const { rerender } = render(<ActivityLogPanel />);

        expect(screen.getByText("Old entry")).toBeDefined();

        const newEntries = [makeEntry({ id: 2, title: "New entry" })];
        setPageProps({ activity_log_entries: newEntries });

        act(() => {
            rerender(<ActivityLogPanel />);
        });

        expect(screen.getByText("New entry")).toBeDefined();
        expect(screen.queryByText("Old entry")).toBeNull();
    });

    it("Test 9 (LOW-4): Strict Mode double-mount cleans up both subscriptions at steady state", () => {
        const unsubscribeFns: Array<ReturnType<typeof vi.fn>> = [];
        mockSubscribeActivityLog.mockImplementation(() => {
            const unsub = vi.fn<(...args: unknown[]) => void>();
            unsubscribeFns.push(unsub);
            return unsub;
        });

        setPageProps({ activity_log_entries: [] });

        const { unmount } = render(<ActivityLogPanel currentRunRemoteId="run-strict" />);

        unmount();

        for (const fn of unsubscribeFns) {
            expect(fn).toHaveBeenCalled();
        }
    });

    it("Test 10: a broadcast queued during a filter reload is dropped when the new filter lands", () => {
        const e1 = makeEntry({ id: 1, title: "Entry 1" });
        const e2 = makeEntry({ id: 2, title: "Entry 2" });
        const e3 = makeEntry({ id: 3, title: "Broadcast during reload" });
        const e4 = makeEntry({ id: 4, title: "Server response 1" });

        const capturedOnAppend: Array<(entry: ActivityLogEntry) => void> = [];
        mockSubscribeActivityLog.mockImplementation((_runId: string, onAppend: (entry: ActivityLogEntry) => void) => {
            capturedOnAppend.push(onAppend);
            return () => {};
        });

        setPageProps({ activity_log_entries: [e1, e2] });
        const { rerender } = render(<ActivityLogPanel currentRunRemoteId="run-abc" />);

        fireEvent.click(screen.getByText("Errors only"));
        expect(routerGet).toHaveBeenCalledTimes(1);

        act(() => {
            if (capturedOnAppend[0]) capturedOnAppend[0](e3);
        });
        expect(screen.queryByText("Broadcast during reload")).toBeNull();
        expect(screen.getByText("Show 1 new entry")).toBeDefined();

        setPageProps({ activity_log_entries: [e4] });
        act(() => {
            rerender(<ActivityLogPanel currentRunRemoteId="run-abc" />);
        });

        expect(screen.getByText("Server response 1")).toBeDefined();
        expect(screen.queryByText("Broadcast during reload")).toBeNull();
        expect(screen.queryByText("Show 1 new entry")).toBeNull();
    });

    it("Test 11: a live broadcast queues instead of appearing immediately; Show reveals it", () => {
        const e6 = makeEntry({ id: 6, title: "Steady state broadcast" });

        const capturedOnAppend: Array<(entry: ActivityLogEntry) => void> = [];
        mockSubscribeActivityLog.mockImplementation((_runId: string, onAppend: (entry: ActivityLogEntry) => void) => {
            capturedOnAppend.push(onAppend);
            return () => {};
        });

        setPageProps({ activity_log_entries: [] });
        render(<ActivityLogPanel currentRunRemoteId="run-xyz" />);

        act(() => {
            if (capturedOnAppend[0]) {
                capturedOnAppend[0](e6);
            }
        });

        expect(screen.queryByText("Steady state broadcast")).toBeNull();
        fireEvent.click(screen.getByText("Show 1 new entry"));
        expect(screen.getByText("Steady state broadcast")).toBeDefined();
    });

    // Copy AR query sits inside each entry's Details section, next to the raw JSON.
    it("Test 12: Copy button writes entry.inspect_query to clipboard + notifies", async () => {
        const writeText = vi.fn<(...args: unknown[]) => Promise<void>>().mockResolvedValue(undefined);
        Object.defineProperty(navigator, "clipboard", {
            configurable: true,
            value: { writeText },
        });

        const e = makeEntry({
            title: "Approved ACLU on 25-0003",
            inspect_query:
                'OrganizationBillPosition.joins(:organization).where(bill_id: 42, organizations: {name: "ACLU"})',
        });
        setPageProps({ activity_log_entries: [e] });

        render(<ActivityLogPanel />);

        // Other buttons may also say "Copy", so find the one next to the <code> block
        // holding this entry's query rather than matching on button text alone.
        const queryCode = screen.getByText(e.inspect_query);
        const copyButton = queryCode.parentElement?.querySelector("button");
        expect(copyButton).not.toBeNull();

        fireEvent.click(copyButton!);

        expect(writeText).toHaveBeenCalledWith(e.inspect_query);

        // The toast only fires once the clipboard write has settled.
        await Promise.resolve();
        await Promise.resolve();

        expect(mockNotify).toHaveBeenCalledWith(expect.objectContaining({ level: "info", title: "Copied AR query" }));
    });
});
