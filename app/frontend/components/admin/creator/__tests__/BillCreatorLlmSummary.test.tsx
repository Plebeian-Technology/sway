import { cleanup, fireEvent, render, screen, act } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ConfirmOptions } from "app/frontend/components/ui/confirm-dialog";

// ── Stand-ins for other modules ──────────────────────────────────────────────

// @lat: [[org-position-bill-testimony-check#Test setup for BillCreatorLlmSummary.test.tsx]]
const { confirmMock } = vi.hoisted(() => ({ confirmMock: vi.fn<(options: ConfirmOptions) => Promise<boolean>>() }));
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerPatch = vi.fn<(...args: unknown[]) => void>();
const routerReload = vi.fn<(...args: unknown[]) => void>();
const usePageMock = vi.fn<() => Record<string, unknown>>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        patch: (...args: unknown[]) => routerPatch(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));

const notifyMock = vi.fn<(options: Record<string, unknown>) => void>();

vi.mock("app/frontend/sway_utils", () => ({
    notify: (options: Record<string, unknown>) => notifyMock(options),
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
    Badge: ({
        children,
        variant,
        tone,
        ...props
    }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
        <span data-testid="badge" data-variant={variant} data-tone={tone} {...props}>
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

vi.mock("app/frontend/components/ui/dialog", () => ({
    Dialog: ({
        children,
        open,
        onOpenChange,
    }: {
        children: React.ReactNode;
        open?: boolean;
        onOpenChange?: (open: boolean) => void;
    }) =>
        open ? (
            <dialog
                open
                data-testid="dialog"
                onKeyDown={(e) => {
                    if (e.key === "Escape") onOpenChange?.(false);
                }}
            >
                <button
                    type="button"
                    tabIndex={-1}
                    data-testid="dialog-backdrop"
                    aria-label="Dismiss dialog"
                    onClick={() => onOpenChange?.(false)}
                />
                {children}
            </dialog>
        ) : null,
    DialogContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
    DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
}));

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));

vi.mock("app/frontend/components/ui/label", () => ({
    Label: ({ children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) => (
        <label {...props}>{children}</label>
    ),
}));

vi.mock("app/frontend/components/ui/tooltip", () => ({
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode; asChild?: boolean }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <span data-testid="tooltip">{children}</span>,
}));

// Replace the neighbouring components with simple stand-ins, so we do not have
// to pull in everything they depend on. Only the stale header matters here.
vi.mock("app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge", () => ({
    default: ({ status }: { status: string | null }) => <div data-testid="status-badge">{String(status)}</div>,
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorOrgPositionCard", () => ({
    // `index` is put in the output so a test below can check the card gets its
    // position in the FULL draft list, not its position among the cards shown.
    default: ({ index, orgPosition }: { index: number; orgPosition: { org_name: string } }) => (
        <div data-testid="org-position-card" data-index={index}>
            {orgPosition.org_name}
        </div>
    ),
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge", () => ({
    default: ({ status }: { status: string | null }) => <div data-testid="pipeline-status-badge">{String(status)}</div>,
}));

// A native <select> in place of the Radix picker, so a choice can be made with
// fireEvent.change. SummaryModelPicker's own rendering is covered by
// summaryModelChoice.test.tsx.
vi.mock("app/frontend/components/admin/creator/llm-summary/SummaryModelPicker", () => ({
    default: ({
        modelOptions,
        selectedModel,
        onModelChange,
    }: {
        modelOptions: { id: string; label: string }[];
        selectedModel: string;
        onModelChange: (model: string) => void;
    }) =>
        modelOptions.length === 0 ? null : (
            <select
                data-testid="select-summary-model"
                value={selectedModel}
                onChange={(event) => onModelChange(event.target.value)}
            >
                <option value="">Standing default</option>
                {modelOptions.map((option) => (
                    <option key={option.id} value={option.id}>
                        {option.label}
                    </option>
                ))}
            </select>
        ),
}));

// Import the component being tested AFTER the stand-ins above.
import BillCreatorLlmSummary from "app/frontend/components/admin/creator/BillCreatorLlmSummary";
import { clearRetainedSummaryInstructions } from "app/frontend/components/admin/creator/llm-summary/useRegenerateSummary";
import {
    IBillLlmProvisioning,
    IOrgPosition,
    ITestimonyAttachment,
} from "app/frontend/components/admin/creator/llm-summary/types";
import { TStaleChangeKind } from "app/frontend/components/admin/creator/llm-summary/staleChange";
import fixtureOverride from "app/frontend/components/admin/creator/__tests__/fixtureOverride";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeBill(overrides: {
    stale: boolean;
    // The PUBLISHED summary (bills.summary), kept apart from llm_summary below (the
    // model's draft). Nothing copies one to the other, and no fixture told them apart
    // until now. (C21-02)
    summary?: string | null;
    generation_status?: "pending" | "generating" | "completed" | "failed" | "skipped" | null;
    stale_change_kind?: TStaleChangeKind | null;
    stale_change_at?: string | null;
    llm_generated_at?: string | null;
    llm_summary?: string | null;
    // IOrgPosition, not a loose Record: the loose shape is what let a fixture
    // claim a draft without the three fields every card reads.
    draft_org_positions?: IOrgPosition[];
    generation_error?: string | null;
    supplemental_testimony?: string | null;
    bill_pipeline_status?: "queued" | "running" | "completed" | "failed" | null;
    has_testimony?: boolean;
    testimony_attachments?: ITestimonyAttachment[] | null;
    llm_provider?: string | null;
    reclaimable?: boolean;
    // @lat: [[bill-creator-test-fixture-overrides#paste_owns_summary_run is set independently of llm_provider]]
    paste_owns_summary_run?: boolean;
}) {
    // @lat: [[bill-creator-test-fixture-overrides#Provisioning fixtures are typed, unlike the whole TBill]]
    const bill_llm_provisioning: IBillLlmProvisioning = {
        has_testimony: fixtureOverride(overrides, "has_testimony", true),
        testimony_attachments: fixtureOverride(overrides, "testimony_attachments", null),
        llm_provider: fixtureOverride(overrides, "llm_provider", "claude"),
        citations_valid: null,
        invalid_citations: null,
        generation_status: fixtureOverride(overrides, "generation_status", "completed"),
        generation_error: fixtureOverride(overrides, "generation_error", null),
        llm_summary: fixtureOverride(overrides, "llm_summary", "Existing summary body — should remain readable."),
        llm_full_breakdown: "breakdown",
        supplemental_testimony: fixtureOverride(overrides, "supplemental_testimony", null),
        draft_org_positions: fixtureOverride(overrides, "draft_org_positions", []),
        stale: overrides.stale,
        reclaimable: fixtureOverride(overrides, "reclaimable", false),
        paste_owns_summary_run: fixtureOverride(overrides, "paste_owns_summary_run", false),
        stale_change_kind: fixtureOverride(overrides, "stale_change_kind", "pipeline_data"),
        stale_change_at: fixtureOverride(overrides, "stale_change_at", new Date(Date.now() - 60_000).toISOString()),
        llm_generated_at: fixtureOverride(
            overrides,
            "llm_generated_at",
            new Date(Date.now() - 24 * 60 * 60_000).toISOString(),
        ),
    };

    return {
        id: 42,
        external_id: "HB123",
        summary: fixtureOverride(overrides, "summary", "The published summary an admin wrote by hand."),
        bill_llm_provisioning,
        bill_pipeline_refresh: overrides.bill_pipeline_status
            ? { status: overrides.bill_pipeline_status, error_message: null }
            : null,
    };
}

beforeEach(() => {
    routerPost.mockClear();
    routerPatch.mockClear();
    routerReload.mockClear();
    notifyMock.mockClear();
    confirmMock.mockReset();
    confirmMock.mockResolvedValue(true);
    usePageMock.mockReset();
});

afterEach(() => cleanup());

describe("BillCreatorLlmSummary stale chip + Regenerate CTA", () => {
    it("when stale === true, shows the stale chip and Regenerate CTA", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: true }) } });
        render(<BillCreatorLlmSummary />);

        const chip = screen.getByTestId("llm-stale-chip");
        expect(chip).toBeTruthy();
        expect(chip.getAttribute("data-variant")).toBe("stamp");
        expect(chip.getAttribute("data-tone")).toBe("warning");
        expect(chip.textContent ?? "").toContain("Stale: pipeline data updated");

        expect(screen.getByTestId("btn-regenerate-from-latest-data")).toBeTruthy();
        // The summary stays on screen while stale, in the draft notice — the editor holds bills.summary and
        // llm_summary is the model's draft on a different record. (C21-02)
        expect(screen.getByTestId("llm-draft-body")).toHaveTextContent("Existing summary body");
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
    it("names testimony, and the testimony moment, when testimony is what overtook the summary", () => {
        const testimonyAt = new Date(Date.now() - 60_000).toISOString();
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: true,
                    stale_change_kind: "testimony",
                    stale_change_at: testimonyAt,
                }),
            },
        });
        render(<BillCreatorLlmSummary />);

        const text = screen.getByTestId("llm-stale-chip").textContent ?? "";
        expect(text).toContain("Stale: testimony updated");
        expect(text).not.toContain("pipeline data");
    });

    // fixtureOverride reads the key instead of coalescing, surfacing a null moment paired
    // with stale — a state #stale_change can't produce alone (kind+moment together or
    // neither). (C20-07)
    it("says the last update is unknown when the server names no moment", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: true, stale_change_kind: null, stale_change_at: null }) },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("llm-stale-chip").textContent ?? "").toContain("Stale: last update unknown");
    });

    // The sibling field, and the sibling branch: a row that has never produced
    // a body carries no provider, so the hand-written stamp must not appear.
    it("draws no operator-pasted stamp on a row with no provider", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false, llm_provider: null }) } });
        render(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("llm-operator-paste-chip")).toBeNull();
    });

    it("when stale === false, neither stale chip nor Regenerate CTA renders", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("llm-stale-chip")).toBeNull();
        expect(screen.queryByTestId("btn-regenerate-from-latest-data")).toBeNull();
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
    it("a skipped row that still has a prior summary renders the editable completed view", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    generation_status: "skipped",
                    llm_summary: "Prior summary survives the skip.",
                }),
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("llm-draft-body")).toHaveTextContent("Prior summary survives the skip");
        // The badge shows the real status, "skipped", not a green "Ready": the
        // normal view passes the status straight through rather than hard-coding
        // one.
        expect(screen.getByTestId("status-badge").textContent).toBe("skipped");
    });

    // @lat: [[bill-creator-test-fixture-overrides#The refused-Generate test relies on the onError toast, not a flash]]
    it("clicking Generate carries an onError that toasts the server's refusal copy", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, generation_status: "failed", llm_summary: null }) },
        });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-retry-summary"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        expect(typeof opts.onError).toBe("function");

        opts.onError?.({ generation: "Generation already in progress" });

        expect(notifyMock).toHaveBeenCalledWith({ level: "error", title: "Generation already in progress" });
    });

    it("clicking the Regenerate CTA POSTs to /bills/:id/regenerate_summary via Inertia router", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: true }) } });
        render(<BillCreatorLlmSummary />);

        // This button now asks for confirmation first — what it sends is unchanged. On a stale bill this is
        // the ONLY regenerate button, exactly where a hand-pasted summary lives.
        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        expect(routerPost).not.toHaveBeenCalled();
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        const call = routerPost.mock.calls[0];
        expect(call[0]).toBe("/bills/42/regenerate_summary");
        // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
        expect(call[1]).toEqual({});
        expect(call[2]).toMatchObject({ preserveScroll: true });
        const opts = call[2] as { onStart: () => void; onFinish: () => void };
        expect(typeof opts.onStart).toBe("function");
        expect(typeof opts.onFinish).toBe("function");
    });

    it("CTA stays disabled when stale=true AND generation_status === 'generating' (in-flight guard)", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: true, generation_status: "generating" }) },
        });
        render(<BillCreatorLlmSummary />);

        const cta = screen.getByTestId("btn-regenerate-from-latest-data") as HTMLButtonElement;
        expect(cta.disabled).toBe(true);

        // Clicking a greyed-out button must NOT send anything. The server's
        // `regenerate_summary` would refuse with "already in progress" anyway,
        // but checking here saves the trip.
        fireEvent.click(cta);
        expect(routerPost).not.toHaveBeenCalled();
    });

    it("CTA stays disabled when stale=true AND generation_status === 'pending' (in-flight guard)", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: true, generation_status: "pending" }) },
        });
        render(<BillCreatorLlmSummary />);

        const cta = screen.getByTestId("btn-regenerate-from-latest-data") as HTMLButtonElement;
        expect(cta.disabled).toBe(true);
        fireEvent.click(cta);
        expect(routerPost).not.toHaveBeenCalled();
    });

    it("CTA enters disabled state while the Inertia request is in-flight, then re-enables", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: true }) } });
        render(<BillCreatorLlmSummary />);

        const cta = screen.getByTestId("btn-regenerate-from-latest-data") as HTMLButtonElement;
        expect(cta.disabled).toBe(false);

        fireEvent.click(cta);
        // The confirmation step; the checks below then run just as before.
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        // Take the start and finish callbacks out of the router.post arguments
        // and call them, to act out a request beginning and ending.
        const opts = routerPost.mock.calls[0][2] as { onStart: () => void; onFinish: () => void };

        act(() => {
            opts.onStart();
        });
        const inFlight = screen.getByTestId("btn-regenerate-from-latest-data") as HTMLButtonElement;
        expect(inFlight.disabled).toBe(true);
        expect(inFlight.textContent).toContain("Queueing");

        act(() => {
            opts.onFinish();
        });
        const afterFinish = screen.getByTestId("btn-regenerate-from-latest-data") as HTMLButtonElement;
        expect(afterFinish.disabled).toBe(false);
        expect(afterFinish.textContent).toContain("Regenerate from latest data");
    });
});

