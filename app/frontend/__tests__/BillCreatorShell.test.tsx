// oxlint-disable-next-line vitest/require-mock-type-parameters -- false positive; all vi.fn() calls have type parameters
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent } from "@testing-library/react";
import { ETab } from "app/frontend/components/bill/creator/constants";
import { renderV2, resetInertiaStubs, setPageProps, type InertiaStubs } from "app/frontend/__tests__/test-utils";

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} as Record<string, unknown> })),
    router: {
        visit: vi.fn<(url: string) => void>(),
        post: vi.fn<(url: string, data?: unknown) => void>(),
        put: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
        delete: vi.fn<(url: string) => void>(),
        get: vi.fn<(url: string) => void>(),
        reload: vi.fn<(opts?: Record<string, unknown>) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return { ...actual, usePage: inertia.usePage, router: inertia.router };
});

// @lat: [[bill-creator-shell#The Bill Creator shell#Why only the tab container is tested in the shell test]]
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<() => Promise<boolean>>().mockResolvedValue(true),
}));

const paramsAdd = vi.hoisted(() => vi.fn<(key: string, value: string) => void>());
vi.mock("app/frontend/hooks/useSearchParams", () => ({
    useSearchParams: () => ({
        entries: {},
        qs: "",
        get: vi.fn<(key: string) => string | undefined>(),
        add: paramsAdd,
        remove: vi.fn<(key: string) => void>(),
    }),
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorAccordions", () => ({
    default: ({ setCreatorDirty }: { setCreatorDirty: (v: boolean) => void }) => (
        <div data-testid="creator-accordions">
            <button type="button" data-testid="mark-dirty" onClick={() => setCreatorDirty(true)}>
                mark dirty
            </button>
            <button type="button" data-testid="mark-clean" onClick={() => setCreatorDirty(false)}>
                mark clean
            </button>
        </div>
    ),
}));
vi.mock("app/frontend/components/admin/creator/BillSchedule", () => ({
    default: () => <div data-testid="schedule-panel" />,
}));
// @lat: [[bill-creator-shell#Why a Radix portal is stubbed rather than driven in tests]]
vi.mock("app/frontend/components/admin/creator/AdminSwayLocaleSelector", () => ({
    default: ({ onSwayLocaleChange }: { onSwayLocaleChange: (swayLocaleId: number) => void }) => (
        <button type="button" data-testid="change-locale" onClick={() => onSwayLocaleChange(9)}>
            change locale
        </button>
    ),
}));
vi.mock("app/frontend/components/admin/creator/BillCreatorPipelineLlm", () => ({
    default: () => <div data-testid="pipeline-panel" />,
}));

vi.mock("app/frontend/components/ui/combobox", () => {
    type ComboboxOption = { value: string; label: string };
    type ComboboxProps = {
        value: string;
        onValueChange: (v: string) => void;
        options: ComboboxOption[];
        pinnedOption?: ComboboxOption;
    };
    return {
        Combobox: ({ value, onValueChange, options, pinnedOption }: ComboboxProps) => (
            <div data-testid="bill-select" data-value={value}>
                <input data-testid="bill-select-input" value={value} onChange={(e) => onValueChange(e.target.value)} />
                {[...(pinnedOption ? [pinnedOption] : []), ...options].map((o) => (
                    <div key={o.value} data-testid="bill-select-item" data-value={o.value}>
                        {o.label}
                    </div>
                ))}
            </div>
        ),
    };
});
vi.mock("app/frontend/components/ui/select", () => {
    type SelectProps = {
        value: string;
        onValueChange: (v: string) => void;
        children?: ReactNode;
        disabled?: boolean;
    };
    return {
        Select: ({ value, onValueChange, children }: SelectProps) => (
            <div data-testid="ui-select" data-value={value}>
                <input data-testid="ui-select-input" value={value} onChange={(e) => onValueChange(e.target.value)} />
                {children}
            </div>
        ),
        SelectTrigger: ({ children }: { children: ReactNode }) => <div>{children}</div>,
        SelectValue: ({ placeholder }: { placeholder?: string }) => <span>{placeholder}</span>,
        SelectContent: ({ children }: { children: ReactNode }) => <div>{children}</div>,
        SelectItem: ({ value, children }: { value: string; children: ReactNode }) => (
            <div data-testid="ui-select-item" data-value={value}>
                {children}
            </div>
        ),
    };
});

vi.mock("app/frontend/components/ui/tabs", () => ({
    Tabs: ({
        value,
        onValueChange,
        children,
    }: {
        value: string;
        onValueChange: (v: string) => void;
        children: ReactNode;
    }) => (
        <div data-testid="tabs" data-value={value}>
            <input data-testid="tabs-input" value={value} onChange={(e) => onValueChange(e.target.value)} />
            {children}
        </div>
    ),
    TabsList: ({ children }: { children: ReactNode }) => <div>{children}</div>,
    TabsTrigger: ({ value, children }: { value: string; children: ReactNode }) => (
        <button type="button" data-testid={`tab-${value}`} data-value={value}>
            {children}
        </button>
    ),
    TabsContent: ({ value, children }: { value: string; children: ReactNode }) => (
        <div data-testid={`tab-content-${value}`}>{children}</div>
    ),
}));

