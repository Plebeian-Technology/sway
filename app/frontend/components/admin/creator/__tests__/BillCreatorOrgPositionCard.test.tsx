import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerPatch = vi.fn<(...args: unknown[]) => void>();
const routerReload = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        patch: (...args: unknown[]) => routerPatch(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));

// On success the card shows no toast of its own — that comes from the server's flash
// message. A refusal has no flash, so its toast must come from onError.
const notify = vi.fn<(...args: unknown[]) => void>();

vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

const confirmMock = vi.fn<(opts: Record<string, unknown>) => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

// `tone` is forwarded as data-tone; it used to be dropped, which let the stance fallback
// pin on only ONE of its two lookups (badge tone stayed undefined and green). (C20-09)
vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({
        children,
        tone,
        ...props
    }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
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

vi.mock("app/frontend/components/ui/textarea", () => ({
    Textarea: (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...props} />,
}));

vi.mock("app/frontend/components/ui/input", () => ({
    Input: (props: React.InputHTMLAttributes<HTMLInputElement>) => <input {...props} />,
}));

vi.mock("app/frontend/components/ui/label", () => ({
    Label: ({ children, ...props }: React.LabelHTMLAttributes<HTMLLabelElement>) => (
        <label {...props}>{children}</label>
    ),
}));

// The select pieces, cut down to a plain <select>, so a test can change it with
// fireEvent.change instead of imitating how Radix renders its menu elsewhere on
// the page.
vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({
        children,
        value,
        onValueChange,
    }: {
        children: React.ReactNode;
        value: string;
        onValueChange: (v: string) => void;
    }) => (
        <select data-testid="select-edit-stance" value={value} onChange={(e) => onValueChange(e.target.value)}>
            {children}
        </select>
    ),
    SelectTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

import BillCreatorOrgPositionCard from "app/frontend/components/admin/creator/BillCreatorOrgPositionCard";
import { SUPPORT_TO_TONE, type TStance } from "app/frontend/components/admin/creator/org-position-card/constants";
import { IOrgPosition } from "app/frontend/components/admin/creator/llm-summary/types";
import { TESTIMONY_COVERAGE_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/testimonyCoverageNoticeId";

// Written out here rather than imported: aria-describedby only matches by text, so two
// drifted constants would still point at nothing and pass.
//
// LlmSummaryOrgPositions.test.tsx checks the notice's side of the same text.
const NO_TESTIMONY_NOTICE_ID = "llm-no-testimony-notice";

afterEach(() => {
    cleanup();
    routerPost.mockReset();
    routerPatch.mockReset();
    routerReload.mockReset();
    notify.mockReset();
    confirmMock.mockReset();
});

const baseOrgPosition: IOrgPosition = {
    org_name: "ACME Civic Coalition",
    stance: "support",
    summary: "Original summary.",
    // An identifier the server works out for this entry and sends with every
    // draft. Both Approve and Reject have to send it back.
    draft_token: "test-draft-token-01",
};

// @lat: [[bill-creator-org-position-card-test-notes#Row element ids must not be built from the organization name alone]]
describe("BillCreatorOrgPositionCard — the neutral stance is called one thing", () => {
    it("labels a neutral stance Neutral, matching the edit menu", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={{ ...baseOrgPosition, stance: "neutral" }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        const card = screen.getByTestId("org-position-card-acme-civic-coalition-0");
        expect(card).toHaveTextContent("Neutral");
        expect(card).not.toHaveTextContent("Abstain");
    });

    // A row written before the controller enforced stance validity can hold any value, so both lookups
    // return undefined — the badge draws empty until Approve refuses.
    it("shows the stored word for a stance outside the three it knows", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={{ ...baseOrgPosition, stance: "sympathetic" as TStance }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("org-position-card-acme-civic-coalition-0")).toHaveTextContent("sympathetic");
        // The OTHER lookup: SUPPORT_TO_TONE[stanceBadgeKey] falls back to ABSTAIN's tone,
        // unasserted — reverting stanceBadgeKey left an undefined tone and this file
        // green. (C20-09)
        expect(screen.getByText("sympathetic").getAttribute("data-tone")).toBe(SUPPORT_TO_TONE.ABSTAIN);
    });

    it("names a blank stance rather than drawing an empty badge", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={{ ...baseOrgPosition, stance: "" as TStance }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("org-position-card-acme-civic-coalition-0")).toHaveTextContent("No position");
        expect(screen.getByText("No position").getAttribute("data-tone")).toBe(SUPPORT_TO_TONE.ABSTAIN);
    });
});