// @lat: [[bill-creator-test-fixture-overrides#The no-provisioning empty-state CTA also posts to /regenerate_summary]]
describe("BillCreatorLlmSummary no-provisioning empty-state CTAs", () => {
    const billNoProvisioning = {
        id: 42,
        external_id: "HB123",
        bill_llm_provisioning: null,
        bill_pipeline_refresh: null,
    };

    it("renders a 'Generate summary' button that POSTs to /bills/:id/regenerate_summary", () => {
        usePageMock.mockReturnValue({ props: { bill: billNoProvisioning } });
        render(<BillCreatorLlmSummary />);

        const btn = screen.getByTestId("btn-generate-summary-empty-state");
        expect(btn).toBeTruthy();
        expect(btn.textContent).toBe("Generate summary");

        fireEvent.click(btn);

        expect(routerPost).toHaveBeenCalledTimes(1);
        const call = routerPost.mock.calls[0];
        expect(call[0]).toBe("/bills/42/regenerate_summary");
        expect(call[1]).toEqual({});
        expect(call[2]).toMatchObject({ preserveScroll: true });
    });

    // Building the prompt writes nothing, so this asks for a prop instead of posting. It
    // used to carry the active tab through a full re-render; a reload changes no page, so
    // there's no tab to carry.
    it("Prepare-prompt button asks the server for the summary_prompt prop by name", () => {
        usePageMock.mockReturnValue({ props: { bill: billNoProvisioning, tab_key: "summary" } });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-prepare-prompt"));

        expect(routerReload).toHaveBeenCalledTimes(1);
        expect(routerPost).not.toHaveBeenCalled();
        expect(routerReload.mock.calls[0][0]).toMatchObject({
            only: ["summary_prompt", "bill"],
        });
    });

    it("Generate-summary button disables + flips copy while the request is in-flight", () => {
        usePageMock.mockReturnValue({ props: { bill: billNoProvisioning } });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        const opts = routerPost.mock.calls[0][2] as { onStart: () => void; onFinish: () => void };
        act(() => {
            opts.onStart();
        });
        const inFlight = screen.getByTestId("btn-generate-summary-empty-state") as HTMLButtonElement;
        expect(inFlight.disabled).toBe(true);
        // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
        expect(inFlight.textContent).toBe("Queueing…");

        act(() => {
            opts.onFinish();
        });
        const afterFinish = screen.getByTestId("btn-generate-summary-empty-state") as HTMLButtonElement;
        expect(afterFinish.disabled).toBe(false);
        expect(afterFinish.textContent).toBe("Generate summary");
    });
});

