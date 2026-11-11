import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerReload = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        reload: (...args: unknown[]) => routerReload(...args),
    },
}));

const notify = vi.fn<(...args: unknown[]) => void>();
vi.mock("app/frontend/sway_utils", () => ({
    notify: (...args: unknown[]) => notify(...args),
}));

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
        <select data-testid="select-campaign-stance" value={value} onChange={(e) => onValueChange(e.target.value)}>
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

import BillCreatorCampaignPositionCard from "app/frontend/components/admin/creator/BillCreatorCampaignPositionCard";
import {
    ITestimonyCampaignDraft,
    ITestimonyCampaignLetter,
} from "app/frontend/components/admin/creator/llm-summary/types";

afterEach(() => {
    cleanup();
    routerPost.mockClear();
    routerReload.mockClear();
    notify.mockClear();
});

const draft = (overrides: Partial<ITestimonyCampaignDraft> = {}): ITestimonyCampaignDraft => ({
    content_hash: "abc123",
    sender_count: 324,
    letter_count: 324,
    added_words_characters: 310,
    senders_added_words_left_out: 0,
    domain: "everyactioncustom.com",
    ...overrides,
});

// W-22: Approve is off until a summary exists, so every approve-flow example
// has to put one there first.
const fillSummary = (text = "Backs the bill") => {
    fireEvent.click(screen.getByTestId("btn-edit-campaign-position"));
    fireEvent.change(screen.getByTestId("textarea-campaign-summary"), { target: { value: text } });
};