describe("BillCreatorOrgPositionCard — DOM identity (C2-WR-02)", () => {
    it("disambiguates two positions from the same organization by index", () => {
        const { container } = render(
            <>
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={baseOrgPosition}
                    testimonyMissing={false}
                    runInFlight={false}
                />
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={1}
                    orgPosition={{ ...baseOrgPosition, stance: "oppose" }}
                    testimonyMissing={false}
                    runInFlight={false}
                />
            </>,
        );

        const testids = Array.from(container.querySelectorAll("[data-testid^='org-position-card-']")).map((el) =>
            el.getAttribute("data-testid"),
        );
        expect(testids).toEqual([
            "org-position-card-acme-civic-coalition-0",
            "org-position-card-acme-civic-coalition-1",
        ]);
        expect(new Set(testids).size).toBe(2);
    });

    it("keeps the testid fixed when the operator renames the draft", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={3}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByTestId("org-position-card-acme-civic-coalition-3")).toBeInTheDocument();

        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("input-edit-org-name"), {
            target: { value: "Maryland Tenants Union" },
        });
        fireEvent.click(screen.getByText("Apply edits"));

        expect(screen.getByText("Maryland Tenants Union")).toBeInTheDocument();
        expect(screen.getByTestId("org-position-card-acme-civic-coalition-3")).toBeInTheDocument();
    });
});

// Approve/Reject both already redirect to a fresh page, so a second reload from onSuccess
// was a duplicate request against a single-Pi server, and it outlived the submitting flag too.
describe("BillCreatorOrgPositionCard — no redundant reload (C-WR-07)", () => {
    it("Approve issues exactly one request and no follow-up reload", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        expect(routerPost).toHaveBeenCalledTimes(1);
        const opts = routerPost.mock.calls[0][2] as Record<string, unknown>;
        expect(opts.onSuccess).toBeUndefined();
        expect(routerReload).not.toHaveBeenCalled();
    });

    it("Reject issues exactly one request and no follow-up reload", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const opts = routerPatch.mock.calls[0][2] as Record<string, unknown>;
        expect(opts.onSuccess).toBeUndefined();
        expect(routerReload).not.toHaveBeenCalled();
    });
});

// A refused Approve/Reject redirects with `inertia: {errors: {org_position:}}` and no
// flash; nothing shows it. Without onError it looks like a slow request, so the operator
// retries.
describe("BillCreatorOrgPositionCard — server refusals are visible (C1-CR-01)", () => {
    it("Approve toasts the server's refusal copy", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        expect(typeof opts.onError).toBe("function");

        opts.onError?.({
            org_position: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });
    });

    it("Approve falls back to its own copy when the server sends no org_position message", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        opts.onError?.({});

        expect(notify).toHaveBeenCalledWith({ level: "error", title: expect.stringMatching(/approve/i) });
    });

    it("Reject toasts the server's refusal copy", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));

        const opts = routerPatch.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        expect(typeof opts.onError).toBe("function");

        opts.onError?.({
            org_position: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });

        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });
    });
});