// This button used to POST to /generate_summary, which only writes its audit entry on the
// regenerate path — so the common case spent money and left nothing in the activity log.
describe("BillCreatorLlmSummary completed-branch regenerate is audited (C2-WR-04)", () => {
    it("POSTs /regenerate_summary — the endpoint that writes the audit entry", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        const call = routerPost.mock.calls[0];
        expect(call[0]).toBe("/bills/42/regenerate_summary");
        expect(call[1]).toEqual({});
    });

    // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
    it("carries no testimony field, and offers none to type into", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Stored testimony." }) },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("textarea-supplemental-testimony")).toBeNull();

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][1]).not.toHaveProperty("supplemental_testimony");
    });
});

// The "working…" cover used to be aria-hidden, hiding busy state from screen readers
// without switching off the content — so Tab still reached Approve, Reject and Save
// mid-regenerate.
describe("BillCreatorLlmSummary in-flight regenerate overlay (C-WR-05)", () => {
    it("announces the busy state and makes the covered content inert", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        const { container } = render(<BillCreatorLlmSummary />);

        expect(container.querySelector("[inert]")).toBeNull();

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));
        const opts = routerPost.mock.calls[0][2] as { onStart: () => void; onFinish: () => void };
        act(() => {
            opts.onStart();
        });

        const overlay = screen.getByTestId("llm-regenerating-overlay");
        // <output> carries an implicit role="status" — no explicit role attribute needed.
        expect(overlay.tagName).toBe("OUTPUT");
        expect(screen.getByRole("status")).toBe(overlay);
        expect(overlay.getAttribute("aria-live")).toBe("polite");
        expect(overlay.hasAttribute("aria-hidden")).toBe(false);
        expect(container.querySelector("[inert]")).not.toBeNull();

        act(() => {
            opts.onFinish();
        });
        expect(screen.queryByTestId("llm-regenerating-overlay")).toBeNull();
        expect(container.querySelector("[inert]")).toBeNull();
    });
});

