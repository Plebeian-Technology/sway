import { render as rtlRender, screen } from "@testing-library/react";
import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import { usePage } from "@inertiajs/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@inertiajs/react", () => ({
    router: {
        post: vi.fn<(url: string, data?: unknown) => void>(),
        patch: vi.fn<(url: string, data?: unknown) => void>(),
    },
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    useForm: () => ({
        data: {},
        setData: vi.fn<(key: string | Record<string, unknown>, value?: unknown) => void>(),
        post: vi.fn<() => void>(),
        processing: false,
        errors: {},
        reset: vi.fn<() => void>(),
        transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
    }),
}));

vi.mock("app/frontend/sway_utils", () => ({ notify: vi.fn<(message: string, type?: string) => void>() }));

import BillCreatorTestimonyPositions from "app/frontend/components/admin/creator/BillCreatorTestimonyPositions";
import { IBillLlmProvisioning, IOrgPosition } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[private-individual-guard-override#Approve-anyway lives behind the app-wide confirm dialog]]
const render = (ui: React.ReactElement) => rtlRender(ui, { wrapper: ConfirmProvider });

const draft: IOrgPosition = {
    org_name: "Maryland Tenants Union",
    stance: "support",
    summary: "Testified in support.",
};

const provisioning = (overrides: Partial<IBillLlmProvisioning> = {}): IBillLlmProvisioning => ({
    generation_status: "completed",
    generation_error: null,
    llm_summary: "A real summary.",
    llm_full_breakdown: null,
    supplemental_testimony: null,
    draft_org_positions: [draft],
    stale: false,
    reclaimable: false,
    paste_owns_summary_run: false,
    stale_change_kind: null,
    stale_change_at: null,
    llm_generated_at: null,
    llm_provider: "claude",
    has_testimony: true,
    testimony_attachments: [],
    citations_valid: true,
    invalid_citations: [],
    ...overrides,
});

const servePage = (
    overrides: Partial<IBillLlmProvisioning> = {},
    activeRun: { status?: string | null; bill_id?: number | null } | null = null,
) =>
    (usePage as ReturnType<typeof vi.fn>).mockReturnValue({
        props: {
            bill: { id: 1, external_id: "HB123", summary: "", bill_llm_provisioning: provisioning(overrides) },
            active_legislation_pipeline_run: activeRun,
        },
    });

const renderPositions = (
    overrides: Partial<IBillLlmProvisioning> = {},
    activeRun: { status?: string | null; bill_id?: number | null } | null = null,
) => {
    servePage(overrides, activeRun);
    return render(<BillCreatorTestimonyPositions />);
};

beforeEach(() => servePage());

// @lat: [[bill-creator-positions-tab#Why Approve says on this tab why it is off]]
describe("the positions tab — a run that is about to replace these drafts", () => {
    it("switches off Approve on the drafts a queued run is about to replace", () => {
        renderPositions({ generation_status: "pending" });

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("switches off Approve while the replacing run is generating too", () => {
        renderPositions({ generation_status: "generating" });

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("leaves Reject and Edit alone", () => {
        renderPositions({ generation_status: "pending" });

        expect(screen.getByTestId("btn-reject-org-position")).not.toBeDisabled();
        expect(screen.getByTestId("btn-edit-org-position")).not.toBeDisabled();
    });

    it("points the greyed-out Approve at a notice that explains the greyed-out Approve", () => {
        renderPositions({ generation_status: "pending" });

        const notice = screen.getByTestId("positions-run-in-flight");
        const describedBy = screen.getByTestId("btn-approve-org-position").getAttribute("aria-describedby");
        expect(describedBy).toContain(notice.getAttribute("id"));
        expect(notice).toHaveTextContent(/approve is off while this row is queued or running/i);
        expect(notice).toHaveTextContent(/comes back when the run finishes/i);
    });

    it("explains it on the abandoned arm too, where the pointer is also set", () => {
        renderPositions({ generation_status: "pending", reclaimable: true });

        const notice = screen.getByTestId("positions-run-in-flight");
        const describedBy = screen.getByTestId("btn-approve-org-position").getAttribute("aria-describedby");
        expect(describedBy).toContain(notice.getAttribute("id"));
        expect(notice).toHaveTextContent(/approve is off while this row is queued or running/i);
    });

    it("leaves Approve shut on an abandoned row, because the server still refuses it", () => {
        renderPositions({ generation_status: "pending", reclaimable: true });

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("still offers Approve on a finished row", () => {
        renderPositions();

        expect(screen.getByTestId("btn-approve-org-position")).not.toBeDisabled();
        expect(screen.getByTestId("btn-approve-org-position")).not.toHaveAttribute("aria-describedby");
        expect(screen.queryByTestId("positions-run-in-flight")).toBeNull();
    });
});

// @lat: [[bill-creator-positions-tab#Why Approve says on this tab why it is off]]
describe("the positions tab — a clean-testimony run rewriting the artifact behind a finished row", () => {
    it("switches off Approve on a completed row while this bill's own clean-testimony run is going", () => {
        renderPositions({}, { status: "cleaning_testimony", bill_id: 1 });

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("switches off Approve on a completed row during a global all-bills clean-testimony run (bill_id null)", () => {
        renderPositions({}, { status: "cleaning_testimony", bill_id: null });

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("says why Approve is off, where the older summary-side notice said nothing at all", () => {
        renderPositions({}, { status: "cleaning_testimony", bill_id: 1 });

        const notice = screen.getByTestId("positions-run-in-flight");
        expect(notice).toHaveTextContent(/testimony behind these positions is being rewritten/i);
        expect(screen.getByTestId("btn-approve-org-position").getAttribute("aria-describedby")).toContain(
            notice.getAttribute("id"),
        );
    });

    it("leaves Approve alone when the running clean-testimony run belongs to a different bill", () => {
        renderPositions({}, { status: "cleaning_testimony", bill_id: 999 });

        expect(screen.getByTestId("btn-approve-org-position")).not.toBeDisabled();
    });

    it("leaves Approve alone when this bill's active run is at some other stage, not cleaning_testimony", () => {
        renderPositions({}, { status: "extracting_text", bill_id: 1 });

        expect(screen.getByTestId("btn-approve-org-position")).not.toBeDisabled();
    });
});
