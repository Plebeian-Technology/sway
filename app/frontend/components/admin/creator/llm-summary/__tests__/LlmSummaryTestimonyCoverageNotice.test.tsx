import { render, screen } from "@testing-library/react";
import LlmSummaryTestimonyCoverageNotice from "app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyCoverageNotice";
import { TESTIMONY_COVERAGE_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/testimonyCoverageNoticeId";
import { ITestimonyCoverage } from "app/frontend/components/admin/creator/llm-summary/types";

// Every field CoverageReport::Result carries, so each test below only
// overrides the fields its state actually depends on (67-UI-SPEC.md Surface
// 1's state table).
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

describe("LlmSummaryTestimonyCoverageNotice", () => {
    it("renders nothing when the state is no_testimony", () => {
        const { container } = render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    state: "no_testimony",
                    coverage_gap: false,
                    total_chars: 0,
                    total_letters: null,
                }}
            />,
        );

        expect(container).toBeEmptyDOMElement();
    });

    it("carries the shared aria id every disabled Approve button points at", () => {
        render(<LlmSummaryTestimonyCoverageNotice billId={1} runInFlight={false} coverage={baseCoverage} />);

        expect(screen.getByTestId("llm-testimony-coverage-notice")).toHaveAttribute("id", TESTIMONY_COVERAGE_NOTICE_ID);
    });

    describe("nothing left out", () => {
        it("says all the letters reached the model, in the info variant, and offers nothing to acknowledge", () => {
            render(<LlmSummaryTestimonyCoverageNotice billId={1} runInFlight={false} coverage={baseCoverage} />);

            const notice = screen.getByTestId("llm-testimony-coverage-notice");
            expect(screen.getByText("Testimony coverage")).toBeInTheDocument();
            expect(notice).toHaveTextContent("All 439 letters reached the model. Repeated text was removed first.");
            expect(notice).toHaveAttribute("data-variant", "info");
            // E6 "empty": nothing was left out, so there is nothing to acknowledge.
            expect(screen.queryByRole("button", { name: "Acknowledge the missing testimony" })).toBeNull();
        });

        // The zero case never uses the did-not-reach phrasing at all.
        it("says all zero letters reached the model at zero, never 'did not reach'", () => {
            render(
                <LlmSummaryTestimonyCoverageNotice
                    billId={1}
                    runInFlight={false}
                    coverage={{
                        ...baseCoverage,
                        coverage_gap: false,
                        total_letters: 0,
                        reached_letters: 0,
                        left_out_letters: 0,
                    }}
                />,
            );

            const notice = screen.getByTestId("llm-testimony-coverage-notice");
            expect(notice).toHaveTextContent("All 0 letters reached the model. Repeated text was removed first.");
            expect(notice).not.toHaveTextContent(/did not reach/);
        });
    });

    // A single unsplit letter counts as "reached" once one of its own characters lands inside
    // the budget, so left_out_letters can read 0 while left_out_chars is still positive. The
    // notice must never claim "All N letters reached" in that case.
    it("never says all letters reached when characters were left out despite left_out_letters being 0", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    coverage_gap: true,
                    total_letters: 1,
                    reached_letters: 1,
                    left_out_letters: 0,
                    left_out_chars: 5_106,
                }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("Some testimony did not reach the model")).toBeInTheDocument();
        expect(notice).not.toHaveTextContent(/^All/);
        expect(notice).toHaveTextContent(
            "1 letter reached the model, but not in full. The prompt reached its size limit. Approval is blocked until you acknowledge this.",
        );
        expect(notice).toHaveAttribute("data-variant", "warning");
        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    it("says how many letters did not reach the model, in the warning variant, and offers the acknowledge button, when something was left out", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    coverage_gap: true,
                    total_letters: 439,
                    reached_letters: 412,
                    left_out_letters: 27,
                }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("Some testimony did not reach the model")).toBeInTheDocument();
        expect(notice).toHaveTextContent(
            "27 of 439 letters did not reach the model. The prompt reached its size limit. Approval is blocked until you acknowledge this.",
        );
        expect(notice).toHaveAttribute("data-variant", "warning");
        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    it("names the raw fallback and states the character split when the stage never ran, and offers the acknowledge button", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    state: "never_run",
                    coverage_gap: true,
                    total_chars: 1037523,
                    reached_chars: 150000,
                    total_letters: null,
                    reached_letters: null,
                    removed_letters: null,
                    left_out_letters: null,
                }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("This testimony was not cleaned")).toBeInTheDocument();
        expect(notice).toHaveTextContent(
            "The clean-testimony stage has not run on this bill. The model read the first 150,000 characters of 1,037,523.",
        );
        // Raw extraction sits here uncleaned, so never_run always gates.
        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    // No raw extraction exists to have cleaned — only a hand-pasted remedy — so never_run does
    // not gate here even though the state name is the same as the case above.
    it("offers no acknowledge button when never_run means a paste with nothing extracted", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    state: "never_run",
                    coverage_gap: false,
                    total_chars: 5000,
                    reached_chars: 5000,
                    paste_present: true,
                    paste_chars: 5000,
                    total_letters: null,
                    reached_letters: null,
                    removed_letters: null,
                    left_out_letters: null,
                }}
            />,
        );

        expect(screen.queryByRole("button", { name: "Acknowledge the missing testimony" })).not.toBeInTheDocument();
    });

    // An artifact exists but a later fetch superseded it — the prompt fell back to the raw
    // column, so this gets its own notice telling the operator to re-run the stage.
    it("tells the operator to re-run the stage when the cleaned artifact has gone stale, and offers the acknowledge button", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    state: "stale",
                    coverage_gap: true,
                    total_chars: 170000,
                    reached_chars: 150000,
                    total_letters: null,
                    reached_letters: null,
                    removed_letters: null,
                    left_out_letters: null,
                }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("This testimony needs to be cleaned again")).toBeInTheDocument();
        expect(notice).toHaveTextContent(
            "Newer hearing testimony arrived after this bill was last cleaned, so the model read the raw testimony instead. It read the first 150,000 characters of 170,000. Re-run the clean-testimony stage.",
        );
        expect(notice).toHaveAttribute("data-variant", "warning");
        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    it("states its own title and body, without repeating the failure reason, when the stage failed, and offers the acknowledge button", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    state: "failed",
                    coverage_gap: true,
                    total_letters: 439,
                    reached_letters: 412,
                    left_out_letters: 27,
                }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("The clean-testimony stage failed")).toBeInTheDocument();
        expect(notice).toHaveTextContent(
            "The model read the raw testimony instead. 27 of 439 letters did not reach the model.",
        );
        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeInTheDocument();
    });

    it("says the numbers come from the last run while the stage is running", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{ ...baseCoverage, state: "running", coverage_gap: false }}
            />,
        );

        const notice = screen.getByTestId("llm-testimony-coverage-notice");
        expect(screen.getByText("The clean-testimony stage is running")).toBeInTheDocument();
        expect(notice).toHaveTextContent("These numbers come from the last run.");
    });

    // E6 "loading": the acknowledge button is also disabled while a pipeline run is in flight.
    it("disables the acknowledge button while a pipeline run is in flight", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={true}
                coverage={{
                    ...baseCoverage,
                    coverage_gap: true,
                    total_letters: 439,
                    reached_letters: 412,
                    left_out_letters: 27,
                }}
            />,
        );

        expect(screen.getByRole("button", { name: "Acknowledge the missing testimony" })).toBeDisabled();
    });

    // E6 "partial": once acknowledged, the stamp replaces the button, not a page reload of its own.
    it("shows the ACKNOWLEDGED stamp instead of the button once the server says so", () => {
        render(
            <LlmSummaryTestimonyCoverageNotice
                billId={1}
                runInFlight={false}
                coverage={{
                    ...baseCoverage,
                    coverage_gap: true,
                    total_letters: 439,
                    reached_letters: 412,
                    left_out_letters: 27,
                    acknowledged: true,
                    acknowledged_by_email: "github@sway.vote",
                    acknowledged_at: "2026-08-13T20:51:00Z",
                }}
            />,
        );

        expect(screen.getByText("ACKNOWLEDGED")).toBeInTheDocument();
        expect(screen.queryByRole("button", { name: "Acknowledge the missing testimony" })).toBeNull();
    });

    it("never renders a hard-coded color literal or arbitrary var() class", () => {
        const { container } = render(
            <LlmSummaryTestimonyCoverageNotice billId={1} runInFlight={false} coverage={baseCoverage} />,
        );

        expect(container.innerHTML).not.toMatch(/#[0-9a-fA-F]{6}|rgb\(|hsl\(|\[var\(--/);
    });
});