// The same cover goes up for a first Generate, since handleGenerate sets the same flag —
// and it used to say "Regenerating…" over a bill never summarized, read aloud verbatim.
describe("BillCreatorLlmSummary busy cover names what is happening", () => {
    it("says generating on a bill with no summary on it", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, generation_status: null, llm_summary: null }) },
        });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-generate-summary"));

        expect(screen.getByTestId("llm-regenerating-overlay").textContent).toContain("Generating summary");
        expect(screen.getByTestId("llm-regenerating-overlay").textContent).not.toContain("Regenerating");
    });

    it("says regenerating on a bill whose summary is about to be replaced", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));
        // Regenerate raises the cover through useRegenerateSummary's onStart,
        // not synchronously the way handleGenerate does — the same step the
        // example above this block takes.
        const opts = routerPost.mock.calls[0][2] as { onStart: () => void };
        act(() => {
            opts.onStart();
        });

        expect(screen.getByTestId("llm-regenerating-overlay").textContent).toContain("Regenerating summary");
    });
});

// The switch-off covers LlmSummaryStatusShell only; the stale header sits outside,
// greyed by `regenLoading` not `isRegenerating` — so Tab+Enter can fire a second paid
// POST that looks disabled.
describe("BillCreatorLlmSummary stale header shares the busy guard (C1-WR-02)", () => {
    const staleAndFailed = () =>
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: true, generation_status: "failed", llm_summary: null }) },
        });

    it("is reachable and enabled before anything is in flight", () => {
        staleAndFailed();
        render(<BillCreatorLlmSummary />);

        const cta = screen.getByTestId("btn-regenerate-from-latest-data");
        expect(cta.closest("[inert]")).toBeNull();
        expect(cta).not.toBeDisabled();
    });

    // Two separate tests: the header had two faults at once — outside the switched-off area, and fed the
    // wrong flag. Either fault alone still left the button clickable.
    it("goes inert once the failed branch's Retry starts a generation", () => {
        staleAndFailed();
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-retry-summary"));

        expect(screen.getByTestId("llm-regenerating-overlay")).toBeTruthy();
        expect(screen.getByTestId("btn-regenerate-from-latest-data").closest("[inert]")).not.toBeNull();
    });

    it("goes disabled once the failed branch's Retry starts a generation", () => {
        staleAndFailed();
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-retry-summary"));

        expect(screen.getByTestId("btn-regenerate-from-latest-data")).toBeDisabled();
    });

    it("comes back once the generation POST settles", () => {
        staleAndFailed();
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-retry-summary"));
        const opts = routerPost.mock.calls[0][2] as { onFinish: () => void };
        act(() => {
            opts.onFinish();
        });

        const cta = screen.getByTestId("btn-regenerate-from-latest-data");
        expect(cta.closest("[inert]")).toBeNull();
        expect(cta).not.toBeDisabled();
    });
});