// @lat: [[private-individual-guard-override]]
describe("BillCreatorOrgPositionCard — private-individual override", () => {
    it("offers a confirm dialog on the private-individual refusal, and resubmits with the override flag once confirmed", async () => {
        confirmMock.mockResolvedValue(true);
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await opts.onError?.({
            org_position: "This bill's testimony reads ACME Civic Coalition as a person writing for themselves.",
            private_individual_refusal: true,
        });

        expect(confirmMock).toHaveBeenCalledTimes(1);
        expect(routerPost).toHaveBeenCalledTimes(2);
        expect(routerPost).toHaveBeenNthCalledWith(
            2,
            "/bills/42/approve_org_position",
            expect.objectContaining({ override_private_individual: true }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("does not resubmit, and still shows the refusal toast, when the operator cancels the confirm dialog", async () => {
        confirmMock.mockResolvedValue(false);
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await opts.onError?.({
            org_position: "This bill's testimony reads ACME Civic Coalition as a person writing for themselves.",
            private_individual_refusal: true,
        });

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "This bill's testimony reads ACME Civic Coalition as a person writing for themselves.",
        });
    });

    // @lat: [[private-individual-guard-override#A retry started from onError outlives the request that started it]]
    it("keeps every action disabled while the override retry is still on the wire", async () => {
        let answerDialog: (confirmed: boolean) => void = () => {};
        confirmMock.mockImplementation(() => new Promise<boolean>((resolve) => (answerDialog = resolve)));
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const refused = routerPost.mock.calls[0][2] as {
            onError?: (errors: unknown) => Promise<void>;
            onFinish?: () => void;
        };
        const handled = refused.onError?.({
            org_position: "This bill's testimony reads ACME Civic Coalition as a person writing for themselves.",
            private_individual_refusal: true,
        });
        await act(async () => {
            answerDialog(true);
            await handled;
        });
        act(() => refused.onFinish?.());

        expect(routerPost).toHaveBeenCalledTimes(2);
        expect(screen.getByTestId("btn-approve-org-position")).toHaveProperty("disabled", true);
        expect(screen.getByTestId("btn-reject-org-position")).toHaveProperty("disabled", true);
        expect(screen.getByTestId("btn-edit-org-position")).toHaveProperty("disabled", true);

        const retry = routerPost.mock.calls[1][2] as { onFinish?: () => void };
        act(() => retry.onFinish?.());

        expect(screen.getByTestId("btn-approve-org-position")).toHaveProperty("disabled", false);
    });

    // @lat: [[private-individual-guard-override#A refusal that survives the override is shown, not re-asked]]
    it("shows the message instead of re-asking when the override retry is refused the same way", async () => {
        confirmMock.mockResolvedValue(true);
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const refusal = {
            org_position: "This bill's testimony reads ACME Civic Coalition as a person writing for themselves.",
            private_individual_refusal: true,
        };
        const first = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await first.onError?.(refusal);

        const retry = routerPost.mock.calls[1][2] as { onError?: (errors: unknown) => Promise<void> };
        await retry.onError?.(refusal);

        expect(confirmMock).toHaveBeenCalledTimes(1);
        expect(routerPost).toHaveBeenCalledTimes(2);
        expect(notify).toHaveBeenCalledWith({ level: "error", title: refusal.org_position });
    });

    it("does not offer a confirm dialog for an ordinary refusal", async () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await opts.onError?.({
            org_position: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });

        expect(confirmMock).not.toHaveBeenCalled();
        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "This draft list has changed. The list on screen is up to date — check it and try again.",
        });
    });
});

