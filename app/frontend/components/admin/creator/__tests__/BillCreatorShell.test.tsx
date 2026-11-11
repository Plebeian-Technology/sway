import { fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PendingVisit } from "@inertiajs/core";
import {
    registerQueryParamNavigationCarry,
    unregisterQueryParamNavigationCarry,
} from "app/frontend/sway_utils/queryParamNavigationCarry";

const { routerVisit, routerGet, routerOn, getOutgoingVisitUrl } = vi.hoisted(() => {
    type Listener = (event: { detail: { visit: PendingVisit } }) => void;
    const listeners: Record<string, Listener[]> = {};
    let lastUrl = "";

    const onFn = vi.fn<(event: string, callback: Listener) => () => void>((event: string, callback: Listener) => {
        listeners[event] = listeners[event] || [];
        listeners[event].push(callback);
        return () => {
            listeners[event] = listeners[event].filter((cb) => cb !== callback);
        };
    });

    const visitFn = vi.fn<(url: string, options?: Record<string, unknown>) => void>(
        (url: string, options?: Record<string, unknown>) => {
            const origin =
                typeof window !== "undefined" && window.location?.origin ? window.location.origin : "http://localhost";
            const destinationUrl = new URL(url, origin);
            if (options?.data && typeof options.data === "object") {
                for (const [key, value] of Object.entries(options.data as Record<string, unknown>)) {
                    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
                        destinationUrl.searchParams.set(key, String(value));
                    }
                }
            }
            const visit = {
                url: destinationUrl,
                method: "get",
                data: options?.data ?? {},
                preserveScroll: Boolean(options?.preserveScroll),
            } as unknown as PendingVisit;

            const beforeListeners = listeners["before"] || [];
            for (const listener of beforeListeners) {
                listener({ detail: { visit } });
            }
            lastUrl = (visit.url instanceof URL ? visit.url : new URL(visit.url, origin)).toString();
        },
    );

    const getFn = vi.fn<(url: string, data?: unknown, options?: Record<string, unknown>) => void>();

    return {
        routerVisit: visitFn,
        routerGet: getFn,
        routerOn: onFn,
        getOutgoingVisitUrl: () => (lastUrl ? new URL(lastUrl) : null),
    };
});

const mockPageProps: { bill?: { id?: number }; bills?: unknown[] } = {
    bill: { id: 42 },
    bills: [],
};

vi.mock("@inertiajs/react", () => ({
    router: { visit: routerVisit, get: routerGet, on: routerOn },
    usePage: () => ({ props: mockPageProps }),
}));

// @lat: [[bill-creator-shell#Why only the tab container is tested in the shell test]]
vi.mock("app/frontend/components/admin/creator/BillCreatorAccordions", () => ({
    default: ({ setCreatorDirty }: { setCreatorDirty: (next: boolean) => void }) => (
        <button type="button" data-testid="make-creator-dirty" onClick={() => setCreatorDirty(true)}>
            edit the bill form
        </button>
    ),
}));
vi.mock("app/frontend/components/admin/creator/BillSchedule", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/BillCreatorPipelineLlm", () => ({
    default: () => (
        <div>
            <RunSelector
                runs={[
                    {
                        id: 77,
                        status: "succeeded",
                        kind: "all_bills",
                        bill_external_id: null,
                        created_at: null,
                        completed_at: null,
                    },
                    {
                        id: 99,
                        status: "failed",
                        kind: "single",
                        bill_external_id: "HB0001",
                        created_at: null,
                        completed_at: null,
                    },
                ]}
                currentRunId={77}
            />
        </div>
    ),
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorSummary", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/BillCreatorPositions", () => ({
    default: ({ setCreatorDirty }: { setCreatorDirty?: (next: boolean) => void }) => (
        <button type="button" data-testid="make-positions-dirty" onClick={() => setCreatorDirty?.(true)}>
            edit positions form
        </button>
    ),
}));
vi.mock("app/frontend/components/admin/creator/RunConflictBanner", () => ({ default: () => <div /> }));
vi.mock("app/frontend/components/admin/creator/AdminSwayLocaleSelector", () => ({
    default: ({ onSwayLocaleChange }: { onSwayLocaleChange?: (id: number) => void }) => (
        <div>
            <button type="button" data-testid="pick-locale-2" onClick={() => onSwayLocaleChange?.(2)}>
                Change to Locale 2
            </button>
            <button type="button" data-testid="pick-locale-3" onClick={() => onSwayLocaleChange?.(3)}>
                Change to Locale 3
            </button>
        </div>
    ),
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorPicker", () => ({
    default: ({
        onValueChange,
        localeSelector,
    }: {
        onValueChange: (next: string) => void;
        localeSelector?: React.ReactNode;
    }) => (
        <div>
            {localeSelector}
            <button type="button" data-testid="pick-the-sentinel" onClick={() => onValueChange("new")}>
                All Bills
            </button>
            <button type="button" data-testid="pick-existing-bill-99" onClick={() => onValueChange("99")}>
                Pick Bill 99
            </button>
            <button type="button" data-testid="pick-existing-bill-101" onClick={() => onValueChange("101")}>
                Pick Bill 101
            </button>
        </div>
    ),
    NEW_BILL_VALUE: "new",
}));