// Every generate/regenerate button under LlmSummaryStatusShell greys out while the
// pipeline is queued/running, but only the empty state ever said why — and only for
// "running".
describe("BillCreatorLlmSummary explains a pipeline-disabled CTA on every branch (C1-IN-02)", () => {
    it.each(["queued", "running"] as const)(
        "explains a %s pipeline on the completed branch, where Regenerate is disabled",
        (status) => {
            usePageMock.mockReturnValue({
                props: { bill: makeBill({ stale: false, bill_pipeline_status: status }) },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("btn-regenerate-summary")).toBeDisabled();
            expect(screen.getByTestId("bill-pipeline-refresh-status")).toBeInTheDocument();
        },
    );

    it.each(["queued", "running"] as const)(
        "explains a %s pipeline on the failed branch, where Retry is disabled",
        (status) => {
            usePageMock.mockReturnValue({
                props: {
                    bill: makeBill({
                        stale: false,
                        generation_status: "failed",
                        llm_summary: null,
                        bill_pipeline_status: status,
                    }),
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("btn-retry-summary")).toBeDisabled();
            expect(screen.getByTestId("bill-pipeline-refresh-status")).toBeInTheDocument();
        },
    );

    it("says nothing while the pipeline is idle", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("btn-regenerate-summary")).not.toBeDisabled();
        expect(screen.queryByTestId("bill-pipeline-refresh-status")).toBeNull();
    });

    // A greyed-out button is skipped by Tab, so unless it points at the notice via
    // aria-describedby, the reason only exists for sighted users. These plus Generate are
    // every paid control here.
    describe.each([
        ["completed branch Regenerate", "btn-regenerate-summary", { stale: false } as const],
        [
            "failed branch Retry",
            "btn-retry-summary",
            { stale: false, generation_status: "failed", llm_summary: null } as const,
        ],
        ["stale header Regenerate", "btn-regenerate-from-latest-data", { stale: true } as const],
    ])("%s", (_label, testId, provisioning) => {
        it("points at the notice that explains why it is disabled", () => {
            usePageMock.mockReturnValue({
                props: { bill: makeBill({ ...provisioning, bill_pipeline_status: "running" }) },
            });
            render(<BillCreatorLlmSummary />);

            const notice = screen.getByTestId("bill-pipeline-refresh-status");
            expect(notice.id).toBe("bill-pipeline-busy-notice");
            expect(screen.getByTestId(testId)).toHaveAttribute("aria-describedby", notice.id);
        });

        it("says nothing about a pipeline that is not running", () => {
            usePageMock.mockReturnValue({ props: { bill: makeBill(provisioning) } });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId(testId)).not.toHaveAttribute("aria-describedby");
        });
    });
});

// Both writes told an expired page to "Reload and try again" — but Inertia's rescue
// redirect had already reloaded it. The operator was told to redo by hand what the
// browser did (C22-08).
describe("BillCreatorLlmSummary — an expired page asks for the click, not an F5", () => {
    const expiredPage = {
        url: "/admin/bill_creator/42/summary",
        props: { flash: { page_expired: true, alert: "The page expired, please try again." } },
    };

    // @lat: [[bill-creator-test-fixture-overrides#An expired-page Generate failure needs its own banner, since there is no onSuccess]]
    it("says at the Generate button when an expired page stopped the run starting", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, generation_status: null, llm_summary: null }) },
        });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-generate-summary"));
        const opts = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.(expiredPage);

        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/nothing was queued/i),
        });
    });

    // The other side of that wire: an ordinary landing stays silent, so a
    // handler toasting on every visit would fail here.
    it("says nothing at the Generate button when the visit was not refused", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, generation_status: null, llm_summary: null }) },
        });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-generate-summary"));
        const opts = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.({ url: "/admin/bill_creator/42/summary", props: { flash: {} } });

        expect(notifyMock).not.toHaveBeenCalled();
    });

    // Generate buys two model calls like Regenerate, but only Regenerate, Save and Clear
    // checked landedOnBillCreator — a lapsed admin session is a SUCCESSFUL visit, invisible
    // to onError.
    it("says at the Generate button when the visit landed off the Bill Creator (a lapsed admin session)", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, generation_status: null, llm_summary: null }) },
        });
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-generate-summary"));
        const opts = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };

        opts.onSuccess?.({ url: "/", props: { flash: {} } });

        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/sign in as an admin/i),
        });
    });
});

// @lat: [[bill-creator-test-fixture-overrides#The editable-summary test must drive the real parent, not a child fixture]]
describe("BillCreatorLlmSummary — the editable summary is the published one", () => {
    const renderWithBothSummaries = () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    summary: "The published summary an admin wrote by hand.",
                    llm_summary: "The model's draft, which nobody has published.",
                }),
            },
        });
        render(<BillCreatorLlmSummary />);
    };

    it("shows the published summary, not the model's draft", () => {
        renderWithBothSummaries();

        const textarea = screen.getByTestId("textarea-llm-summary") as HTMLTextAreaElement;
        expect(textarea.value).toBe("The published summary an admin wrote by hand.");
    });

    it("does not publish the model's draft when the operator saves without editing", () => {
        renderWithBothSummaries();

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/42",
            expect.objectContaining({
                summary: "The published summary an admin wrote by hand.",
                return_tab: "summary",
            }),
            expect.anything(),
        );
    });

    // @lat: [[bill-creator-test-fixture-overrides#Taking the model's draft must stay an explicit act, and the test proves click order]]
    it("puts the model's draft one explicit click away", () => {
        renderWithBothSummaries();

        fireEvent.click(screen.getByTestId("btn-use-llm-draft"));
        expect(routerPatch).not.toHaveBeenCalled();

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/42",
            expect.objectContaining({
                summary: "The model's draft, which nobody has published.",
                return_tab: "summary",
            }),
            expect.anything(),
        );
    });

    // The box took the server's value once, since the parent rebuilds on llm_generated_at —
    // but nothing stamps that on a summary write, so a Creator-tab save moves it without a
    // remount (C22-03).
    it("re-seeds the box when the published summary changes under an untouched field", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "The first published summary." }) },
        });
        const { rerender } = render(<BillCreatorLlmSummary />);
        expect(screen.getByTestId("textarea-llm-summary")).toHaveValue("The first published summary.");

        // Another admin saves a correction from the Creator tab. The poll
        // delivers it; llm_generated_at does not move, so there is no remount.
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "A correction saved from the Creator tab." }) },
        });
        rerender(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("textarea-llm-summary")).toHaveValue("A correction saved from the Creator tab.");
    });

    // The stale box is only half the harm. Saving it publishes the old text
    // back over the correction, which is the loss C21-02 was filed about,
    // arriving through a different door.
    it("does not write a superseded summary back over the server's newer one", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "The first published summary." }) },
        });
        const { rerender } = render(<BillCreatorLlmSummary />);

        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "A correction saved from the Creator tab." }) },
        });
        rerender(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-save-summary"));

        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/42",
            expect.objectContaining({
                summary: "A correction saved from the Creator tab.",
                return_tab: "summary",
            }),
            expect.anything(),
        );
    });

    // The check that makes taking the server's value safe: an operator mid-type must not
    // lose their words to a background refresh.
    it("keeps a half-typed edit when the published summary changes underneath", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "The first published summary." }) },
        });
        const { rerender } = render(<BillCreatorLlmSummary />);

        fireEvent.change(screen.getByTestId("textarea-llm-summary"), { target: { value: "Half-written rewrite" } });

        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, summary: "A correction saved from the Creator tab." }) },
        });
        rerender(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("textarea-llm-summary")).toHaveValue("Half-written rewrite");
    });

    // The counter-example: when the published summary already IS the draft, there's nothing to choose
    // between, so offering the choice would be noise on every completed bill.
    it("offers nothing to copy when the published summary already matches the draft", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    summary: "One and the same text.",
                    llm_summary: "One and the same text.",
                }),
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("btn-use-llm-draft")).toBeNull();
    });
});