vi.mock("app/frontend/components/ui/dialog", () => ({
    Dialog: ({ open, children }: { open: boolean; children: ReactNode }) =>
        open ? (
            <dialog open data-testid="dialog">
                {children}
            </dialog>
        ) : null,
    DialogContent: ({ children }: { children: ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: ReactNode }) => <div>{children}</div>,
    DialogFooter: ({ children }: { children: ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: ReactNode }) => <h2>{children}</h2>,
    DialogDescription: ({ children }: { children: ReactNode }) => <p>{children}</p>,
}));

import BillCreatorShell from "app/frontend/components/admin/creator/BillCreatorShell";

beforeEach(() => {
    resetInertiaStubs(inertia);
    paramsAdd.mockReset();
});

const sampleBills = [
    { id: 11, external_id: "HB0001", title: "Open Meetings Act", external_version: "v1" },
    { id: 22, external_id: "SB0055", title: "Transit Funding", external_version: "v1" },
];

describe("BillCreatorShell — bill picker options", () => {
    it("includes a 'New Bill' entry plus every bill prop sorted by label", () => {
        setPageProps(inertia, { bills: sampleBills });

        const { getAllByTestId } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);

        const items = getAllByTestId("bill-select-item");
        const labels = items.map((el) => el.textContent);
        expect(labels[0]).toBe("New Bill");
        expect(labels).toContain("HB0001 — Open Meetings Act");
        expect(labels).toContain("SB0055 — Transit Funding");
    });

    it("selects 'New Bill' sentinel when no bill id is set", () => {
        setPageProps(inertia, { bill: undefined, bills: sampleBills });

        const { getByTestId } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);

        expect(getByTestId("bill-select")).toHaveAttribute("data-value", "__new__");
    });

    it("selects the current bill id when the bill prop has one", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);

        expect(getByTestId("bill-select")).toHaveAttribute("data-value", "22");
    });
});

describe("BillCreatorShell — bill navigation", () => {
    // @lat: [[bill-creator-shell#The Bill Creator shell#Why the tab survives picking a different bill]]
    it("routes to /admin/bill_creator/new, keeping the tab, when the 'New Bill' sentinel is picked", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.change(getByTestId("bill-select-input"), { target: { value: "__new__" } });

        expect(inertia.router.visit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: { bill_creator_tab: ETab.Creator },
        });
    });

    it("routes to /admin/bill_creator/:id/<current-tab> when an existing bill is picked (follow-up A)", () => {
        setPageProps(inertia, { bill: undefined, bills: sampleBills });

        const { getByTestId } = renderV2(<BillCreatorShell tabKey={ETab.PipelineLlm} />);
        fireEvent.change(getByTestId("bill-select-input"), { target: { value: "11" } });

        // @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
        expect(inertia.router.visit).toHaveBeenCalledWith(`/admin/bill_creator/11/${ETab.PipelineLlm}`, {
            data: { bill_creator_tab: ETab.PipelineLlm },
        });
    });

    it("switches tabs via the canonical query on the id-less new-bill flow", () => {
        // @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
        setPageProps(inertia, { bill: undefined, bills: sampleBills });

        const { getByTestId } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.change(getByTestId("tabs-input"), { target: { value: ETab.Schedule } });

        expect(inertia.router.visit).toHaveBeenCalledWith("/admin/bill_creator/new", {
            data: { bill_creator_tab: ETab.Schedule },
            preserveScroll: true,
        });
    });
});

