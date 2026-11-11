import { render, screen } from "@testing-library/react";
import TestimonyCampaignTable from "app/frontend/components/admin/creator/testimony-report/TestimonyCampaignTable";
import { ITestimonyCampaignDraft } from "app/frontend/components/admin/creator/llm-summary/types";

const row = (overrides: Partial<ITestimonyCampaignDraft> = {}): ITestimonyCampaignDraft => ({
    content_hash: "abc123",
    sender_count: 324,
    letter_count: 324,
    added_words_characters: 310,
    senders_added_words_left_out: 0,
    domain: "everyactioncustom.com",
    ...overrides,
});

describe("TestimonyCampaignTable", () => {
    it("renders the muted italic empty sentence, not a table, when there are no campaigns", () => {
        render(<TestimonyCampaignTable rows={[]} />);

        const empty = screen.getByText("No campaign letters were found on this bill.");
        expect(empty).toBeInTheDocument();
        expect(empty).toHaveClass("italic", "text-muted-foreground");
        expect(screen.queryByRole("table")).toBeNull();
    });

    it("renders one campaign as a plain table with no collapsible wrapper", () => {
        render(<TestimonyCampaignTable rows={[row()]} />);

        expect(screen.getByRole("table")).toBeInTheDocument();
        expect(screen.queryByTestId(/^collapsible-panel-/)).toBeNull();
        expect(screen.getByRole("columnheader", { name: "Campaign" })).toBeInTheDocument();
        expect(screen.getByRole("columnheader", { name: "Senders" })).toBeInTheDocument();
        expect(screen.getByRole("columnheader", { name: "Letters" })).toBeInTheDocument();
        expect(screen.getByRole("columnheader", { name: "Added words" })).toBeInTheDocument();
        expect(screen.getByText("324 people sent this letter")).toBeInTheDocument();
    });

    // WR-01. added_words_characters is a count of CHARACTERS (the resource
    // measures group["added_words"].to_s.length) and
    // senders_added_words_left_out is a count of SENDERS (the marker adds one
    // per letter). Subtracting one from the other produced a number of
    // nothing at all — and added_words is already the KEPT text, so it was
    // never the total either. The two facts render as the two facts they are.
    it("states the character count, with no bound note, when nothing was left out", () => {
        render(<TestimonyCampaignTable rows={[row({ senders_added_words_left_out: 0 })]} />);

        expect(screen.getByText("310 characters of senders' own words")).toBeInTheDocument();
        expect(screen.queryByText(/limit on added words/)).toBeNull();
    });

    it("states the same character count, never a count with senders subtracted from it, when the bound was reached", () => {
        render(
            <TestimonyCampaignTable rows={[row({ added_words_characters: 310, senders_added_words_left_out: 168 })]} />,
        );

        expect(screen.getByText("310 characters of senders' own words")).toBeInTheDocument();
        expect(screen.queryByText(/142/)).toBeNull();
        expect(
            screen.getByText("The limit on added words was reached. 168 senders' own words were not kept."),
        ).toBeInTheDocument();
    });

    // Every count TestimonyCampaignDraftResource ships comes from
    // CampaignMarker#finalize_group, which always writes an Integer — so a
    // measured zero is the only "nothing here" this table can be handed.
    it("renders a measured zero as a zero", () => {
        render(<TestimonyCampaignTable rows={[row({ sender_count: 0, letter_count: 0 })]} />);

        expect(screen.getAllByText("0").length).toBeGreaterThan(0);
        expect(screen.queryByText("—")).toBeNull();
    });

    it("renders eight rows as a plain table with no collapsible wrapper", () => {
        const rows = Array.from({ length: 8 }, (_, i) => row({ content_hash: `hash-${i}` }));
        render(<TestimonyCampaignTable rows={rows} />);

        expect(screen.getByRole("table")).toBeInTheDocument();
        expect(screen.queryByTestId(/^collapsible-panel-/)).toBeNull();
    });

    it("wraps nine rows in a closed-by-default collapsible panel carrying the count in its title", () => {
        const rows = Array.from({ length: 9 }, (_, i) => row({ content_hash: `hash-${i}` }));
        render(<TestimonyCampaignTable rows={rows} />);

        const trigger = screen.getByText("Campaigns (9)");
        expect(trigger).toBeInTheDocument();
        // Closed by default: the table's own content is not present in the accessibility tree.
        expect(screen.queryByRole("table")).toBeNull();
    });

    it("never renders a hard-coded color literal or arbitrary var() class", () => {
        const { container } = render(<TestimonyCampaignTable rows={[row()]} />);

        expect(container.innerHTML).not.toMatch(/#[0-9a-fA-F]{6}|rgb\(|hsl\(|\[var\(--/);
    });
});
