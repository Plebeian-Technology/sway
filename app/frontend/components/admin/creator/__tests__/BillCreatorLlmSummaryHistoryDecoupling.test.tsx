import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
// Adversarial test suite for exposing summary history without LLM provisioning.

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerReload = vi.fn<(...args: unknown[]) => void>();
const usePageMock = vi.fn<() => Record<string, unknown>>();

vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));

vi.mock("app/frontend/sway_utils", () => ({
    notify: vi.fn<(options: Record<string, unknown>) => void>(),
}));

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<() => Promise<boolean>>().mockResolvedValue(true),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement>) => (
        <span data-testid="badge" {...props}>
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

vi.mock("app/frontend/components/admin/creator/BillCreatorLlmSummaryBadge", () => ({
    default: ({ status }: { status: string | null }) => <div data-testid="status-badge">{String(status)}</div>,
}));

vi.mock("app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge", () => ({
    default: ({ status }: { status: string | null }) => <div data-testid="pipeline-status-badge">{String(status)}</div>,
}));

vi.mock("app/frontend/components/admin/creator/llm-summary/SummaryModelPicker", () => ({
    default: () => null,
}));

import BillCreatorLlmSummary from "app/frontend/components/admin/creator/BillCreatorLlmSummary";

describe("BillCreatorLlmSummary — Expose summary history without LLM provisioning", () => {
    beforeEach(() => {
        routerPost.mockClear();
        routerReload.mockClear();
        usePageMock.mockReset();
    });

    afterEach(() => cleanup());

    describe("Persisted bills (billId > 0)", () => {
        it("renders BillSummaryRevisionHistory when provisioning is null", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 101,
                        external_id: "HB101",
                        summary: "Manual operator summary",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("btn-generate-summary-empty-state")).toBeInTheDocument();
        });

        it("renders BillSummaryRevisionHistory when provisioning is undefined", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 102,
                        external_id: "HB102",
                        summary: "Manual summary without prov",
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
        });

        it("renders BillSummaryRevisionHistory when provisioning is pending", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 103,
                        external_id: "HB103",
                        summary: "",
                        bill_llm_provisioning: {
                            generation_status: "pending",
                            llm_summary: null,
                            stale: false,
                            reclaimable: false,
                            paste_owns_summary_run: false,
                            draft_org_positions: [],
                            has_testimony: false,
                            testimony_attachments: null,
                            llm_provider: "claude",
                            citations_valid: null,
                            invalid_citations: null,
                            generation_error: null,
                            llm_full_breakdown: null,
                            supplemental_testimony: null,
                            stale_change_kind: null,
                            stale_change_at: null,
                            llm_generated_at: null,
                        },
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("status-badge").textContent).toBe("pending");
        });

        it("renders BillSummaryRevisionHistory when provisioning is failed", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 104,
                        external_id: "HB104",
                        summary: "Prior saved summary",
                        bill_llm_provisioning: {
                            generation_status: "failed",
                            generation_error: "Model timed out",
                            llm_summary: null,
                            stale: false,
                            reclaimable: false,
                            paste_owns_summary_run: false,
                            draft_org_positions: [],
                            has_testimony: false,
                            testimony_attachments: null,
                            llm_provider: "claude",
                            citations_valid: null,
                            invalid_citations: null,
                            llm_full_breakdown: null,
                            supplemental_testimony: null,
                            stale_change_kind: null,
                            stale_change_at: null,
                            llm_generated_at: null,
                        },
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("btn-retry-summary")).toBeInTheDocument();
        });

        it("renders BillSummaryRevisionHistory when provisioning is generating", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 105,
                        external_id: "HB105",
                        summary: "",
                        bill_llm_provisioning: {
                            generation_status: "generating",
                            llm_summary: null,
                            stale: false,
                            reclaimable: false,
                            paste_owns_summary_run: false,
                            draft_org_positions: [],
                            has_testimony: false,
                            testimony_attachments: null,
                            llm_provider: "claude",
                            citations_valid: null,
                            invalid_citations: null,
                            generation_error: null,
                            llm_full_breakdown: null,
                            supplemental_testimony: null,
                            stale_change_kind: null,
                            stale_change_at: null,
                            llm_generated_at: null,
                        },
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
        });

        it("renders BillSummaryRevisionHistory when provisioning is completed without duplicating control", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 106,
                        external_id: "HB106",
                        summary: "Published summary text",
                        bill_llm_provisioning: {
                            generation_status: "completed",
                            llm_summary: "Completed draft text",
                            stale: false,
                            reclaimable: false,
                            paste_owns_summary_run: false,
                            draft_org_positions: [],
                            has_testimony: false,
                            testimony_attachments: null,
                            llm_provider: "claude",
                            citations_valid: null,
                            invalid_citations: null,
                            generation_error: null,
                            llm_full_breakdown: "Full breakdown",
                            supplemental_testimony: null,
                            stale_change_kind: null,
                            stale_change_at: null,
                            llm_generated_at: new Date().toISOString(),
                        },
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            const historyNodes = screen.getAllByTestId("bill-summary-revision-history");
            expect(historyNodes).toHaveLength(1);
            expect(screen.getAllByTestId("toggle-revision-history")).toHaveLength(1);
        });

        it("renders BillSummaryRevisionHistory when provisioning is skipped", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 107,
                        external_id: "HB107",
                        summary: "Existing text",
                        bill_llm_provisioning: {
                            generation_status: "skipped",
                            llm_summary: "Prior summary",
                            stale: false,
                            reclaimable: false,
                            paste_owns_summary_run: false,
                            draft_org_positions: [],
                            has_testimony: false,
                            testimony_attachments: null,
                            llm_provider: "claude",
                            citations_valid: null,
                            invalid_citations: null,
                            generation_error: null,
                            llm_full_breakdown: null,
                            supplemental_testimony: null,
                            stale_change_kind: null,
                            stale_change_at: null,
                            llm_generated_at: null,
                        },
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.getByTestId("bill-summary-revision-history")).toBeInTheDocument();
            expect(screen.getByTestId("toggle-revision-history")).toBeInTheDocument();
        });

        it("invokes router.reload when opening history drawer on a bill without provisioning", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 108,
                        external_id: "HB108",
                        summary: "Manual summary",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            const toggle = screen.getByTestId("toggle-revision-history");
            fireEvent.click(toggle);

            expect(routerReload).toHaveBeenCalledTimes(1);
            expect(routerReload).toHaveBeenCalledWith({
                only: ["summary_revisions"],
                onFinish: expect.any(Function),
            });
        });
    });

    describe("Unpersisted bills (!billId or billId <= 0)", () => {
        it("omits BillSummaryRevisionHistory when bill.id is 0", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: 0,
                        external_id: "NEW",
                        summary: "",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.queryByTestId("bill-summary-revision-history")).toBeNull();
            expect(screen.queryByTestId("toggle-revision-history")).toBeNull();
        });

        it("omits BillSummaryRevisionHistory when bill.id is undefined", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        external_id: "NEW",
                        summary: "",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.queryByTestId("bill-summary-revision-history")).toBeNull();
            expect(screen.queryByTestId("toggle-revision-history")).toBeNull();
        });

        it("omits BillSummaryRevisionHistory when bill.id is null", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: null,
                        external_id: "NEW",
                        summary: "",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.queryByTestId("bill-summary-revision-history")).toBeNull();
            expect(screen.queryByTestId("toggle-revision-history")).toBeNull();
        });

        it("omits BillSummaryRevisionHistory when bill.id is negative", () => {
            usePageMock.mockReturnValue({
                props: {
                    bill: {
                        id: -1,
                        external_id: "NEW",
                        summary: "",
                        bill_llm_provisioning: null,
                        bill_pipeline_refresh: null,
                    },
                },
            });
            render(<BillCreatorLlmSummary />);

            expect(screen.queryByTestId("bill-summary-revision-history")).toBeNull();
            expect(screen.queryByTestId("toggle-revision-history")).toBeNull();
        });
    });
});
