// @lat: [[bill-creator-pipeline-llm-test-notes#BillCreatorPipelineLlm test notes]]

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// @lat: [[bill-creator-pipeline-llm-test-notes#BillCreatorPipelineLlm test notes]]
vi.mock("app/frontend/components/admin/creator/PerBillGrid", () => ({
    __esModule: true,
    default: () => <div data-testid="section-PerBillGrid">PerBillGrid</div>,
    PerBillGrid: () => <div data-testid="section-PerBillGrid">PerBillGrid</div>,
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorPipelineControls", () => ({
    __esModule: true,
    default: () => <div data-testid="section-BillCreatorPipelineControls">BillCreatorPipelineControls</div>,
}));
vi.mock("app/frontend/components/admin/creator/PipelineProgress", () => ({
    __esModule: true,
    default: () => <div data-testid="section-PipelineProgress">PipelineProgress</div>,
}));
vi.mock("app/frontend/components/admin/creator/ResourceCachePanel", () => ({
    __esModule: true,
    default: () => <div data-testid="section-ResourceCachePanel">ResourceCachePanel</div>,
    ResourceCachePanel: () => <div data-testid="section-ResourceCachePanel">ResourceCachePanel</div>,
}));
// BillCreatorLlmSummary moved to the Summary tab and BillCreatorOrganizations to the Positions
// tab; BillCreatorSummary.test.tsx and BillCreatorPositions.test.tsx cover them now.
vi.mock("app/frontend/components/admin/creator/FetchedBillsPanel", () => ({
    __esModule: true,
    default: () => <div data-testid="section-FetchedBillsPanel">FetchedBillsPanel</div>,
}));
vi.mock("app/frontend/components/admin/creator/ActivityLogPanel", () => ({
    __esModule: true,
    default: () => <div data-testid="section-ActivityLogPanel">ActivityLogPanel</div>,
}));
// SendingServicesPanel calls useConfirm() unconditionally, which throws
// outside a ConfirmProvider. Stubbed to a no-op like TestimonyReport (unmocked, real, but
// renders nothing without testimony data) — this file's locked-order check tracks only
// sections that always render a marker, and this one is orthogonal to that order.
vi.mock("app/frontend/components/admin/creator/SendingServicesPanel", () => ({
    __esModule: true,
    default: () => null,
}));

// ── Stand-ins for the hooks and Inertia ──────────────────────────────────────

const usePageMock = vi.fn<() => unknown>();
// The same two start/stop functions every render — if usePoll returned new ones each
// time, there'd be nothing to check afterward; the polling tests below need them steady.
const startPollingMock = vi.fn<() => void>();
const stopPollingMock = vi.fn<() => void>();
// @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props]]
const usePollOnlyLists: string[][] = [];
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    usePoll: (_interval: number, options: { only: string[] }) => {
        usePollOnlyLists.push(options.only);
        return { start: startPollingMock, stop: stopPollingMock };
    },
    router: { reload: vi.fn<() => void>(), post: vi.fn<(...args: unknown[]) => void>() },
}));

// Every `only:` list the component hands the live connection, captured the same way as
// usePollOnlyLists, so a test can compare the two directly.
const useSubscriptionOnlyLists: (readonly string[])[] = [];
vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: (_runId: string | null, onlyProps: readonly string[]) => {
        useSubscriptionOnlyLists.push(onlyProps);
        return { connected: true, downgraded: false, lastDisconnectedAt: null };
    },
}));

// Imported after the stand-ins, so they take the place of the real children.
import BillCreatorPipelineLlm from "app/frontend/components/admin/creator/BillCreatorPipelineLlm";
import { PIPELINE_LLM_ONLY_PROPS } from "app/frontend/components/admin/creator/pipelineLlmOnlyProps";
// The `?raw` suffix asks Vite for the panel's source as plain text, so a test below can
// confirm nothing imports RunConflictBanner.
import billCreatorPipelineLlmSource from "app/frontend/components/admin/creator/BillCreatorPipelineLlm.tsx?raw";

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    startPollingMock.mockClear();
    stopPollingMock.mockClear();
    usePollOnlyLists.length = 0;
    useSubscriptionOnlyLists.length = 0;
});

// ── Sample data ──────────────────────────────────────────────────────────────

const baseBill = {
    id: 1,
    external_id: "HB001",
    bill_llm_provisioning: {
        generation_status: "completed" as const,
        stale: false,
        stale_change_kind: null,
        stale_change_at: null,
        llm_generated_at: null,
        paste_owns_summary_run: false,
    },
};

