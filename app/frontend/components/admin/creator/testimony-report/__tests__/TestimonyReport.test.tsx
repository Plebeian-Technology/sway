import { render, screen } from "@testing-library/react";
import TestimonyReport from "app/frontend/components/admin/creator/testimony-report/TestimonyReport";
import { ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";

const baseCoverage: ITestimonyCoverage = {
    state: "cleaned",
    coverage_gap: false,
    total_chars: 1037523,
    reached_chars: 180253,
    removed_chars: 857270,
    repair_added_chars: 0,
    left_out_chars: 0,
    total_letters: 439,
    reached_letters: 439,
    removed_letters: 0,
    left_out_letters: 0,
    individual_letter_count: 71,
    model_fallback_letter_count: 0,
    attachment_cut_count: 0,
    attachment_cut_cap: null,
    paste_present: false,
    paste_chars: 0,
    paste_share_of_limit: null,
    displaced_letter_count: 0,
    digest: "a".repeat(64),
    acknowledged: false,
    acknowledged_by_email: null,
    acknowledged_at: null,
};

const campaignDraft = {
    content_hash: "abc123",
    sender_count: 324,
    letter_count: 324,
    added_words_characters: 310,
    senders_added_words_left_out: 0,
    domain: "everyactioncustom.com",
    letters: [],
};

describe("TestimonyReport", () => {
    it("renders nothing at all when there is no coverage", () => {
        const { container } = render(<TestimonyReport coverage={null} campaignDrafts={[]} />);

        expect(container).toBeEmptyDOMElement();
    });

    it("renders nothing at all when the state is no_testimony", () => {
        const { container } = render(
            <TestimonyReport coverage={{ ...baseCoverage, state: "no_testimony" }} campaignDrafts={[]} />,
        );

        expect(container).toBeEmptyDOMElement();
    });

    // Bill 62, the phase's reference render.
    it("draws the four blocks for the reference render", () => {
        render(<TestimonyReport coverage={baseCoverage} campaignDrafts={[campaignDraft]} />);

        expect(screen.getByText("Testimony report")).toBeInTheDocument();
        expect(screen.getByText("What reached the model")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-record-bar")).toBeInTheDocument();
        expect(screen.getByText("Campaigns")).toBeInTheDocument();
        expect(screen.getByText("324 people sent this letter")).toBeInTheDocument();
        expect(screen.getByText("People speaking for themselves")).toBeInTheDocument();
        expect(
            screen.getByText(
                "71 letters came from people speaking for themselves. The model read them. They cannot become an organization position.",
            ),
        ).toBeInTheDocument();
        expect(screen.queryByText("Your pasted testimony")).toBeNull();
    });

    it("says no campaign letters were found, in the muted-italic empty state, for zero campaigns", () => {
        render(<TestimonyReport coverage={baseCoverage} campaignDrafts={[]} />);

        expect(screen.getByText("No campaign letters were found on this bill.")).toBeInTheDocument();
    });

    it("states its own zero sentence for zero letters from people speaking for themselves", () => {
        render(<TestimonyReport coverage={{ ...baseCoverage, individual_letter_count: 0 }} campaignDrafts={[]} />);

        expect(screen.getByText("No letters came from people speaking for themselves.")).toBeInTheDocument();
    });

    // A number never measured (no cleaned artifact ever existed) must not render as a
    // measured zero — the whole block is absent instead.
    it("renders no individuals block at all when the count was never measured", () => {
        render(
            <TestimonyReport
                coverage={{ ...baseCoverage, state: "never_run", individual_letter_count: null }}
                campaignDrafts={[]}
            />,
        );

        expect(screen.queryByText("People speaking for themselves")).toBeNull();
        expect(screen.queryByText(/people speaking for themselves/)).toBeNull();
    });

    it("renders the pasted-testimony block only when the operator has pasted something", () => {
        render(
            <TestimonyReport
                coverage={{
                    ...baseCoverage,
                    paste_present: true,
                    paste_chars: 93000,
                    paste_share_of_limit: 0.62,
                    displaced_letter_count: 27,
                }}
                campaignDrafts={[]}
            />,
        );

        expect(screen.getByText("Your pasted testimony")).toBeInTheDocument();
        expect(
            screen.getByText(
                "Your pasted text is in the prompt exactly as you saved it. It was not cleaned. It fills 62% of the size limit — 93,000 of 150,000 characters. Your pasted text is joined first, so it is never left out. 27 letters did not fit within the size limit.",
            ),
        ).toBeInTheDocument();
    });

    it("adds a header line and leaves the last run's numbers visible while the stage is running", () => {
        render(<TestimonyReport coverage={{ ...baseCoverage, state: "running" }} campaignDrafts={[campaignDraft]} />);

        expect(
            screen.getByText("The clean-testimony stage is running. These numbers are from the last run."),
        ).toBeInTheDocument();
        // The last run's numbers are still on screen, not hidden behind a skeleton.
        expect(screen.getByTestId("testimony-record-bar")).toBeInTheDocument();
        expect(screen.getByText("324 people sent this letter")).toBeInTheDocument();
    });

    it("adds a header line saying the run failed, without repeating the failure reason", () => {
        render(<TestimonyReport coverage={{ ...baseCoverage, state: "failed" }} campaignDrafts={[]} />);

        expect(
            screen.getByText("The clean-testimony stage failed. These numbers are from the last successful run."),
        ).toBeInTheDocument();
    });

    it("adds a header line saying the artifact is stale, telling the operator to re-run the stage", () => {
        render(<TestimonyReport coverage={{ ...baseCoverage, state: "stale" }} campaignDrafts={[]} />);

        expect(
            screen.getByText(
                "Newer hearing testimony arrived after this bill was last cleaned. These numbers are from the raw testimony — re-run the stage.",
            ),
        ).toBeInTheDocument();
    });

    it("adds no header line for the ordinary cleaned state", () => {
        render(<TestimonyReport coverage={baseCoverage} campaignDrafts={[]} />);

        expect(screen.queryByText(/These numbers are from the last/)).toBeNull();
    });

    it("never renders a hard-coded color literal or arbitrary var() class", () => {
        const { container } = render(<TestimonyReport coverage={baseCoverage} campaignDrafts={[campaignDraft]} />);

        expect(container.innerHTML).not.toMatch(/#[0-9a-fA-F]{6}|rgb\(|hsl\(|\[var\(--/);
    });
});