// @lat: [[bill-summary-run-button-unification#Call-site echoes]]
describe("what a summary button says while its request is in flight", () => {
    // Sends the click, works the confirmation if there is one, and starts the
    // request without finishing it — the window the operator is looking at.
    const clickAndStart = (testId: string, confirm: boolean) => {
        fireEvent.click(screen.getByTestId(testId));
        if (confirm) fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));
        const opts = routerPost.mock.calls[0][2] as { onStart?: () => void };
        if (opts.onStart) act(() => opts.onStart?.());
        return screen.getByTestId(testId) as HTMLButtonElement;
    };

    it("says it on the completed view's Regenerate summary button", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorLlmSummary />);

        expect(clickAndStart("btn-regenerate-summary", true).textContent).toContain("Queueing");
    });

    it("says it on the generate branch's Generate summary button", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    generation_status: null,
                    llm_summary: null,
                    draft_org_positions: [],
                }),
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(clickAndStart("btn-generate-summary", false).textContent).toContain("Queueing");
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#What the tab says about a run it did not finish]]
    it("says it on the out-of-date header's Regenerate from latest data button", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: true }) } });
        render(<BillCreatorLlmSummary />);

        expect(clickAndStart("btn-regenerate-from-latest-data", true).textContent).toContain("Queueing");
    });
});

// The operator's per-run model choice reaches only the button they happen to be
// standing in front of if it is not threaded to every branch that starts a run.
describe("BillCreatorLlmSummary — the per-run model on every control that starts a run", () => {
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#The choice is held above every control that starts a run]]
    const options = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
    ];

    const servePage = (bill: unknown, currentModel: string | null = "claude-haiku-5-5") =>
        usePageMock.mockReturnValue({
            props: { bill, summary_model_options: options, current_summarization_model: currentModel },
        });

    const pick = (model: string) =>
        fireEvent.change(screen.getByTestId("select-summary-model"), { target: { value: model } });

    // recallSummaryModel reads sessionStorage, so a choice made in one example
    // would otherwise seed the next one.
    beforeEach(() => window.sessionStorage.clear());
    afterEach(() => window.sessionStorage.clear());

    it("sends the picked model with the completed view's Regenerate summary", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends no model key at all when the standing default is one the server no longer offers", () => {
        servePage(makeBill({ stale: false }), "claude-retired-1");
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][1]).toEqual({});
    });

    it("sends the picked model with the stale header's Regenerate from latest data", () => {
        servePage(makeBill({ stale: true }));
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends the picked model with the generate branch's Generate summary", () => {
        servePage(makeBill({ stale: false, generation_status: null, llm_summary: null, draft_org_positions: [] }));
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-generate-summary"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends the picked model with the failed branch's Retry", () => {
        servePage(makeBill({ stale: false, generation_status: "failed", llm_summary: null, draft_org_positions: [] }));
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-retry-summary"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends the picked model when an abandoned run is replaced with a new one", () => {
        servePage(
            makeBill({
                stale: false,
                generation_status: "generating",
                reclaimable: true,
                llm_summary: null,
                draft_org_positions: [],
            }),
        );
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-start-new-run"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });

    it("sends the picked model with the empty state's Generate summary", () => {
        servePage({ id: 42, external_id: "HB123", bill_llm_provisioning: null, bill_pipeline_refresh: null });
        render(<BillCreatorLlmSummary />);

        pick("claude-opus-5-5");
        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "claude-opus-5-5" });
    });
});