describe("BillCreatorOrgPositionCard — Edit toggle", () => {
    it("seeds the badge directly from orgPosition.stance (real wire shape, no undefined badge)", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByText("Support")).toBeInTheDocument();
    });

    it("renders the correct badge for an 'oppose' stance position", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={{ ...baseOrgPosition, stance: "oppose" }}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.getByText("Oppose")).toBeInTheDocument();
    });

    it("Edit reveals inline form; Cancel edit returns to card view without changes", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        expect(screen.queryByTestId("select-edit-stance")).not.toBeInTheDocument();
        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        expect(screen.getByTestId("select-edit-stance")).toBeInTheDocument();
        expect(screen.getByText("Apply edits")).toBeInTheDocument();
        expect(screen.getByText("Cancel edit")).toBeInTheDocument();

        fireEvent.click(screen.getByText("Cancel edit"));
        expect(screen.queryByTestId("select-edit-stance")).not.toBeInTheDocument();
    });

    it("Apply edits retains the amended stance + summary so subsequent Approve POSTs them", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("select-edit-stance"), { target: { value: "oppose" } });
        fireEvent.change(screen.getByTestId("textarea-edit-summary"), {
            target: { value: "Amended position summary." },
        });
        fireEvent.click(screen.getByText("Apply edits"));

        fireEvent.click(screen.getByTestId("btn-approve-org-position"));
        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/approve_org_position",
            expect.objectContaining({
                org_name: "ACME Civic Coalition",
                support: "oppose",
                summary: "Amended position summary.",
            }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("Apply edits to the org name flows through to the Approve POST (local-until-Approve)", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("input-edit-org-name"), {
            target: { value: "Maryland Tenants Union" },
        });
        fireEvent.click(screen.getByText("Apply edits"));

        expect(screen.getByText("Maryland Tenants Union")).toBeInTheDocument();
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));
        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/approve_org_position",
            expect.objectContaining({ org_name: "Maryland Tenants Union" }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    // An operator can rename a draft before approving, so the server can't use the
    // submitted name to confirm identity — send the untouched original name as proof.
    it("Approve carries the pristine draft org name as the identity token, even after a rename", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={2}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("input-edit-org-name"), {
            target: { value: "Maryland Tenants Union" },
        });
        fireEvent.click(screen.getByText("Apply edits"));
        fireEvent.click(screen.getByTestId("btn-approve-org-position"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/42/approve_org_position",
            expect.objectContaining({
                org_name: "Maryland Tenants Union",
                index: 2,
                draft_org_name: "ACME Civic Coalition",
                draft_token: "test-draft-token-01",
            }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("Reject PATCHes /bill_draft_org_positions/:bill_id-:index with rejected=true", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={2}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));
        expect(routerPatch).toHaveBeenCalledWith(
            "/bill_draft_org_positions/42-2",
            { rejected: true, draft_org_name: "ACME Civic Coalition", draft_token: "test-draft-token-01" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    // Reject needed the same protection as Approve: only a per-card flag guarded against
    // a stale click, so the original name proves which draft this is.
    it("Reject carries the pristine draft org name as the identity token, even after a rename", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={1}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-edit-org-position"));
        fireEvent.change(screen.getByTestId("input-edit-org-name"), {
            target: { value: "Maryland Tenants Union" },
        });
        fireEvent.click(screen.getByText("Apply edits"));
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));

        expect(routerPatch).toHaveBeenCalledWith(
            "/bill_draft_org_positions/42-1",
            { rejected: true, draft_org_name: "ACME Civic Coalition", draft_token: "test-draft-token-01" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });
});

// @lat: [[bill-creator-org-position-card-test-notes#An evidence-retracted draft still allows Reject and Edit]]
describe("BillCreatorOrgPositionCard — evidence-retracted draft (B4-CR-02)", () => {
    const retracted = { ...baseOrgPosition, evidence_retracted_at: "2026-07-01T00:00:00Z" };

    it("disables Approve and says why", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={retracted}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
        const notice = screen.getByTestId("org-position-evidence-retracted");
        expect(notice.textContent).toMatch(/testimony/i);
        expect(notice.textContent).toMatch(/regenerat/i);
    });

    // Four different things can stamp this mark, so the message must not name one — it
    // used to blame "the latest hearing fetch", wrong for the common case of an operator
    // clearing their own paste.
    it("does not blame a hearing fetch it cannot know ran", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={retracted}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("org-position-evidence-retracted").textContent).not.toMatch(/hearing fetch/i);
    });

    it("leaves Reject and Edit available", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={retracted}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("btn-reject-org-position")).not.toBeDisabled();
        expect(screen.getByTestId("btn-edit-org-position")).not.toBeDisabled();
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));
        expect(routerPatch).toHaveBeenCalledTimes(1);
    });

    it("renders no notice and an enabled Approve for an unmarked draft", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={false}
                runInFlight={false}
            />,
        );

        expect(screen.queryByTestId("org-position-evidence-retracted")).toBeNull();
        expect(screen.getByTestId("btn-approve-org-position")).not.toBeDisabled();
    });
});