import BillCreatorShell from "app/frontend/components/admin/creator/BillCreatorShell";
import RunSelector from "app/frontend/components/admin/creator/RunSelector";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { isQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";

beforeEach(() => {
    registerQueryParamNavigationCarry();
    mockPageProps.bill = { id: 42 };
    mockPageProps.bills = [];
    routerVisit.mockClear();
    routerGet.mockClear();
    routerGet.mockImplementation((url: string) => {
        window.history.pushState({}, "", url);
    });
    window.history.pushState({}, "", "/admin/bill_creator/42/creator");
});

afterEach(() => {
    unregisterQueryParamNavigationCarry();
});

// @lat: [[bill-creator-shell#Why the unsaved-changes prompt guards every tab]]
describe("BillCreatorShell — the unsaved-changes prompt", () => {
    // mouseDown, not click: a Radix tab trigger selects on mousedown, which fireEvent.click
    // never sends — a click here would leave the tab unchanged and pass every assertion
    // vacuously.
    const selectSummaryTab = () => fireEvent.mouseDown(screen.getByText("Summary"));
    const selectPositionsTab = () => fireEvent.mouseDown(screen.getByText("Positions"));

    const renderShell = () => {
        routerVisit.mockClear();
        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("make-creator-dirty"));
    };

    it("asks before carrying unsaved Bill-form edits into the Summary tab", () => {
        renderShell();

        selectSummaryTab();

        expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
        expect(routerVisit).not.toHaveBeenCalled();
    });

    // The other side of the wire: with nothing unsaved the tab change goes
    // straight through, so the example above cannot pass on a shell that simply
    // prompts every time.
    it("switches straight to the Summary tab when nothing is unsaved", () => {
        routerVisit.mockClear();
        render(<BillCreatorShell tabKey={ETab.Creator} />);

        selectSummaryTab();

        expect(screen.queryByText("Unsaved changes")).toBeNull();
        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/summary", {
            data: { bill_creator_tab: "summary" },
            preserveScroll: true,
        });
    });

    // The guarded set is derived from ETab rather than written out here, so a tab
    // added without a guard would pass every example above.
    // @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
    it("asks before carrying unsaved Bill-form edits into the Positions tab", () => {
        renderShell();

        selectPositionsTab();

        expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
        expect(routerVisit).not.toHaveBeenCalled();
    });

    it("switches straight to the Positions tab when nothing is unsaved", () => {
        routerVisit.mockClear();
        render(<BillCreatorShell tabKey={ETab.Creator} />);

        selectPositionsTab();

        expect(screen.queryByText("Unsaved changes")).toBeNull();
        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/positions", {
            data: { bill_creator_tab: "positions" },
            preserveScroll: true,
        });
    });

    it("asks before leaving unsaved Positions-tab edits for the Creator tab", () => {
        routerVisit.mockClear();
        render(<BillCreatorShell tabKey={ETab.Positions} />);
        fireEvent.click(screen.getByTestId("make-positions-dirty"));

        fireEvent.mouseDown(screen.getByText("Bill Creator"));

        expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
        expect(routerVisit).not.toHaveBeenCalled();
    });
});

// @lat: [[bill-creator-shell#The Bill Creator shell#Why the tab survives picking a different bill]]
describe("BillCreatorShell — picking the All Bills sentinel", () => {
    it("keeps the operator on the Pipeline tab", () => {
        window.history.pushState({}, "", "/admin/bill_creator/42/pipeline");
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.click(screen.getByTestId("pick-the-sentinel"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: { bill_creator_tab: "pipeline" },
        });
    });

    // The other side of the wire: on the Creator tab the same sentinel means "make a new bill", and
    // that tab is where it already led — so this cannot pass by hardcoding one tab.
    it("keeps the operator on the Creator tab", () => {
        window.history.pushState({}, "", "/admin/bill_creator/42/creator");
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-the-sentinel"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: { bill_creator_tab: "creator" },
        });
    });
});

