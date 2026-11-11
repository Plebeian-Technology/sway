import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
    },
}));

const notify = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

const confirmMock = vi.fn<(opts: Record<string, unknown>) => Promise<boolean>>();
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({ useConfirm: () => confirmMock }));

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
        <select
            data-testid="select-claimed-affiliation-stance"
            value={value}
            onChange={(e) => onValueChange(e.target.value)}
        >
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

import BillCreatorClaimedAffiliationCard, {
    IClaimedAffiliationDraft,
} from "app/frontend/components/admin/creator/BillCreatorClaimedAffiliationCard";

afterEach(() => {
    cleanup();
    routerPost.mockClear();
    notify.mockClear();
    confirmMock.mockReset();
});

const draft = (overrides: Partial<IClaimedAffiliationDraft> = {}): IClaimedAffiliationDraft => ({
    position: 3,
    phrase: "president of the Baltimore Transit Equity Coalition",
    role: "president",
    sender: "jane@example.com",
    org_name: "Baltimore Transit Equity Coalition",
    ...overrides,
});

// W-22: Approve is off until a summary exists, so every approve-flow example
// has to put one there first.
const fillSummary = (text = "Backs the bill") => {
    fireEvent.click(screen.getByTestId("btn-edit-claimed-affiliation"));
    fireEvent.change(screen.getByTestId("textarea-claimed-affiliation-summary"), { target: { value: text } });
};

