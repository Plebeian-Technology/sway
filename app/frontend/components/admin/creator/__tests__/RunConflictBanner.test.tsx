import { render, screen, fireEvent, act } from "@testing-library/react";
import { usePage } from "@inertiajs/react";
import RunConflictBanner from "app/frontend/components/admin/creator/RunConflictBanner";

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: { active_legislation_pipeline_run: unknown } }>(),
}));

const onCancelRun = vi.fn<(runId: number) => void>();

const mockUsePage = (run: unknown) =>
    (usePage as ReturnType<typeof vi.fn>).mockReturnValue({ props: { active_legislation_pipeline_run: run } });

describe("RunConflictBanner", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        onCancelRun.mockClear();
        vi.useFakeTimers();
    });
    afterEach(() => vi.useRealTimers());

    it("returns null when active_legislation_pipeline_run prop is null", () => {
        mockUsePage(null);
        const { container } = render(<RunConflictBanner onCancelRun={onCancelRun} />);
        expect(container.firstChild).toBeNull();
    });

    // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What the run-conflict banner counts as finished]]
    it.each(["completed", "failed", "cancelled", "succeeded", "partial"])(
        "returns null when status is terminal (%s)",
        (status) => {
            // cancelled_at is left out on purpose: the server never sends it.
            mockUsePage({ id: 7, status, current_stage: null, started_at: null, bill_external_id: null });
            const { container } = render(<RunConflictBanner onCancelRun={onCancelRun} />);
            expect(container.firstChild).toBeNull();
        },
    );

    // @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#RunConflictBanner's test for which column decides "has the run started"]]
    describe("which column decides whether the run has started", () => {
        it("says queued when the status is queued and no stage is written yet", () => {
            mockUsePage({
                id: 7,
                status: "queued",
                current_stage: null,
                started_at: null,
                bill_external_id: null,
            });
            render(<RunConflictBanner onCancelRun={onCancelRun} />);
            expect(screen.getByTestId("run-conflict-banner")).toBeInTheDocument();
            expect(
                screen.getByText(/Pipeline run 7 is queued\. It starts when a worker picks it up\./),
            ).toBeInTheDocument();
            expect(screen.getByText("Pipeline run queued")).toBeInTheDocument();
        });

        // @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#RunConflictBanner's test for an unvalidated null status]]
        it("says queued, not in progress, when the status is unknown", () => {
            mockUsePage({
                id: 7,
                status: null,
                current_stage: null,
                started_at: null,
                bill_external_id: null,
            });
            render(<RunConflictBanner onCancelRun={onCancelRun} />);
            expect(screen.getByTestId("run-conflict-banner")).toBeInTheDocument();
            expect(screen.getByText("Pipeline run queued")).toBeInTheDocument();
            expect(screen.queryByText(/is in progress/)).toBeNull();
        });

        it("says in progress when the status is running and no stage is written yet", () => {
            mockUsePage({
                id: 7,
                status: "running",
                current_stage: null,
                started_at: null,
                bill_external_id: null,
            });
            render(<RunConflictBanner onCancelRun={onCancelRun} />);
            expect(screen.getByText(/Pipeline run 7 \(all bills\) is in progress/)).toBeInTheDocument();
            expect(screen.getByText("Pipeline run in progress")).toBeInTheDocument();
            expect(screen.queryByText(/is queued/)).toBeNull();
        });
    });

    it("renders running copy with bill_external_id and HH:MM start time", () => {
        mockUsePage({
            id: 42,
            status: "running",
            current_stage: "extract-text",
            started_at: "2026-05-05T13:42:00Z",
            bill_external_id: "21-0123",
        });
        render(<RunConflictBanner onCancelRun={onCancelRun} />);
        expect(screen.getByText(/Pipeline run 42 \(bill 21-0123\) is in progress/)).toBeInTheDocument();
        // The clock format changes from one locale to another, so check only
        // the parts that never change:
        expect(screen.getByText(/Cancel to start a new run\./)).toBeInTheDocument();
    });

    // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What the run-conflict banner counts as finished]]
    describe("a run nobody is working on", () => {
        const abandonedRun = {
            id: 1,
            status: "summarizing",
            current_stage: "summarize-bill",
            started_at: "2026-05-05T13:42:00Z",
            bill_external_id: null,
            abandoned: true,
        };

        it("says it stopped, not that it is in progress", () => {
            mockUsePage(abandonedRun);
            render(<RunConflictBanner onCancelRun={onCancelRun} />);

            expect(screen.getByText("Pipeline run left unfinished")).toBeInTheDocument();
            expect(screen.getByText(/nothing is working on it now/)).toBeInTheDocument();
            expect(screen.queryByText(/is in progress/)).toBeNull();
        });

        it("names what it costs and what clearing it buys", () => {
            mockUsePage(abandonedRun);
            render(<RunConflictBanner onCancelRun={onCancelRun} />);

            expect(screen.getByText(/holding the Run button off/)).toBeInTheDocument();
            expect(screen.getByText(/leaves the run resumable/)).toBeInTheDocument();
        });

        it("offers to clear it rather than to cancel it", async () => {
            mockUsePage(abandonedRun);
            render(<RunConflictBanner onCancelRun={onCancelRun} />);
            const btn = screen.getByTestId("btn-banner-cancel");

            expect(btn).toHaveTextContent("Clear this run");
            await act(() => fireEvent.click(btn));
            expect(btn).toHaveTextContent("Tap again to clear");
            await act(() => fireEvent.click(btn));
            expect(onCancelRun).toHaveBeenCalledExactlyOnceWith(1);
        });

        // Absent is not abandoned. The channel deltas do not carry the field, and a first render
        // after a redirect must not accuse a healthy run of having stopped.
        it.each([undefined, null, false])("keeps the ordinary wording when abandoned is %s", (abandoned) => {
            mockUsePage({ ...abandonedRun, status: "running", abandoned });
            render(<RunConflictBanner onCancelRun={onCancelRun} />);

            expect(screen.getByText("Pipeline run in progress")).toBeInTheDocument();
            expect(screen.getByTestId("btn-banner-cancel")).toHaveTextContent("Cancel run");
        });
    });

    it("two-tap Cancel: first tap arms, second tap hands the run id to onCancelRun", async () => {
        mockUsePage({
            id: 7,
            status: "running",
            current_stage: "extract-text",
            started_at: "2026-05-05T13:42:00Z",
            bill_external_id: null,
        });
        render(<RunConflictBanner onCancelRun={onCancelRun} />);
        const btn = screen.getByTestId("btn-banner-cancel");

        // First tap: asks for confirmation
        await act(() => fireEvent.click(btn));
        expect(screen.getByText("Tap again to cancel")).toBeInTheDocument();
        expect(onCancelRun).not.toHaveBeenCalled();

        // Second tap: hands off to the caller, which decides whether the unsaved-changes guard
        // applies — this component no longer calls router.delete itself.
        await act(() => fireEvent.click(btn));
        expect(onCancelRun).toHaveBeenCalledExactlyOnceWith(7);
    });
});