// @lat: [[bill-creator-shell#Why the Bill Creator carries query parameters across navigation]]
describe("BillCreatorShell — navigation dispatch across tabs, bills, and locales", () => {
    const SAMPLE_SEARCH = "?plain=scalar&multi=first&multi=second&tags[]=alpha&tags[]=beta&sway_locale_id=2";

    it("dispatches clean tab visit without spreading hand-rolled query params into data", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${SAMPLE_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.mouseDown(screen.getByText("Summary"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/summary", {
            data: {
                bill_creator_tab: "summary",
            },
            preserveScroll: true,
        });
    });

    it("dispatches clean tab visit to Positions tab as a counter-example", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${SAMPLE_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.mouseDown(screen.getByText("Positions"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/positions", {
            data: {
                bill_creator_tab: "positions",
            },
            preserveScroll: true,
        });
    });

    it("dispatches tab navigation during new bill creation", () => {
        mockPageProps.bill = undefined;
        window.history.pushState({}, "", "/admin/bill_creator/new?filter=unreviewed&tags[]=test");
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.mouseDown(screen.getByText("Summary"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: {
                bill_creator_tab: "summary",
            },
            preserveScroll: true,
        });
    });

    it("dispatches bill change with only bill_creator_tab without hand-rolling params", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${SAMPLE_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-existing-bill-99"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/99/creator", {
            data: {
                bill_creator_tab: "creator",
            },
        });
    });

    it("dispatches bill change to bill 101 as a counter-example", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${SAMPLE_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-existing-bill-101"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/101/creator", {
            data: {
                bill_creator_tab: "creator",
            },
        });
    });

    it("dispatches navigation when selecting the All Bills sentinel", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/pipeline${SAMPLE_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.click(screen.getByTestId("pick-the-sentinel"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: {
                bill_creator_tab: "pipeline",
            },
        });
    });

    it("dispatches locale change with sway_locale_id without spreading old query params", () => {
        window.history.pushState(
            {},
            "",
            "/admin/bill_creator/42/creator?filter=active&multi=first&multi=second&tags[]=alpha&tags[]=beta",
        );
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-locale-2"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: {
                sway_locale_id: 2,
            },
        });
    });

    it("dispatches locale change to locale 3 as a counter-example", () => {
        window.history.pushState(
            {},
            "",
            "/admin/bill_creator/42/creator?filter=active&multi=first&multi=second&tags[]=alpha&tags[]=beta",
        );
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-locale-3"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: {
                sway_locale_id: 3,
            },
        });
    });
});

// @lat: [[bill-creator-shell#Why the Bill Creator carries query parameters across navigation]]
describe("BillCreatorShell — RunSelector pinning and clearing carry", () => {
    it("pins run_id in the URL when selecting run 77 and dispatches tab visit with bill_creator_tab", () => {
        window.history.pushState({}, "", "/admin/bill_creator/42/pipeline");
        routerVisit.mockClear();
        routerGet.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);

        fireEvent.change(screen.getByTestId("run-selector"), { target: { value: "77" } });

        expect(routerGet).toHaveBeenCalledWith(
            "/admin/bill_creator/42/pipeline?run_id=77",
            undefined,
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
        expect(window.location.search).toBe("?run_id=77");

        fireEvent.mouseDown(screen.getByText("Summary"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/summary", {
            data: { bill_creator_tab: "summary" },
            preserveScroll: true,
        });
    });

    it("pins run_id in the URL when selecting run 99 and dispatches tab visit to Positions tab", () => {
        window.history.pushState({}, "", "/admin/bill_creator/42/pipeline");
        routerVisit.mockClear();
        routerGet.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);

        fireEvent.change(screen.getByTestId("run-selector"), { target: { value: "99" } });

        expect(routerGet).toHaveBeenCalledWith(
            "/admin/bill_creator/42/pipeline?run_id=99",
            undefined,
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
        expect(window.location.search).toBe("?run_id=99");

        fireEvent.mouseDown(screen.getByText("Positions"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/positions", {
            data: { bill_creator_tab: "positions" },
            preserveScroll: true,
        });
    });

    it("deliberately clearing run_id via RunSelector emits the cleared parameter signal and does not resurrect previous run_id", () => {
        window.history.pushState({}, "", "/admin/bill_creator/42/pipeline?run_id=77");
        routerVisit.mockClear();
        routerGet.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);

        expect((screen.getByTestId("run-selector") as HTMLSelectElement).value).toBe("77");

        fireEvent.change(screen.getByTestId("run-selector"), { target: { value: "" } });

        expect(routerGet).toHaveBeenCalledWith(
            "/admin/bill_creator/42/pipeline?run_id=",
            undefined,
            expect.objectContaining({
                preserveScroll: true,
                preserveState: true,
            }),
        );
        expect(window.location.search).toBe("?run_id=");
        expect(isQueryParamCleared(new URLSearchParams(window.location.search), "run_id")).toBe(true);

        fireEvent.mouseDown(screen.getByText("Summary"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/summary", {
            data: { bill_creator_tab: "summary" },
            preserveScroll: true,
        });
    });
});