// @lat: [[bill-creator-org-position-card-test-notes#Bill-wide no-testimony is a second, separate refusal reason]]
describe("BillCreatorOrgPositionCard — bill has no testimony (A2-CR-01 / C2-CR-01)", () => {
    it("disables Approve on an unmarked draft", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    it("leaves Reject and Edit available", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={baseOrgPosition}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("btn-reject-org-position")).not.toBeDisabled();
        expect(screen.getByTestId("btn-edit-org-position")).not.toBeDisabled();
        fireEvent.click(screen.getByTestId("btn-reject-org-position"));
        expect(routerPatch).toHaveBeenCalledTimes(1);
    });

    // @lat: [[bill-creator-org-position-card-test-notes#A disabled Approve must carry its reason into the accessibility tree]]
    describe("a disabled Approve carries its reason into the accessibility tree (C1-i6-IN-04)", () => {
        const describedBy = () =>
            (screen.getByTestId("btn-approve-org-position").getAttribute("aria-describedby") ?? "").split(/\s+/);

        it("points at the per-draft retraction notice, by an id that resolves", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={{ ...baseOrgPosition, evidence_retracted_at: "2026-07-01T00:00:00Z" }}
                    testimonyMissing={false}
                    runInFlight={false}
                />,
            );

            const notice = screen.getByTestId("org-position-evidence-retracted");
            expect(notice.id).toBeTruthy();
            expect(describedBy()).toContain(notice.id);
        });

        it("points at the bill-level no-testimony notice", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={baseOrgPosition}
                    testimonyMissing={true}
                    runInFlight={false}
                />,
            );

            expect(describedBy()).toContain(NO_TESTIMONY_NOTICE_ID);
        });

        it("points at both when both reasons hold", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={{ ...baseOrgPosition, evidence_retracted_at: "2026-07-01T00:00:00Z" }}
                    testimonyMissing={true}
                    runInFlight={false}
                />,
            );

            expect(describedBy()).toContain(screen.getByTestId("org-position-evidence-retracted").id);
            expect(describedBy()).toContain(NO_TESTIMONY_NOTICE_ID);
        });

        // A working button must not describe a state it is not in. An id that
        // points at nothing announces nothing and looks like a bug.
        it("says nothing when Approve is available", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={baseOrgPosition}
                    testimonyMissing={false}
                    runInFlight={false}
                />,
            );

            expect(screen.getByTestId("btn-approve-org-position")).not.toHaveAttribute("aria-describedby");
        });

        // Two cards for the same organization must not share the id of their
        // notice, or both Approve buttons would describe the first card's.
        it("gives each card's retraction notice its own id", () => {
            const retracted = { ...baseOrgPosition, evidence_retracted_at: "2026-07-01T00:00:00Z" };
            render(
                <>
                    <BillCreatorOrgPositionCard
                        billId={42}
                        index={0}
                        orgPosition={retracted}
                        testimonyMissing={false}
                        runInFlight={false}
                    />
                    <BillCreatorOrgPositionCard
                        billId={42}
                        index={1}
                        orgPosition={retracted}
                        testimonyMissing={false}
                        runInFlight={false}
                    />
                </>,
            );

            const ids = screen.getAllByTestId("org-position-evidence-retracted").map((n) => n.id);
            expect(new Set(ids).size).toBe(2);
        });
    });

    // The two conditions have nothing to do with each other, so the per-draft
    // notice still shows when both apply: the mark says something the bill-wide
    // fact does not.
    it("still renders the per-draft retraction notice when both conditions hold", () => {
        render(
            <BillCreatorOrgPositionCard
                billId={42}
                index={0}
                orgPosition={{ ...baseOrgPosition, evidence_retracted_at: "2026-07-01T00:00:00Z" }}
                testimonyMissing={true}
                runInFlight={false}
            />,
        );

        expect(screen.getByTestId("org-position-evidence-retracted")).toBeInTheDocument();
        expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
    });

    describe("news-sourced draft positions", () => {
        const newsOrgPosition: IOrgPosition = {
            ...baseOrgPosition,
            bill_news_article_id: 101,
            text_version_id: 202,
            evidence_excerpt: "We strongly support this legislation to safeguard fair housing for all tenants",
            speaker_name: "Jane Doe",
            speaker_role: "Executive Director",
            source_url: "https://example.com/article",
            outlet_name: "The Baltimore Banner",
            article_title: "Tenants Fight for Fair Housing",
            excerpt_page: 1,
            excerpt_paragraph: 3,
            excerpt_offset: 120,
        };

        it("enables Approve on a news-sourced draft position even when testimonyMissing is true", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={newsOrgPosition}
                    testimonyMissing={true}
                    runInFlight={false}
                />,
            );

            const approveBtn = screen.getByTestId("btn-approve-org-position");
            expect(approveBtn).not.toBeDisabled();
            const describedBy = approveBtn.getAttribute("aria-describedby") || "";
            expect(describedBy).not.toContain(NO_TESTIMONY_NOTICE_ID);
        });

        it("does not disable Approve when testimonyLeftOutUnacknowledged is true on news drafts", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={newsOrgPosition}
                    testimonyMissing={false}
                    testimonyLeftOutUnacknowledged={true}
                    runInFlight={false}
                />,
            );

            const approveBtn = screen.getByTestId("btn-approve-org-position");
            expect(approveBtn).not.toBeDisabled();
            const describedBy = approveBtn.getAttribute("aria-describedby") || "";
            expect(describedBy).not.toContain(TESTIMONY_COVERAGE_NOTICE_ID);
        });

        it("renders blockquote citation with data-testid='draft-org-position-news-excerpt-{index}', verbatim excerpt, attribution, and source link", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={2}
                    orgPosition={newsOrgPosition}
                    testimonyMissing={false}
                    runInFlight={false}
                />,
            );

            const quote = screen.getByTestId("draft-org-position-news-excerpt-2");
            expect(quote).toBeInTheDocument();
            expect(quote).toHaveTextContent(
                "“We strongly support this legislation to safeguard fair housing for all tenants”",
            );
            expect(quote).toHaveTextContent("— Jane Doe, Executive Director");
            const link = screen.getByRole("link", { name: "The Baltimore Banner" });
            expect(link).toHaveAttribute("href", "https://example.com/article");
            expect(link).toHaveAttribute("target", "_blank");
            expect(quote).toHaveTextContent("p. 1, para. 3, char 120");
        });

        it("renders inert text without an anchor when news source_url has an unsafe or file:/// scheme", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={3}
                    orgPosition={{
                        ...newsOrgPosition,
                        source_url: "file:///etc/passwd",
                        outlet_name: "Local Leak Outlet",
                    }}
                    testimonyMissing={false}
                    runInFlight={false}
                />,
            );

            const quote = screen.getByTestId("draft-org-position-news-excerpt-3");
            expect(quote).toBeInTheDocument();
            expect(screen.queryByRole("link", { name: "Local Leak Outlet" })).toBeNull();
            expect(quote).toHaveTextContent("Local Leak Outlet");
        });

        it("disables Approve on a news-sourced draft when evidence_retracted_at is present", () => {
            render(
                <BillCreatorOrgPositionCard
                    billId={42}
                    index={0}
                    orgPosition={{ ...newsOrgPosition, evidence_retracted_at: "2026-10-26T00:00:00Z" }}
                    testimonyMissing={false}
                    runInFlight={false}
                />,
            );

            expect(screen.getByTestId("btn-approve-org-position")).toBeDisabled();
            expect(screen.getByTestId("org-position-evidence-retracted")).toBeInTheDocument();
        });
    });
});