describe("BillCreatorClaimedAffiliationCard", () => {
    it("carries the CLAIMED, NOT VERIFIED stamp", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByTestId("claimed-affiliation-stamp")).toHaveTextContent("CLAIMED, NOT VERIFIED");
    });

    it("carries a name line marked as a guess, seeded from org_name, not the whole phrase", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByText("Maybe: Baltimore Transit Equity Coalition")).toBeInTheDocument();
    });

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why the affiliation card seeds from the organization name]]
    it("seeds the name box (and what Approve POSTs) from org_name, not phrase, when they differ", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft({
                    phrase: "Executive Director of the Baltimore Housing Coalition",
                    role: "Executive Director",
                    org_name: "the Baltimore Housing Coalition",
                })}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByText("Maybe: the Baltimore Housing Coalition")).toBeInTheDocument();
        expect(screen.queryByText(/Maybe: Executive Director/)).not.toBeInTheDocument();

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/1/approve_org_position",
            {
                org_name: "the Baltimore Housing Coalition",
                support: "support",
                summary: "Backs the bill",
                claimed_affiliation_position: 3,
            },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("carries the evidence block heading and the evidence rows themselves", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByText("Why this organization")).toBeInTheDocument();
        expect(screen.getByText("Phrase")).toBeInTheDocument();
        expect(screen.getByText("Role claimed")).toBeInTheDocument();
        expect(screen.getByText("Sender")).toBeInTheDocument();
    });

    it("carries the guard line verbatim", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(
            screen.getByText("The sender said this. Nothing has confirmed it. Approve only if you know it is true."),
        ).toBeInTheDocument();
    });

    it("renders no card at all when none of the three evidence values can be filled", () => {
        const { container } = render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft({ phrase: null, role: null, sender: null, org_name: null })}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(container.firstChild).toBeNull();
    });

    // It still sends no index and no draft token — it promotes no stored draft. What changed is
    // that it no longer relies on that ABSENCE to be understood: a server deciding by the missing
    // parameter read this card as an admin asserting a position from their own knowledge and
    // skipped every testimony rule, including the two this card greys its own Approve button on.
    it("posts org_name/support/summary and the letter it is acting on, with no index and no draft token", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/1/approve_org_position",
            {
                org_name: "Baltimore Transit Equity Coalition",
                support: "support",
                summary: "Backs the bill",
                claimed_affiliation_position: 3,
            },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("shows the refusal through the existing org_position channel on error", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        opts.onError?.({ org_position: "Summary is required" });

        expect(notify).toHaveBeenCalledWith({ level: "error", title: "Summary is required" });
    });

    it("offers a confirm dialog on the private-individual refusal, and resubmits with the override flag once confirmed", async () => {
        confirmMock.mockResolvedValue(true);
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await opts.onError?.({
            org_position: "This bill's testimony reads Jane Doe as a person writing for themselves.",
            private_individual_refusal: true,
        });

        expect(confirmMock).toHaveBeenCalledTimes(1);
        expect(routerPost).toHaveBeenCalledTimes(2);
        expect(routerPost).toHaveBeenNthCalledWith(
            2,
            "/bills/1/approve_org_position",
            expect.objectContaining({ override_private_individual: true }),
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("does not resubmit when the operator cancels the confirm dialog", async () => {
        confirmMock.mockResolvedValue(false);
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => Promise<void> };
        await opts.onError?.({
            org_position: "This bill's testimony reads Jane Doe as a person writing for themselves.",
            private_individual_refusal: true,
        });

        expect(routerPost).toHaveBeenCalledTimes(1);
        expect(notify).toHaveBeenCalledWith({
            level: "error",
            title: "This bill's testimony reads Jane Doe as a person writing for themselves.",
        });
    });

    it("disables approve, reject and edit together while submitting", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).toBeDisabled();
        expect(screen.getByTestId("btn-reject-claimed-affiliation")).toBeDisabled();
        expect(screen.getByTestId("btn-edit-claimed-affiliation")).toBeDisabled();
    });

    it("disables approve while a clean-testimony run is in flight, but leaves reject and edit usable", () => {
        render(<BillCreatorClaimedAffiliationCard billId={1} draft={draft()} runInFlight testimonyMissing={false} />);

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).toBeDisabled();
        expect(screen.getByTestId("btn-reject-claimed-affiliation")).not.toBeDisabled();
        expect(screen.getByTestId("btn-edit-claimed-affiliation")).not.toBeDisabled();
    });

    it("disables approve while testimony was left out and unacknowledged", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
                testimonyLeftOutUnacknowledged
            />,
        );

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).toBeDisabled();
    });

    it("hides the card locally on Reject, publishing nothing, keeping its evidence intact only until then", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-reject-claimed-affiliation"));

        expect(routerPost).not.toHaveBeenCalled();
        expect(screen.queryByTestId("claimed-affiliation-stamp")).not.toBeInTheDocument();
    });

    it("keeps the card on screen with its evidence intact after a refused approval", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void; onFinish?: () => void };
        opts.onError?.({ org_position: "Organization name is required" });
        opts.onFinish?.();

        expect(screen.getByTestId("claimed-affiliation-stamp")).toBeInTheDocument();
        expect(screen.getByText("Phrase")).toBeInTheDocument();
    });

    it("opens an editable form on Edit, letting the operator change the name, stance and summary before Approve", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        fireEvent.click(screen.getByTestId("btn-edit-claimed-affiliation"));
        fireEvent.change(screen.getByTestId("input-claimed-affiliation-name"), {
            target: { value: "Baltimore Transit Equity Coalition" },
        });
        fireEvent.change(screen.getByTestId("select-claimed-affiliation-stance"), {
            target: { value: "oppose" },
        });
        fireEvent.change(screen.getByTestId("textarea-claimed-affiliation-summary"), {
            target: { value: "Opposes the bill on cost grounds." },
        });
        fireEvent.click(screen.getByTestId("btn-claimed-affiliation-cancel"));
        fireEvent.click(screen.getByTestId("btn-approve-claimed-affiliation"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/1/approve_org_position",
            {
                org_name: "Baltimore Transit Equity Coalition",
                support: "oppose",
                summary: "Opposes the bill on cost grounds.",
                claimed_affiliation_position: 3,
            },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("renders no digit-followed-by-percent pattern anywhere on the card", () => {
        const { container } = render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(container.textContent).not.toMatch(/\d+%/);
    });

    it("identifies the card by the draft's stable position, not by its rendered list order", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft({ position: 7 })}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByTestId("claimed-affiliation-card-claimed-affiliation-7")).toBeInTheDocument();
    });

    // W-22/W-24: the card must name every reason the server would refuse on,
    // or the first click is spent discovering one.
    it("keeps approve off until a summary is written", () => {
        render(
            <BillCreatorClaimedAffiliationCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).toBeDisabled();

        fillSummary();

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).not.toBeDisabled();
    });

    it("keeps approve off when the bill's testimony is gone, even with a summary written", () => {
        render(<BillCreatorClaimedAffiliationCard billId={1} draft={draft()} runInFlight={false} testimonyMissing />);

        fillSummary();

        expect(screen.getByTestId("btn-approve-claimed-affiliation")).toBeDisabled();
    });
});