describe("BillCreatorShell — dirty-guard dialog", () => {
    it("opens the dialog with bill-switch copy when the form is dirty and a bill is picked", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("bill-select-input"), { target: { value: "11" } });

        const dialog = queryByRole("dialog");
        expect(dialog).not.toBeNull();
        // @lat: [[bill-creator-shell#The Bill Creator shell#Why the unsaved-changes dialog has one sentence per action kind]]
        expect(dialog?.textContent).toContain("only for one bill at a time");
        expect(dialog?.textContent).not.toMatch(/discard/i);
        expect(inertia.router.visit).not.toHaveBeenCalled();
    });

    it("opens the dialog with tab-switch copy when the form is dirty and a dirty-guarded tab is picked", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("tabs-input"), { target: { value: ETab.Schedule } });

        const dialog = queryByRole("dialog");
        expect(dialog).not.toBeNull();
        // @lat: [[bill-creator-shell#The Bill Creator shell#Why the unsaved-changes dialog has one sentence per action kind]]
        expect(dialog?.textContent).toContain("come back when you return");
        expect(dialog?.textContent).toContain("what you are typing right now");
        expect(dialog?.textContent).toContain("your unsaved summary");
        expect(dialog?.textContent).not.toMatch(/discard/i);
        expect(paramsAdd).not.toHaveBeenCalled();
    });

    it("'Stay' cancels the pending navigation and closes the dialog", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, getByRole, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("bill-select-input"), { target: { value: "11" } });

        fireEvent.click(getByRole("button", { name: /stay/i }));

        expect(queryByRole("dialog")).toBeNull();
        expect(inertia.router.visit).not.toHaveBeenCalled();
    });

    it("'Switch bill' commits the pending bill navigation", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, getByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("bill-select-input"), { target: { value: "11" } });

        fireEvent.click(getByRole("button", { name: /switch (bill|tab)/i }));

        expect(inertia.router.visit).toHaveBeenCalledWith(`/admin/bill_creator/11/${ETab.Creator}`, {
            data: {},
        });
    });

    it("'Switch tab' commits the pending tab change via router.visit (follow-up A)", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, getByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("tabs-input"), { target: { value: ETab.Schedule } });

        fireEvent.click(getByRole("button", { name: /switch (bill|tab)/i }));

        // @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
        expect(inertia.router.visit).toHaveBeenCalledWith(`/admin/bill_creator/22/${ETab.Schedule}`, {
            data: { bill_creator_tab: ETab.Schedule },
            preserveScroll: true,
        });
        expect(paramsAdd).not.toHaveBeenCalled();
    });

    // @lat: [[bill-creator-shell#The Bill Creator shell#Why onSwayLocaleChange always returns to the empty picker]]
    describe("a jurisdiction change is not a bill change", () => {
        const openLocaleDialog = () => {
            setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

            const rendered = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
            fireEvent.click(rendered.getByTestId("mark-dirty"));
            fireEvent.click(rendered.getByTestId("change-locale"));
            return rendered;
        };

        it("names the action the operator actually took", () => {
            const { queryByRole } = openLocaleDialog();

            const dialog = queryByRole("dialog");
            expect(dialog).not.toBeNull();
            expect(dialog?.textContent).toMatch(/jurisdiction/i);
            expect(dialog?.textContent).not.toMatch(/another bill/i);
            expect(dialog?.textContent).not.toMatch(/switch bill/i);
            expect(inertia.router.visit).not.toHaveBeenCalled();
        });

        // @lat: [[bill-creator-shell#The Bill Creator shell#Why the unsaved-changes dialog has one sentence per action kind]]
        it("does not promise this draft comes back after the jurisdiction changes", () => {
            const { queryByRole } = openLocaleDialog();

            const dialog = queryByRole("dialog");
            expect(dialog?.textContent).not.toMatch(/here when you come back to it/i);
            expect(dialog?.textContent).toMatch(/replaces this draft/i);
        });

        it("labels its confirm button for the jurisdiction, not the bill", () => {
            const { getByRole } = openLocaleDialog();

            expect(getByRole("button", { name: /change jurisdiction/i })).toBeInTheDocument();
        });

        it("commits the jurisdiction change on confirm", () => {
            const { getByRole } = openLocaleDialog();

            fireEvent.click(getByRole("button", { name: /change jurisdiction/i }));

            expect(inertia.router.visit).toHaveBeenCalledWith("/admin/bill_creator/new", {
                data: { sway_locale_id: 9 },
            });
        });

        it("still names the bill when a bill is what changed", () => {
            setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

            const { getByTestId, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Creator} />);
            fireEvent.click(getByTestId("mark-dirty"));
            fireEvent.change(getByTestId("bill-select-input"), { target: { value: "11" } });

            const dialog = queryByRole("dialog");
            expect(dialog?.textContent).toMatch(/another bill/i);
            expect(dialog?.textContent).not.toMatch(/jurisdiction/i);
        });
    });

    it("gates a switch back to the Creator tab as well, and commits it on confirm", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, getByRole, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Schedule} />);
        fireEvent.click(getByTestId("mark-dirty"));
        fireEvent.change(getByTestId("tabs-input"), { target: { value: ETab.Creator } });

        expect(queryByRole("dialog")).not.toBeNull();
        expect(inertia.router.visit).not.toHaveBeenCalled();

        fireEvent.click(getByRole("button", { name: /switch tab/i }));

        // @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
        expect(inertia.router.visit).toHaveBeenCalledWith(`/admin/bill_creator/22/${ETab.Creator}`, {
            data: { bill_creator_tab: ETab.Creator },
            preserveScroll: true,
        });
    });

    it("lets a clean Creator-tab switch through without the dialog", () => {
        setPageProps(inertia, { bill: { id: 22, external_id: "SB0055" }, bills: sampleBills });

        const { getByTestId, queryByRole } = renderV2(<BillCreatorShell tabKey={ETab.Schedule} />);
        fireEvent.change(getByTestId("tabs-input"), { target: { value: ETab.Creator } });

        expect(queryByRole("dialog")).toBeNull();
        expect(inertia.router.visit).toHaveBeenCalledWith(`/admin/bill_creator/22/${ETab.Creator}`, {
            data: { bill_creator_tab: ETab.Creator },
            preserveScroll: true,
        });
    });
});
