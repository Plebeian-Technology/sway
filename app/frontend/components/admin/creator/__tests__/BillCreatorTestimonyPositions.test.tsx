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
    Dialog: ({ children, open }: { children: React.ReactNode; open?: boolean }) =>
        open ? <div data-testid="dialog">{children}</div> : null,
    DialogContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
    DialogFooter: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    DialogTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
}));

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
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
import BillCreatorTestimonyPositions from "app/frontend/components/admin/creator/BillCreatorTestimonyPositions";
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

// @lat: [[bill-creator-test-fixture-overrides#Draft position card indices are checked against the full server-side list]]
describe("BillCreatorTestimonyPositions draft org position indices (C-CR-04)", () => {
    it("passes the RAW draft_org_positions index to each card, not the filtered render position", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    draft_org_positions: [
                        // A leftover from before rejected positions were
                        // deleted outright: a real entry carrying the flag,
                        // which is the only shape the server could have
                        // written.
                        { org_name: "Old Org", stance: "support", summary: "withdrawn", rejected: true },
                        { org_name: "Org A", stance: "support", summary: "supports" },
                        { org_name: "Org B", stance: "oppose", summary: "opposes" },
                    ],
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const cards = screen.getAllByTestId("org-position-card");
        expect(cards.map((c) => c.textContent)).toEqual(["Org A", "Org B"]);
        expect(cards.map((c) => c.getAttribute("data-index"))).toEqual(["1", "2"]);
    });
});

// @lat: [[bill-creator-test-fixture-overrides#The positions-failure notice must reach the completed branch too]]
describe("BillCreatorTestimonyPositions positions-failure notice on a completed row (B-WR-01)", () => {
    it("surfaces generation_error on the completed branch", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    generation_error: "positions call failed (the summary is valid): 429 rate limited",
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const notice = screen.getByTestId("llm-positions-error");
        expect(notice.textContent ?? "").toContain("positions call failed (the summary is valid): 429 rate limited");
    });

    it("renders no notice on a completed row with no generation_error", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.queryByTestId("llm-positions-error")).toBeNull();
    });
});

// @lat: [[bill-creator-test-fixture-overrides#A positions-call failure does not make a good summary look ungenerated]]
describe("BillCreatorTestimonyPositions positions-failure notice truthfulness (C2-WR-01)", () => {
    const positionsError = "positions call failed (the summary is valid): 429 rate limited";

    it("says the drafts were not REFRESHED, and dates them, when an earlier run's drafts survive", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    generation_error: positionsError,
                    draft_org_positions: [{ org_name: "ACME", stance: "support", summary: "supports" }],
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const notice = screen.getByTestId("llm-positions-error");
        const text = notice.textContent ?? "";
        expect(text).toContain("Draft positions were not refreshed");
        // "from before this run", not "from an earlier run": kept cards could be a paste,
        // and llm_provider is overwritten before the positions call raises, so nothing
        // tells the two apart (FE28-03).
        expect(text).toContain("the draft positions below are from before this run");
        expect(text).not.toContain("earlier run");
        expect(text).not.toContain("were not generated");
        // The kept cards are still on screen, which is the point.
        expect(screen.getAllByTestId("org-position-card").length).toBe(1);
    });

    it("keeps the 'were not generated' copy when no drafts survive", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({ stale: false, generation_error: positionsError, draft_org_positions: [] }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const text = screen.getByTestId("llm-positions-error").textContent ?? "";
        expect(text).toContain("Draft positions were not generated");
        expect(text).not.toContain("from an earlier run");
    });

    // C21-02 moved the editable box to bills.summary, but this notice used to say "the summary above" —
    // wrong for an ingested bill, which reads the untouched box as this run's output. (FE26-03)
    it("names the summary this run produced, not the box above it", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({ stale: false, generation_error: positionsError, draft_org_positions: [] }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const notice = screen.getByTestId("llm-positions-error");
        expect(notice.textContent ?? "").not.toMatch(/summary above is unaffected/i);
        expect(notice).toHaveTextContent(/the summary this run produced is unaffected/i);
        expect(notice).toHaveTextContent(/published summary, which no run changes/i);
    });

    // "the box above" pointed by direction, and SupplementalTestimonyField was later
    // inserted between box and notice, so "above" named the wrong field. Naming it
    // directly can't go stale.
    it("names the published summary field instead of pointing 'above' at it", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({ stale: false, generation_error: positionsError, draft_org_positions: [] }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        const notice = screen.getByTestId("llm-positions-error");
        expect(notice.textContent ?? "").not.toMatch(/the box above holds/i);
        expect(notice).toHaveTextContent(/Public summary/);
    });

    it("renders no notice on a `skipped` row, whose generation_error is not a positions error", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    generation_status: "skipped",
                    llm_summary: "Prior summary survives the skip.",
                    generation_error: "Prior run timeout",
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.queryByTestId("llm-positions-error")).toBeNull();
    });
});