describe("BillCreatorLlmSummary — candidate OpenRouter model choices", () => {
    const candidateOptions = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-sonnet-5-5", label: "Sonnet 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
        { id: "Deepseek Pro Latest", label: "Deepseek Pro Latest" },
        { id: "Deepseek Flash Latest", label: "Deepseek Flash Latest" },
        { id: "OpenRouter Auto", label: "OpenRouter Auto" },
    ];

    const serveCandidatePage = (bill: unknown, currentModel: string | null = "claude-haiku-5-5") =>
        usePageMock.mockReturnValue({
            props: { bill, summary_model_options: candidateOptions, current_summarization_model: currentModel },
        });

    const pickModel = (model: string) =>
        fireEvent.change(screen.getByTestId("select-summary-model"), { target: { value: model } });

    beforeEach(() => {
        window.sessionStorage.clear();
        routerPost.mockClear();
    });
    afterEach(() => {
        window.sessionStorage.clear();
        routerPost.mockClear();
    });

    it("sends candidate OpenRouter model with the completed view's Regenerate summary", () => {
        serveCandidatePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        pickModel("Deepseek Pro Latest");
        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "Deepseek Pro Latest" });
    });

    it("sends candidate OpenRouter model with the stale header's Regenerate from latest data", () => {
        serveCandidatePage(makeBill({ stale: true }));
        render(<BillCreatorLlmSummary />);

        pickModel("Deepseek Flash Latest");
        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "Deepseek Flash Latest" });
    });

    it("sends candidate OpenRouter model with the generate branch's Generate summary", () => {
        serveCandidatePage(
            makeBill({ stale: false, generation_status: null, llm_summary: null, draft_org_positions: [] }),
        );
        render(<BillCreatorLlmSummary />);

        pickModel("OpenRouter Auto");
        fireEvent.click(screen.getByTestId("btn-generate-summary"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "OpenRouter Auto" });
    });

    it("sends candidate OpenRouter model with the failed branch's Retry", () => {
        serveCandidatePage(
            makeBill({ stale: false, generation_status: "failed", llm_summary: null, draft_org_positions: [] }),
        );
        render(<BillCreatorLlmSummary />);

        pickModel("Deepseek Pro Latest");
        fireEvent.click(screen.getByTestId("btn-retry-summary"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "Deepseek Pro Latest" });
    });

    it("sends candidate OpenRouter model when an abandoned run is replaced with a new one", () => {
        serveCandidatePage(
            makeBill({
                stale: false,
                generation_status: "generating",
                reclaimable: true,
                llm_summary: null,
                draft_org_positions: [],
            }),
        );
        render(<BillCreatorLlmSummary />);

        pickModel("Deepseek Flash Latest");
        fireEvent.click(screen.getByTestId("btn-start-new-run"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/generate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "Deepseek Flash Latest" });
    });

    it("sends candidate OpenRouter model with the empty state's Generate summary", () => {
        serveCandidatePage({ id: 42, external_id: "HB123", bill_llm_provisioning: null, bill_pipeline_refresh: null });
        render(<BillCreatorLlmSummary />);

        pickModel("OpenRouter Auto");
        fireEvent.click(screen.getByTestId("btn-generate-summary-empty-state"));

        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({ summarization_model: "OpenRouter Auto" });
    });
});

describe("BillCreatorLlmSummary revision history placement", () => {
    it("renders revision history for a persisted bill without provisioning", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 42,
                    external_id: "HB123",
                    bill_llm_provisioning: null,
                    bill_pipeline_refresh: null,
                    summary: "Manual summary",
                },
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
    });

    it("does not render revision history for an unpersisted bill (no billId or billId 0)", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: {
                    id: 0,
                    external_id: "NEW",
                    bill_llm_provisioning: null,
                    bill_pipeline_refresh: null,
                    summary: "",
                },
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("toggle-revision-history")).toBeNull();
    });

    it("renders revision history for a persisted bill with completed provisioning", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({ stale: false }),
            },
        });
        render(<BillCreatorLlmSummary />);

        expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
    });
});