const baseRunAllBills = {
    id: 100,
    remote_run_id: "abc-123",
    status: "running" as const,
    kind: "all_bills" as const,
    current_stage: "parse-sections",
    pipeline_run_bills: [
        {
            bill_external_id: "HB001",
            title: "Test bill",
            status: "pending" as const,
            started_at: null,
            finished_at: null,
            error_message: null,
            sort_order: 1,
        },
    ],
    pipeline_run_stages: [
        { status: "succeeded", stage_name: "fetch-bills", position: 1 },
        { status: "pending", stage_name: "extract-text", position: 2 },
    ],
};

function setupPage(overrides: {
    bill?: typeof baseBill | undefined;
    legislation_pipeline_run?: typeof baseRunAllBills | { kind: "single" } | null;
    bill_artifact_mirrors?: unknown[];
}) {
    usePageMock.mockReturnValue({
        props: {
            bill: overrides.bill === undefined ? baseBill : overrides.bill,
            legislation_pipeline_run:
                overrides.legislation_pipeline_run === undefined ? baseRunAllBills : overrides.legislation_pipeline_run,
            bill_artifact_mirrors: overrides.bill_artifact_mirrors ?? [],
        },
    });
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe("BillCreatorPipelineLlm — locked section order", () => {
    it("renders sections in the locked top-to-bottom order when kind === 'all_bills'", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        // The summary and organizations sections now live on the Summary &
        // Positions tab.
        const expectedOrder = [
            "section-PerBillGrid",
            "section-BillCreatorPipelineControls",
            "section-PipelineProgress",
            "section-ResourceCachePanel",
            "section-FetchedBillsPanel",
            "section-ActivityLogPanel",
        ];

        const all = Array.from(document.querySelectorAll("[data-testid^='section-']")).map(
            (el) => el.getAttribute("data-testid")!,
        );
        expect(all).toEqual(expectedOrder);
    });

    it("omits PerBillGrid when kind === 'single'", () => {
        setupPage({
            legislation_pipeline_run: { ...baseRunAllBills, kind: "single" } as unknown as typeof baseRunAllBills,
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(screen.queryByTestId("section-PerBillGrid")).toBeNull();
        const all = Array.from(document.querySelectorAll("[data-testid^='section-']")).map(
            (el) => el.getAttribute("data-testid")!,
        );
        expect(all).toEqual([
            "section-BillCreatorPipelineControls",
            "section-PipelineProgress",
            "section-ResourceCachePanel",
            "section-FetchedBillsPanel",
            "section-ActivityLogPanel",
        ]);
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Where the summary stops and the positions start]]
    it("does NOT render BillCreatorLlmSummary or BillCreatorOrganizations (both moved off this tab)", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        // The real components put these testids on their outermost element.
        expect(screen.queryByTestId("llm-status-badge")).toBeNull();
        expect(screen.queryByTestId("llm-no-bill-selected")).toBeNull();
        // And in the source itself: neither import is left in the file.
        expect(billCreatorPipelineLlmSource).not.toMatch(/from\s+["']\.\/BillCreatorLlmSummary["']/);
        expect(billCreatorPipelineLlmSource).not.toMatch(/from\s+["']\.\/BillCreatorOrganizations["']/);
    });

    it("omits PerBillGrid when legislation_pipeline_run is null", () => {
        setupPage({ legislation_pipeline_run: null });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);
        expect(screen.queryByTestId("section-PerBillGrid")).toBeNull();
    });

    it("uses the locked max-w-5xl single-column container", () => {
        setupPage({});
        const { container } = render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);
        // Check the classes on the outermost element itself, rather than
        // pattern-matching the whole rendered HTML, which would break on any
        // text further down the page.
        const root = container.firstElementChild as HTMLElement | null;
        expect(root).not.toBeNull();
        const classes = root!.className.split(/\s+/);
        expect(classes).toContain("max-w-5xl");
        expect(classes).toContain("mx-auto");
        expect(classes).toContain("flex");
        expect(classes).toContain("flex-col");
        expect(classes).toContain("gap-6");
    });

    // RunConflictBanner belongs to BillCreatorShell, drawn ABOVE the tabs. This panel must
    // not draw or import a second one, or the operator sees it twice.
    it("does NOT import or render RunConflictBanner (banner owned by shell, not panel)", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        // First check: nothing on the page has the banner's role. The banner is
        // built from the Alert component, and none of the stand-ins above draw
        // an Alert.
        expect(document.querySelector('[role="alertdialog"]')).toBeNull();
        // Second check: no section marker belongs to the banner. The fixed order
        // has seven sections and the banner is not one of them.
        expect(screen.queryByTestId("section-RunConflictBanner")).toBeNull();

        // And in the source itself: the `?raw` import gave us the file as text, so any
        // future import or use of the tag fails here without the component even running.
        expect(billCreatorPipelineLlmSource).not.toMatch(/from\s+["'].*RunConflictBanner["']/);
        expect(billCreatorPipelineLlmSource).not.toMatch(/<RunConflictBanner/);
    });
});

// @lat: [[lat.md/explanation/llm-summaries#Stand-downs are reported, not swallowed#The pipeline tab warns before it stands down]]
describe("BillCreatorPipelineLlm — operator-paste notice", () => {
    it("renders the notice, naming Regenerate, when paste_owns_summary_run is true", () => {
        setupPage({
            bill: {
                ...baseBill,
                bill_llm_provisioning: { ...baseBill.bill_llm_provisioning, paste_owns_summary_run: true },
            },
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        const notice = screen.getByTestId("pipeline-operator-paste-notice");
        expect(notice).toBeTruthy();
        expect(notice.textContent).toMatch(/written by a person/i);
        expect(notice.textContent).toMatch(/Run Pipeline will not replace it/i);
        expect(notice.textContent).toMatch(/Regenerate/);
    });

    it("omits the notice when paste_owns_summary_run is false", () => {
        setupPage({
            bill: {
                ...baseBill,
                bill_llm_provisioning: { ...baseBill.bill_llm_provisioning, paste_owns_summary_run: false },
            },
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(screen.queryByTestId("pipeline-operator-paste-notice")).toBeNull();
    });

    it("omits the notice when bill_llm_provisioning is missing entirely", () => {
        setupPage({
            bill: { ...baseBill, bill_llm_provisioning: undefined } as unknown as typeof baseBill,
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(screen.queryByTestId("pipeline-operator-paste-notice")).toBeNull();
    });
});

// The 5s backup poll must STOP once a run finishes — it used to check only
// succeeded/failed/cancelled, so a `partial` or `completed` run polled forever on the
// production Pi.
describe("BillCreatorPipelineLlm — polling gate", () => {
    const renderWithStatus = (status: string) => {
        setupPage({
            legislation_pipeline_run: {
                ...baseRunAllBills,
                status,
            } as unknown as typeof baseRunAllBills,
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);
    };

    it.each(["partial", "completed", "succeeded", "failed", "cancelled"])(
        "stops polling on terminal status '%s'",
        (status) => {
            renderWithStatus(status);
            expect(stopPollingMock).toHaveBeenCalled();
            expect(startPollingMock).not.toHaveBeenCalled();
        },
    );

    it.each(["queued", "running", "summarizing", "awaiting_summary_batch"])(
        "keeps polling on non-terminal status '%s'",
        (status) => {
            renderWithStatus(status);
            expect(startPollingMock).toHaveBeenCalled();
            expect(stopPollingMock).not.toHaveBeenCalled();
        },
    );
});

describe("BillCreatorPipelineLlm — the poll and the live connection refresh the same props", () => {
    // Used to be two separate lists; the poll's shorter one missed 3 of 7 props, leaving the run selector
    // stale until a manual reload. One shared constant now feeds both.
    it("hands usePoll exactly the props PIPELINE_LLM_ONLY_PROPS names", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(usePollOnlyLists.at(-1)).toEqual([...PIPELINE_LLM_ONLY_PROPS]);
    });

    // The assertion above checks the poll's list against the constant it also passes in —
    // it can't fail. This one compares the live-connection hook's actual props against the
    // poll's list instead.
    it("hands the live connection the same props list as the poll", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(useSubscriptionOnlyLists.at(-1)).toEqual(usePollOnlyLists.at(-1));
    });

    // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props]]
    it("refreshes the shell banner's run alongside its own props", () => {
        expect(PIPELINE_LLM_ONLY_PROPS).toContain("active_legislation_pipeline_run");
    });
});

// @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
describe("BillCreatorPipelineLlm — summary-batch notice", () => {
    it("stands the batch notice on the page while the run waits on its batches", () => {
        setupPage({
            legislation_pipeline_run: {
                ...baseRunAllBills,
                status: "awaiting_summary_batch",
                summary_batch: {
                    awaiting: true,
                    batches_total: 3,
                    batches_ingested: 2,
                    items_total: 300,
                    items_succeeded: 199,
                    items_failed: 1,
                    first_submitted_at: null,
                    expires_at: null,
                },
            } as unknown as typeof baseRunAllBills,
        });
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        const notice = screen.getByTestId("pipeline-summary-batch-notice");
        expect(notice.textContent).toMatch(/Chunks read back:\s*2 of 3/);
        expect(notice.textContent).toMatch(/Items returned:\s*200 of 300 submitted/);
    });

    it("omits the batch notice for a run that submitted no batch", () => {
        setupPage({});
        render(<BillCreatorPipelineLlm onCancelRun={vi.fn<(runId: number) => void>()} />);

        expect(screen.queryByTestId("pipeline-summary-batch-notice")).toBeNull();
    });
});