// @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
describe("BillCreatorTestimonyPositions supplemental testimony — Clear + re-seed", () => {
    it("seeds the textarea from the server value", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Stored testimony." }) },
        });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("textarea-supplemental-testimony")).toHaveValue("Stored testimony.");
    });

    // The component only rebuilds on llm_generated_at, while the 5s poll refreshes bill
    // data WITHOUT rebuilding it — a tab opened while the value was empty kept showing an
    // empty box forever.
    it("re-seeds when the server value changes under an untouched field", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false, supplemental_testimony: null }) } });
        const { rerender } = render(<BillCreatorTestimonyPositions />);
        expect(screen.getByTestId("textarea-supplemental-testimony")).toHaveValue("");

        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Pasted by another operator." }) },
        });
        rerender(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("textarea-supplemental-testimony")).toHaveValue("Pasted by another operator.");
    });

    // The check that makes taking the server's value safe: an operator in the
    // middle of typing does not lose their words to a background refresh.
    it("keeps unsaved local edits when the server value changes underneath", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false, supplemental_testimony: null }) } });
        const { rerender } = render(<BillCreatorTestimonyPositions />);

        const textarea = screen.getByTestId("textarea-supplemental-testimony");
        fireEvent.change(textarea, { target: { value: "Half-typed note" } });

        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Saved by someone else." }) },
        });
        rerender(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("textarea-supplemental-testimony")).toHaveValue("Half-typed note");
    });

    it("renders no Clear button when the server holds nothing", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false, supplemental_testimony: null }) } });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.queryByTestId("btn-clear-supplemental-testimony")).toBeNull();
    });

    // This sends a PATCH, not a POST to generate or regenerate. Both of those
    // spend an LLM call, and clearing text that was pasted by mistake must not
    // cost anyone a regeneration.
    it("Clear PATCHes the dedicated endpoint with the explicit clear flag", () => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Stored testimony." }) },
        });
        render(<BillCreatorTestimonyPositions />);

        fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));

        expect(routerPatch).toHaveBeenCalledWith(
            "/bills/42/supplemental_testimony",
            { clear_supplemental_testimony: true },
            expect.anything(),
        );
        expect(routerPost).not.toHaveBeenCalled();
        // @lat: [[bill-creator-test-fixture-overrides#Clear-testimony confirmation is skipped when the bill has no drafts]]
        expect(confirmMock).not.toHaveBeenCalled();
    });

    // @lat: [[bill-creator-test-fixture-overrides#The no-testimony notice fixture must type has_testimony, not leave it undefined]]
    it("draws the no-testimony notice when the server says there is none", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    has_testimony: false,
                    draft_org_positions: [{ org_name: "Org A", stance: "support", summary: "supports" }],
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("llm-no-testimony")).toBeInTheDocument();
    });

    // Until Save existed, Generate/Regenerate carried the typed value — each buying two
    // model calls, so pasting meant paying to keep it, and a pipeline run switched off
    // every paid button.
    describe("saving the typed testimony on its own", () => {
        it("sends the typed value to the free endpoint", async () => {
            usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false, supplemental_testimony: null }) } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Testimony of ACME, submitted in support." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            expect(routerPatch).toHaveBeenCalledWith(
                "/bills/42/supplemental_testimony",
                { supplemental_testimony: "Testimony of ACME, submitted in support." },
                expect.objectContaining({ preserveScroll: true }),
            );
        });

        // The button is the unsaved-changes signal, so it must not sit there
        // when the box already matches the server.
        it("offers no Save button until the text differs from what is stored", () => {
            usePageMock.mockReturnValue({
                props: { bill: makeBill({ stale: false, supplemental_testimony: "Already stored." }) },
            });
            render(<BillCreatorTestimonyPositions />);

            expect(screen.queryByTestId("btn-save-supplemental-testimony")).toBeNull();
        });
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
    describe("warns before clearing when drafts would be blocked", () => {
        const billWithDrafts = () =>
            makeBill({
                stale: false,
                supplemental_testimony: "Stored testimony.",
                draft_org_positions: [
                    { org_name: "ACME", stance: "support", summary: "Backs it." },
                    { org_name: "Beta", stance: "oppose", summary: "Against it." },
                ],
            });

        it("does not clear when the operator cancels", async () => {
            confirmMock.mockResolvedValue(false);
            usePageMock.mockReturnValue({ props: { bill: billWithDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));
            });

            expect(confirmMock).toHaveBeenCalledTimes(1);
            expect(routerPatch).not.toHaveBeenCalled();
        });

        it("names how many positions it will block, and that re-pasting will not undo it", async () => {
            usePageMock.mockReturnValue({ props: { bill: billWithDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));
            });

            const options = confirmMock.mock.calls[0][0];
            expect(options.description).toContain("2 draft positions");
            expect(options.description).toContain("no longer be approved");
            // "on this bill", never "below": Clear also sits on the generate branch, which
            // draws no cards — a regeneration can be pending with the previous run's
            // drafts still stored, invisible on screen.
            expect(options.description).toContain("on this bill");
            expect(options.description).not.toContain("below");
            expect(options.description).toMatch(/pasting the testimony back does not restore them/i);
            expect(options.tone).toBe("destructive");
            expect(routerPatch).toHaveBeenCalled();
        });
    });

    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Supplemental testimony is replaced, never appended]]
    describe("warns before saving when the save would block drafts", () => {
        const billWithDrafts = () =>
            makeBill({
                stale: false,
                supplemental_testimony: "Stored testimony.",
                draft_org_positions: [
                    { org_name: "ACME", stance: "support", summary: "Backs it." },
                    { org_name: "Beta", stance: "oppose", summary: "Against it." },
                ],
            });

        it("warns and blocks the save when the operator cancels", async () => {
            confirmMock.mockResolvedValue(false);
            usePageMock.mockReturnValue({ props: { bill: billWithDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Entirely different testimony." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            expect(confirmMock).toHaveBeenCalledTimes(1);
            expect(routerPatch).not.toHaveBeenCalled();
        });

        it("names how many positions it will block, same as Clear", async () => {
            usePageMock.mockReturnValue({ props: { bill: billWithDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Entirely different testimony." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            const options = confirmMock.mock.calls[0][0];
            expect(options.description).toContain("2 draft positions");
            expect(options.description).toContain("no longer be approved");
            expect(options.tone).toBe("destructive");
            expect(routerPatch).toHaveBeenCalled();
        });

        // The covariant half: same bill and drafts, new text still holds every word of the old — an append,
        // not a replace, so the client must not warn as if the server will retract.
        it("does not warn when the save only appends to the stored testimony", async () => {
            usePageMock.mockReturnValue({ props: { bill: billWithDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Stored testimony. Plus a paragraph." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            expect(confirmMock).not.toHaveBeenCalled();
            expect(routerPatch).toHaveBeenCalled();
        });

        it("does not prompt confirmation when saving supplemental testimony if all draft positions are news-sourced", async () => {
            const billWithNewsDrafts = () =>
                makeBill({
                    stale: false,
                    supplemental_testimony: "Stored testimony.",
                    draft_org_positions: [
                        {
                            org_name: "News Org",
                            stance: "support",
                            summary: "News summary",
                            bill_news_article_id: 101,
                            text_version_id: 201,
                            evidence_excerpt: "Direct quote",
                        },
                    ],
                });

            usePageMock.mockReturnValue({ props: { bill: billWithNewsDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Completely different testimony text." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            expect(confirmMock).not.toHaveBeenCalled();
            expect(routerPatch).toHaveBeenCalledWith(
                "/bills/42/supplemental_testimony",
                { supplemental_testimony: "Completely different testimony text." },
                expect.anything(),
            );
        });

        it("warns about only hearing-testimony-sourced drafts when drafts are mixed", async () => {
            const billWithMixedDrafts = () =>
                makeBill({
                    stale: false,
                    supplemental_testimony: "Stored testimony.",
                    draft_org_positions: [
                        {
                            org_name: "Hearing Org 1",
                            stance: "support",
                            summary: "Hearing 1",
                            bill_news_article_id: null,
                        },
                        {
                            org_name: "News Org",
                            stance: "support",
                            summary: "News 1",
                            bill_news_article_id: 101,
                            text_version_id: 201,
                            evidence_excerpt: "Direct quote",
                        },
                    ],
                });

            usePageMock.mockReturnValue({ props: { bill: billWithMixedDrafts() } });
            render(<BillCreatorTestimonyPositions />);

            await act(async () => {
                fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
                    target: { value: "Completely different testimony text." },
                });
            });
            await act(async () => {
                fireEvent.click(screen.getByTestId("btn-save-supplemental-testimony"));
            });

            expect(confirmMock).toHaveBeenCalledTimes(1);
            const options = confirmMock.mock.calls[0][0];
            expect(options.description).toContain("1 draft position on this bill was written from");
            expect(routerPatch).toHaveBeenCalled();
        });
    });

    // @lat: [[bill-creator-test-fixture-overrides#Clear supplemental testimony must keep scroll and report a failed PATCH]]
    describe("Clear supplemental testimony holds the viewport and reports a failure (C1-i6-IN-03 / EXT-02)", () => {
        const clearOptions = () => {
            usePageMock.mockReturnValue({
                props: { bill: makeBill({ stale: false, supplemental_testimony: "Stored testimony." }) },
            });
            render(<BillCreatorTestimonyPositions />);
            fireEvent.click(screen.getByTestId("btn-clear-supplemental-testimony"));

            return routerPatch.mock.calls[0][2] as {
                preserveScroll?: boolean;
                onError?: (errors: unknown) => void;
            };
        };

        it("does not throw the operator back to the top of the page", () => {
            expect(clearOptions().preserveScroll).toBe(true);
        });

        it("tells the operator when the clear did not happen", () => {
            const onError = clearOptions().onError;
            expect(typeof onError).toBe("function");

            onError?.({});

            expect(notifyMock).toHaveBeenCalledWith(
                expect.objectContaining({ level: "error", title: expect.stringMatching(/testimony/i) }),
            );
        });
    });
});

describe("BillCreatorTestimonyPositions — an expired page asks for the click, not an F5", () => {
    const optionsFor = (testId: string) => {
        usePageMock.mockReturnValue({
            props: { bill: makeBill({ stale: false, supplemental_testimony: "Stored testimony." }) },
        });
        render(<BillCreatorTestimonyPositions />);
        // The Save button appears only once the box differs from the stored
        // value, so give it something to save.
        fireEvent.change(screen.getByTestId("textarea-supplemental-testimony"), {
            target: { value: "Stored testimony. Plus a paragraph." },
        });
        fireEvent.click(screen.getByTestId(testId));

        return routerPatch.mock.calls[0][2] as {
            onSuccess?: (page: { url: string; props: Record<string, unknown> }) => void;
        };
    };

    const expiredPage = {
        url: "/admin/bill_creator/42/summary",
        props: { flash: { page_expired: true, alert: "The page expired, please try again." } },
    };

    it.each([
        ["saving the testimony", "btn-save-supplemental-testimony", /not saved/i],
        ["clearing the testimony", "btn-clear-supplemental-testimony", /not cleared/i],
    ])("says what was not written and never says reload, when %s", (_label, testId, outcome) => {
        optionsFor(testId).onSuccess?.(expiredPage);

        const errors = notifyMock.mock.calls
            .map((call) => call[0] as { level: string; title: string })
            .filter((arg) => arg.level === "error");
        expect(errors).toHaveLength(1);
        expect(errors[0].title).toMatch(outcome);
        expect(errors[0].title).not.toMatch(/reload|refresh/i);
    });
});

// @lat: [[bill-creator-positions-tab#Why positions are a tab of their own]]
describe("BillCreatorTestimonyPositions — the region the summary tab gave up", () => {
    it("carries the attachment warning that used to sit on the summary tab", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({
                    stale: false,
                    testimony_attachments: [
                        {
                            filename: "testimony-1.pdf",
                            download_status: "failed",
                            extraction_status: "not_attempted",
                            error: "timeout",
                        },
                    ],
                }),
            },
        });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("llm-testimony-attachment-warning")).toBeInTheDocument();
    });

    it("draws the whole region under one Testimony and positions heading", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("region-testimony-and-positions")).toBeInTheDocument();
        expect(screen.getByRole("heading", { name: "Testimony and positions", level: 3 })).toBeTruthy();
        expect(screen.getByTestId("textarea-supplemental-testimony")).toBeInTheDocument();
    });

    // @lat: [[bill-creator-positions-tab#Saving testimony is what commits it to a run]]
    it("says Save is what a run reads, and that the summary model never sees the testimony", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorTestimonyPositions />);

        const note = screen.getByTestId("positions-testimony-save-first").textContent ?? "";
        expect(note).toMatch(/never reaches the summary model/i);
        expect(note).toMatch(/Save testimony/);
    });

    it("renders no summary box, and no control that starts a run", () => {
        usePageMock.mockReturnValue({ props: { bill: makeBill({ stale: false }) } });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.queryByTestId("textarea-llm-summary")).toBeNull();
        expect(screen.queryByTestId("btn-regenerate-summary")).toBeNull();
        expect(screen.queryByTestId("btn-generate-summary")).toBeNull();
    });

    it("renders PublicTestimonySection when public_testimony_counts is provided and opens the modal with canOverrideStance", () => {
        usePageMock.mockReturnValue({
            props: {
                bill: makeBill({ stale: false }),
                public_testimony_counts: { total: 2, support: 1, oppose: 1, neutral: 0 },
                public_testimony_letters: [
                    { position: 1, label: "Constituent Letter #1", stance: "support", body_text: "I support this." },
                    { position: 2, label: "Constituent Letter #2", stance: "oppose", body_text: "I oppose this." },
                ],
            },
        });
        render(<BillCreatorTestimonyPositions />);

        expect(screen.getByTestId("public-testimony-section")).toBeInTheDocument();
        fireEvent.click(screen.getByTestId("btn-browse-public-testimony"));
        expect(screen.getByTestId("select-letter-stance-1")).toBeInTheDocument();
    });
});