describe("BillCreatorLlmSummary — summary regeneration modal instructions", () => {
    const testOptions = [
        { id: "claude-haiku-5-5", label: "Haiku 5.5" },
        { id: "claude-opus-5-5", label: "Opus 5.5" },
    ];

    const servePage = (bill: unknown, currentModel: string | null = "claude-haiku-5-5", options = testOptions) =>
        usePageMock.mockReturnValue({
            props: { bill, summary_model_options: options, current_summarization_model: currentModel },
        });

    beforeEach(() => {
        window.sessionStorage.clear();
        clearRetainedSummaryInstructions();
        routerPost.mockReset();
    });

    afterEach(() => {
        window.sessionStorage.clear();
        clearRetainedSummaryInstructions();
        cleanup();
    });

    it("renders the confirmation dialog with accessible label, textarea, placeholder, helper text, and counter", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));

        const textarea = screen.getByLabelText(/Additional instructions \(optional\)/i);
        expect(textarea).toBeInTheDocument();
        expect(textarea).toHaveAttribute("id", "summary-instructions");
        expect(textarea).toHaveAttribute(
            "placeholder",
            "e.g. Request a missing property tax rate if stated in the bill",
        );

        expect(screen.getByText(/apply to this regeneration/i)).toBeInTheDocument();
        expect(screen.getByText(/supported by source material/i)).toBeInTheDocument();
        expect(screen.getByText(/0 \/ 2,000/)).toBeInTheDocument();
    });

    it("sends summary_instructions beside the chosen model with completed view's Regenerate summary", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, {
            target: { value: "Note the 2.24% property tax rate mentioned in the testimony" },
        });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-haiku-5-5",
            summary_instructions: "Note the 2.24% property tax rate mentioned in the testimony",
        });
    });

    it("sends summary_instructions with stale header's Regenerate from latest data", () => {
        servePage(makeBill({ stale: true }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-from-latest-data"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Focus on the fiscal note impact" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][0]).toBe("/bills/42/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-haiku-5-5",
            summary_instructions: "Focus on the fiscal note impact",
        });
    });

    it("omits summary_instructions when empty or whitespace-only", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "   \t\n  " } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][1]).toEqual({
            summarization_model: "claude-haiku-5-5",
        });
    });

    it("accepts exactly 2,000 Unicode code points with astral character parity (1,999 ASCII + U+1F600)", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        const validInstructions = "a".repeat(1999) + "😀";
        fireEvent.change(textarea, { target: { value: validInstructions } });

        expect(screen.getByText(/2,000 \/ 2,000/)).toBeInTheDocument();
        expect(screen.queryByRole("alert")).toBeNull();

        const confirmBtn = screen.getByTestId("btn-confirm-dialog-confirm");
        expect(confirmBtn).not.toBeDisabled();

        fireEvent.click(confirmBtn);

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][1]).toMatchObject({
            summary_instructions: validInstructions,
        });
    });

    it("rejects 2,001 Unicode code points (2,000 ASCII + U+1F600), shows actionable error and disables confirm button without silent clipping", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        const overLimitInstructions = "a".repeat(2000) + "😀";
        fireEvent.change(textarea, { target: { value: overLimitInstructions } });

        expect(textarea).toHaveValue(overLimitInstructions);
        expect(screen.getByText(/2,001 \/ 2,000/)).toBeInTheDocument();

        const error = screen.getByRole("alert");
        expect(error).toBeInTheDocument();
        expect(error).toHaveAttribute("id", "summary-instructions-error");

        const confirmBtn = screen.getByTestId("btn-confirm-dialog-confirm");
        expect(confirmBtn).toBeDisabled();

        fireEvent.click(confirmBtn);
        expect(routerPost).not.toHaveBeenCalled();
    });

    it("discards unsubmitted draft instructions on Cancel", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Draft to discard" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-cancel"));

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("preserves typed instructions through same-bill polling rerender", () => {
        servePage(makeBill({ stale: false }));
        const { rerender } = render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "In-progress draft" } });

        servePage(makeBill({ stale: false, summary: "Updated summary from poll" }));
        rerender(<BillCreatorLlmSummary />);

        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("In-progress draft");
    });

    it("retains typed instructions for retry after server refusal onError", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Instructions to retain after refusal" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        const postOpts = routerPost.mock.calls[0][2] as {
            onError?: (errors: unknown) => void;
        };
        act(() => postOpts.onError?.({ generation: "Server busy" }));

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("Instructions to retain after refusal");
    });

    it("clears retained instructions after accepted enqueue", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Instructions queued" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        const postOpts = routerPost.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
        act(() =>
            postOpts.onSuccess?.({
                url: "/admin/bill_creator/42/summary",
                props: {},
            }),
        );

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("resets draft instructions when switching bills (no cross-bill leakage)", () => {
        servePage(makeBill({ stale: false }));
        const { rerender } = render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Bill 42 instructions" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        const postOpts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        act(() => postOpts.onError?.({ generation: "Refused" }));

        servePage({ ...makeBill({ stale: false }), id: 43 });
        rerender(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("prevents double submission while request is in flight", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Run once" } });

        const confirmBtn = screen.getByTestId("btn-confirm-dialog-confirm");
        fireEvent.click(confirmBtn);

        expect(routerPost).toHaveBeenCalledTimes(1);

        const postOpts = routerPost.mock.calls[0][2] as { onStart?: () => void };
        act(() => postOpts.onStart?.());

        fireEvent.click(confirmBtn);
        expect(routerPost).toHaveBeenCalledTimes(1);
    });

    it("clears retained draft when user erases textarea and confirms, even if subsequent request is refused", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        let textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Instruction A" } });
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][1]).toMatchObject({
            summary_instructions: "Instruction A",
        });

        const postOpts1 = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        act(() => postOpts1.onError?.({ generation: "Server busy" }));

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        textarea = screen.getByLabelText(/Additional instructions/i);
        expect(textarea).toHaveValue("Instruction A");

        fireEvent.change(textarea, { target: { value: "" } });
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        expect(routerPost).toHaveBeenCalledTimes(2);
        expect(routerPost.mock.calls[1][1]).not.toHaveProperty("summary_instructions");

        const postOpts2 = routerPost.mock.calls[1][2] as { onError?: (errors: unknown) => void };
        act(() => postOpts2.onError?.({ generation: "Server busy again" }));

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("discards unsubmitted draft instructions on Escape", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Draft to discard on escape" } });

        fireEvent.keyDown(screen.getByTestId("dialog"), { key: "Escape" });

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("discards unsubmitted draft instructions on outside click", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Draft to discard on outside click" } });

        fireEvent.click(screen.getByTestId("dialog-backdrop"));

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("closes open dialog and resets draft instructions when switching bills while dialog is open", () => {
        servePage(makeBill({ stale: false }));
        const { rerender } = render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Bill 42 draft in open dialog" } });

        servePage({ ...makeBill({ stale: false }), id: 43 });
        rerender(<BillCreatorLlmSummary />);

        expect(screen.queryByTestId("dialog")).toBeNull();

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));
        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(routerPost.mock.calls[0][0]).toBe("/bills/43/regenerate_summary");
        expect(routerPost.mock.calls[0][1]).not.toHaveProperty("summary_instructions");
    });

    it("discards retained draft when component unmounts and remounts for the same bill", () => {
        servePage(makeBill({ stale: false }));
        const { unmount } = render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Instruction to discard on unmount" } });
        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        const postOpts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        act(() => postOpts.onError?.({ generation: "Refused" }));

        unmount();

        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue("");
    });

    it("retains typed instructions for retry after transport failure onNetworkError", () => {
        servePage(makeBill({ stale: false }));
        render(<BillCreatorLlmSummary />);

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        const textarea = screen.getByLabelText(/Additional instructions/i);
        fireEvent.change(textarea, { target: { value: "Instructions to retain after transport error" } });

        fireEvent.click(screen.getByTestId("btn-confirm-dialog-confirm"));

        const postOpts = routerPost.mock.calls[0][2] as {
            onNetworkError?: () => void;
        };
        expect(typeof postOpts.onNetworkError).toBe("function");
        act(() => postOpts.onNetworkError?.());

        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: expect.stringMatching(/network error/i),
        });

        fireEvent.click(screen.getByTestId("btn-regenerate-summary"));
        expect(screen.getByLabelText(/Additional instructions/i)).toHaveValue(
            "Instructions to retain after transport error",
        );
    });
});