// @lat: [[bill-creator-shell#Why the Bill Creator carries query parameters across navigation]]
describe("BillCreatorShell — centralized carry of Creator operator controls", () => {
    const CREATOR_SEARCH =
        "?selected_stages[]=fetch-bills&selected_stages[]=fetch-law&download_missing_assets=0&severity=error&window=1d&cursor=cur_123&run_id=99&sway_locale_id=2";

    it("retains all creator list and scalar controls across tab changes under default production registration", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/pipeline${CREATOR_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.mouseDown(screen.getByText("Summary"));

        expect(routerVisit).toHaveBeenCalledWith("/admin/bill_creator/42/summary", {
            data: { bill_creator_tab: "summary" },
            preserveScroll: true,
        });

        const outgoing = getOutgoingVisitUrl()!;
        expect(outgoing).not.toBeNull();
        expect(outgoing.pathname).toBe("/admin/bill_creator/42/summary");
        expect(outgoing.searchParams.getAll("selected_stages[]")).toEqual(["fetch-bills", "fetch-law"]);
        expect(outgoing.searchParams.get("download_missing_assets")).toBe("0");
        expect(outgoing.searchParams.get("severity")).toBe("error");
        expect(outgoing.searchParams.get("window")).toBe("1d");
        expect(outgoing.searchParams.get("cursor")).toBe("cur_123");
        expect(outgoing.searchParams.get("run_id")).toBe("99");
        expect(outgoing.searchParams.get("sway_locale_id")).toBe("2");
    });

    it("preserves explicit empty stage selection across tab changes without defaulting back to all stages", () => {
        window.history.pushState(
            {},
            "",
            "/admin/bill_creator/42/pipeline?selected_stages=&download_missing_assets=0&run_id=99",
        );
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.mouseDown(screen.getByText("Summary"));

        const outgoing = getOutgoingVisitUrl()!;
        expect(outgoing.searchParams.has("selected_stages")).toBe(true);
        expect(outgoing.searchParams.get("selected_stages")).toBe("");
        expect(outgoing.searchParams.get("download_missing_assets")).toBe("0");
        expect(outgoing.searchParams.get("run_id")).toBe("99");
    });

    it("retains creator controls when switching bills", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${CREATOR_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-existing-bill-99"));

        const outgoing = getOutgoingVisitUrl()!;
        expect(outgoing.pathname).toBe("/admin/bill_creator/99/creator");
        expect(outgoing.searchParams.getAll("selected_stages[]")).toEqual(["fetch-bills", "fetch-law"]);
        expect(outgoing.searchParams.get("download_missing_assets")).toBe("0");
        expect(outgoing.searchParams.get("severity")).toBe("error");
        expect(outgoing.searchParams.get("window")).toBe("1d");
        expect(outgoing.searchParams.get("cursor")).toBe("cur_123");
        expect(outgoing.searchParams.get("run_id")).toBe("99");
        expect(outgoing.searchParams.get("sway_locale_id")).toBe("2");
    });

    it("retains creator controls and updates sway_locale_id when switching jurisdictions", () => {
        window.history.pushState({}, "", `/admin/bill_creator/42/creator${CREATOR_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(screen.getByTestId("pick-locale-2"));

        const outgoing = getOutgoingVisitUrl()!;
        expect(outgoing.pathname).toBe("/admin/bill_creator/new");
        expect(outgoing.searchParams.getAll("selected_stages[]")).toEqual(["fetch-bills", "fetch-law"]);
        expect(outgoing.searchParams.get("download_missing_assets")).toBe("0");
        expect(outgoing.searchParams.get("severity")).toBe("error");
        expect(outgoing.searchParams.get("window")).toBe("1d");
        expect(outgoing.searchParams.get("cursor")).toBe("cur_123");
        expect(outgoing.searchParams.get("run_id")).toBe("99");
        expect(outgoing.searchParams.get("sway_locale_id")).toBe("2");
    });

    it("fails to carry parameters if production navigation carry is unregistered", () => {
        unregisterQueryParamNavigationCarry();
        window.history.pushState({}, "", `/admin/bill_creator/42/pipeline${CREATOR_SEARCH}`);
        routerVisit.mockClear();

        render(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.mouseDown(screen.getByText("Summary"));

        const outgoing = getOutgoingVisitUrl()!;
        expect(outgoing.searchParams.has("selected_stages[]")).toBe(false);
        expect(outgoing.searchParams.has("download_missing_assets")).toBe(false);
        expect(outgoing.searchParams.has("severity")).toBe(false);
        expect(outgoing.searchParams.has("window")).toBe(false);
    });
});