describe("BillCreatorCampaignPositionCard", () => {
    it("renders the unnamed name line as the sentence naming how many people sent the letter", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(screen.getByText("324 people sent this letter")).toBeInTheDocument();
    });

    it("gives the sender count, the letter count and the sending service on the evidence sub-line", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(screen.getByText("324 senders · 324 letters · sent through everyactioncustom.com")).toBeInTheDocument();
    });

    it("omits the sending-service clause when the group carries no dominant domain", () => {
        render(
            <BillCreatorCampaignPositionCard
                billId={1}
                draft={draft({ domain: null })}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );

        expect(screen.getByText("324 senders · 324 letters")).toBeInTheDocument();
    });

    it("shows the letters handed to the card and asks for none, the draft carrying no text of its own", () => {
        const fetched: ITestimonyCampaignLetter = {
            position: 7,
            text: "The fetched letter body.",
            sender_address: "jane@example.com",
            sender_domain: "example.com",
            repeat: false,
        };

        render(
            <BillCreatorCampaignPositionCard
                billId={1}
                draft={draft()}
                letters={[fetched]}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-campaign-letters-disclosure"));

        expect(screen.getByText("The fetched letter body.")).toBeInTheDocument();
        expect(routerReload).not.toHaveBeenCalled();
    });

    it("asks for the letters prop when the card was handed none", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        fireEvent.click(screen.getByTestId("btn-campaign-letters-disclosure"));

        expect(routerReload).toHaveBeenCalledTimes(1);
        expect(screen.getByTestId("campaign-letters-loading")).toBeInTheDocument();
    });

    it("carries the guard line saying approving records a campaign position and never creates an organization", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(
            screen.getByText("Approving records a campaign position. It never creates an organization."),
        ).toBeInTheDocument();
    });

    it("carries the CAMPAIGN stamp", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(screen.getByTestId("campaign-stamp")).toHaveTextContent("CAMPAIGN");
    });

    it("posts name/support/summary/content_hash on Approve", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-campaign-position"));

        expect(routerPost).toHaveBeenCalledWith(
            "/bills/1/campaigns",
            { name: "", support: "support", summary: "Backs the bill", content_hash: "abc123" },
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("shows the refusal through the campaign_position channel on error", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-campaign-position"));
        const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
        opts.onError?.({ campaign_position: "A summary is required" });

        expect(notify).toHaveBeenCalledWith({ level: "error", title: "A summary is required" });
    });

    it("disables approve, reject and edit together while submitting", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        fillSummary();
        fireEvent.click(screen.getByTestId("btn-approve-campaign-position"));

        expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();
        expect(screen.getByTestId("btn-reject-campaign-position")).toBeDisabled();
        expect(screen.getByTestId("btn-edit-campaign-position")).toBeDisabled();
    });

    it("disables approve while a clean-testimony run is in flight, but leaves reject and edit usable", () => {
        render(<BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight testimonyMissing={false} />);

        expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();
        expect(screen.getByTestId("btn-reject-campaign-position")).not.toBeDisabled();
        expect(screen.getByTestId("btn-edit-campaign-position")).not.toBeDisabled();
    });

    it("disables approve while testimony was left out and unacknowledged", () => {
        render(
            <BillCreatorCampaignPositionCard
                billId={1}
                draft={draft()}
                runInFlight={false}
                testimonyMissing={false}
                testimonyLeftOutUnacknowledged
            />,
        );

        expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();
    });

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
    describe("rejecting a draft", () => {
        const publishPath = "/bills/1/campaigns";
        const postedPaths = () => routerPost.mock.calls.map((call) => call[0]);

        it("posts the rejection and stops offering the card for approval", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-reject-campaign-position"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/reject_draft",
                { content_hash: "abc123" },
                expect.objectContaining({ preserveScroll: true }),
            );
            expect(postedPaths()).not.toContain(publishPath);
            expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();
        });

        it("renders the rejected shell from the server prop, with no approve button at all", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft({ rejected: true })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-rejected-stamp")).toHaveTextContent("REJECTED");
            expect(screen.queryByTestId("btn-approve-campaign-position")).not.toBeInTheDocument();
            expect(screen.getByTestId("btn-restore-campaign-position")).toBeInTheDocument();
            expect(routerPost).not.toHaveBeenCalled();
        });

        it("posts the restore decision on Restore, still publishing nothing", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft({ rejected: true })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-restore-campaign-position"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/restore_draft",
                { content_hash: "abc123" },
                expect.objectContaining({ preserveScroll: true }),
            );
            expect(postedPaths()).not.toContain(publishPath);
        });

        it("shows the refusal through the campaign_position channel when the rejection is refused", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-reject-campaign-position"));
            const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
            opts.onError?.({ campaign_position: "Draft not found" });

            expect(notify).toHaveBeenCalledWith({ level: "error", title: "Draft not found" });
        });
    });

    describe("marking as individual letters", () => {
        const publishPath = "/bills/1/campaigns";
        const postedPaths = () => routerPost.mock.calls.map((call) => call[0]);

        it("posts the mark individual decision and disables action buttons while submitting", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-mark-individual-campaign-position"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/mark_individual_draft",
                { content_hash: "abc123" },
                expect.objectContaining({ preserveScroll: true }),
            );
            expect(postedPaths()).not.toContain(publishPath);
            expect(screen.getByTestId("btn-mark-individual-campaign-position")).toBeDisabled();
        });

        it("renders the collapsed individual letters row from server prop, with no approve button at all", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft({ marked_individual: true })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-individual-stamp")).toHaveTextContent("INDIVIDUAL LETTERS");
            expect(screen.getByText(/324 senders · 324 letters/)).toBeInTheDocument();
            expect(screen.queryByTestId("btn-approve-campaign-position")).not.toBeInTheDocument();
            expect(screen.getByTestId("btn-restore-campaign-position")).toBeInTheDocument();
            expect(routerPost).not.toHaveBeenCalled();
        });

        it("posts the restore decision on Restore from individual letters state", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft({ marked_individual: true })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-restore-campaign-position"));

            expect(routerPost).toHaveBeenCalledWith(
                "/bills/1/campaigns/restore_draft",
                { content_hash: "abc123" },
                expect.objectContaining({ preserveScroll: true }),
            );
            expect(postedPaths()).not.toContain(publishPath);
        });

        it("shows the refusal through the campaign_position channel when marking individual is refused", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-mark-individual-campaign-position"));
            const opts = routerPost.mock.calls[0][2] as { onError?: (errors: unknown) => void };
            opts.onError?.({ campaign_position: "Draft not found" });

            expect(notify).toHaveBeenCalledWith({ level: "error", title: "Draft not found" });
        });

        it("does not render Mark as Individual Letters button when approved is true", () => {
            const approvedCampaign = {
                id: 10,
                name: "Approved campaign",
                support: "FOR",
                summary: "Summary",
                sender_count: 5,
                letter_count: 5,
                source_campaign_draft_hash: "abc123",
                organization_link_decision: null,
                organization_id: null,
                organization_name: null,
            };

            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approvedCampaign}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.queryByTestId("btn-mark-individual-campaign-position")).not.toBeInTheDocument();
        });
    });

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#An unnamed campaign is a complete record]]
    it("opens the editor on Edit and fills the name field from what the operator types", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        fireEvent.click(screen.getByTestId("btn-edit-campaign-position"));
        fireEvent.change(screen.getByTestId("input-campaign-name"), {
            target: { value: "Complete Streets Letter" },
        });

        expect(screen.getByTestId("input-campaign-name")).toHaveValue("Complete Streets Letter");
    });

    it("renders no digit-followed-by-percent pattern anywhere on the card", () => {
        const { container } = render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(container.textContent).not.toMatch(/\d+%/);
    });

    it("clamps a very long campaign name to one line with a disclosure that stays selectable", () => {
        const longName = "C".repeat(200);
        render(
            <BillCreatorCampaignPositionCard
                billId={1}
                draft={draft({ sender_count: 5, letter_count: 5 })}
                runInFlight={false}
                testimonyMissing={false}
            />,
        );
        fireEvent.click(screen.getByTestId("btn-edit-campaign-position"));
        fireEvent.change(screen.getByTestId("input-campaign-name"), { target: { value: longName } });

        expect(screen.getByTestId("btn-campaign-name-disclosure")).toBeInTheDocument();
        expect(screen.getByText(longName).className).not.toMatch(/select-none/);
    });

    // W-22/W-24: the card must name every reason the server would refuse on,
    // or the first click is spent discovering one.
    it("keeps approve off until a summary is written", () => {
        render(
            <BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing={false} />,
        );

        expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();

        fillSummary();

        expect(screen.getByTestId("btn-approve-campaign-position")).not.toBeDisabled();
    });

    it("keeps approve off when the bill's testimony is gone, even with a summary written", () => {
        render(<BillCreatorCampaignPositionCard billId={1} draft={draft()} runInFlight={false} testimonyMissing />);

        fillSummary();

        expect(screen.getByTestId("btn-approve-campaign-position")).toBeDisabled();
    });

    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
    describe("a draft that already carries a decision", () => {
        const approved = (overrides = {}) => ({
            id: 7,
            name: "Complete Streets Letter",
            support: "AGAINST",
            summary: "Opposes the bill as introduced.",
            sender_count: 324,
            letter_count: 324,
            source_campaign_draft_hash: "abc123",
            organization_link_decision: null,
            organization_id: null,
            organization_name: null,
            ...overrides,
        });

        it("stamps the card APPROVED", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-approved-stamp")).toBeInTheDocument();
        });

        it("shows no APPROVED stamp when no decision has been recorded for this draft", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.queryByTestId("campaign-approved-stamp")).not.toBeInTheDocument();
        });

        it("opens on the approved name, stance and summary rather than on empty fields", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-name-line")).toHaveTextContent("Complete Streets Letter");
            expect(screen.getByText("Opposes the bill as introduced.")).toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-edit-campaign-position"));
            expect(screen.getByTestId("select-campaign-stance")).toHaveValue("oppose");
        });

        // The summary is already there, so Approve is live on first render — the operator is not
        // made to retype a decision the server already holds.
        it("offers Update rather than Approve, and does not require the summary to be retyped", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            const button = screen.getByTestId("btn-approve-campaign-position");
            expect(button).toHaveTextContent("Update this campaign");
            expect(button).not.toBeDisabled();
        });

        // An unrecognised support value must not leave the Select with no value at all.
        it("falls back to the default stance when the stored support is not one of the three", () => {
            render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved({ support: "SIDEWAYS" })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            fireEvent.click(screen.getByTestId("btn-edit-campaign-position"));
            expect(screen.getByTestId("select-campaign-stance")).toHaveValue("support");
        });

        it("syncs name, stance, and summary when the server approved prop changes while not editing", () => {
            const { rerender } = render(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved()}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-name-line")).toHaveTextContent("Complete Streets Letter");
            expect(screen.getByText("Opposes the bill as introduced.")).toBeInTheDocument();

            rerender(
                <BillCreatorCampaignPositionCard
                    billId={1}
                    draft={draft()}
                    approved={approved({
                        name: "Updated Streets Letter",
                        support: "FOR",
                        summary: "Now supports the amended bill.",
                    })}
                    runInFlight={false}
                    testimonyMissing={false}
                />,
            );

            expect(screen.getByTestId("campaign-name-line")).toHaveTextContent("Updated Streets Letter");
            expect(screen.getByText("Now supports the amended bill.")).toBeInTheDocument();
        });
    });
});
