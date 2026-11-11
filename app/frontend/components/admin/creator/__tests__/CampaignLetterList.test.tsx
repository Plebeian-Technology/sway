import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

type TReloadOptions = {
    only: string[];
    onError?: (errors: Record<string, string>) => void;
    onFinish?: () => void;
};

const reload = vi.fn<(options: TReloadOptions) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        reload: (options: TReloadOptions) => reload(options),
    },
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, onClick, disabled, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button onClick={onClick} disabled={disabled} {...props}>
            {children}
        </button>
    ),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, tone, ...props }: React.HTMLAttributes<HTMLSpanElement> & { tone?: string }) => (
        <span data-tone={tone} {...props}>
            {children}
        </span>
    ),
}));

import CampaignLetterList from "app/frontend/components/admin/creator/campaign-position-card/CampaignLetterList";
import { ITestimonyCampaignLetter } from "app/frontend/components/admin/creator/llm-summary/types";

afterEach(() => {
    cleanup();
    reload.mockReset();
});

const letter = (overrides: Partial<ITestimonyCampaignLetter> = {}): ITestimonyCampaignLetter => ({
    position: 0,
    text: "Please support this bill.",
    sender_address: "jane@example.com",
    sender_domain: "example.com",
    repeat: false,
    ...overrides,
});

const disclosure = () => screen.getByTestId("btn-campaign-letters-disclosure");

describe("CampaignLetterList", () => {
    it("reports that no letter text exists when the fetch settles without a bundle for this draft", () => {
        // The response carried bundles, but none keyed to this draft's content
        // hash, so the card is still handed undefined rather than an empty array.
        reload.mockImplementation((options) => options.onFinish?.());

        render(<CampaignLetterList letters={undefined} letterCount={3} />);

        fireEvent.click(disclosure());

        expect(screen.queryByTestId("campaign-letters-loading")).not.toBeInTheDocument();
        expect(screen.getByTestId("campaign-letters-empty")).toBeInTheDocument();
    });

    it("renders nothing at all when the letter count is zero", () => {
        const { container } = render(<CampaignLetterList letters={[]} letterCount={0} />);

        expect(container).toBeEmptyDOMElement();
    });

    it("is collapsed by default, showing a disclosure button and no letter text", () => {
        render(<CampaignLetterList letters={[letter()]} letterCount={1} />);

        expect(disclosure()).toHaveTextContent("Show 1 letter");
        expect(screen.queryByText("Please support this bill.")).not.toBeInTheDocument();
    });

    it("labels the button from the letter count even when it differs from the letters array length", () => {
        render(<CampaignLetterList letters={[letter()]} letterCount={5} />);

        expect(disclosure()).toHaveTextContent("Show 5 letters");
    });

    it("expands on click, showing each letter's id, sender, and text", () => {
        render(<CampaignLetterList letters={[letter({ position: 12 })]} letterCount={1} />);

        fireEvent.click(disclosure());

        expect(screen.getByTestId("campaign-letter-id-12")).toHaveTextContent("Letter #12");
        expect(screen.getByText("jane@example.com")).toBeInTheDocument();
        expect(screen.getByText("Please support this bill.")).toBeInTheDocument();
        expect(disclosure()).toHaveTextContent("Hide letters");
    });

    it("shows one letter per page, and the next letter on the next page", () => {
        const letters = [
            letter({ position: 0, text: "First letter." }),
            letter({ position: 1, text: "Second letter.", sender_address: "sam@example.com" }),
            letter({ position: 2, text: "Third letter.", sender_address: "kim@example.com" }),
        ];
        render(<CampaignLetterList letters={letters} letterCount={3} />);

        fireEvent.click(disclosure());

        expect(screen.getAllByLabelText("Pagination")).toHaveLength(2);
        expect(screen.getByText("First letter.")).toBeInTheDocument();
        expect(screen.queryByText("Second letter.")).not.toBeInTheDocument();

        fireEvent.click(screen.getAllByLabelText("Next page")[0]);

        expect(screen.queryByText("First letter.")).not.toBeInTheDocument();
        expect(screen.getByText("Second letter.")).toBeInTheDocument();
        expect(screen.getAllByLabelText("Page 2")[0]).toHaveAttribute("aria-current", "page");
    });

    it("draws no page strip for a single letter", () => {
        render(<CampaignLetterList letters={[letter()]} letterCount={1} />);

        fireEvent.click(disclosure());

        expect(screen.queryByLabelText("Pagination")).not.toBeInTheDocument();
    });

    it("marks a repeat letter as a duplicate", () => {
        render(<CampaignLetterList letters={[letter({ repeat: true })]} letterCount={1} />);

        fireEvent.click(disclosure());

        expect(screen.getByTestId("campaign-letter-repeat-0")).toHaveTextContent("DUPLICATE");
    });

    it("falls back to the sender domain, then Unknown sender, when the address is missing", () => {
        render(
            <CampaignLetterList
                letters={[
                    letter({ position: 0, sender_address: null, sender_domain: "everyactioncustom.com" }),
                    letter({ position: 1, sender_address: null, sender_domain: null }),
                ]}
                letterCount={2}
            />,
        );

        fireEvent.click(disclosure());

        expect(screen.getByText("everyactioncustom.com")).toBeInTheDocument();

        fireEvent.click(screen.getAllByLabelText("Next page")[0]);

        expect(screen.getByText("Unknown sender")).toBeInTheDocument();
    });

    describe("fetching the letters on open", () => {
        it("reloads naming only the testimony_campaign_letters prop, and says the fetch is running", () => {
            render(<CampaignLetterList letters={undefined} letterCount={2} />);

            fireEvent.click(disclosure());

            expect(reload).toHaveBeenCalledTimes(1);
            expect(reload.mock.calls[0][0].only).toEqual(["testimony_campaign_letters"]);
            expect(screen.getByTestId("campaign-letters-loading")).toBeInTheDocument();
            expect(screen.queryByTestId("campaign-letter-items")).not.toBeInTheDocument();
        });

        it("asks for nothing when the letters are already on the page", () => {
            render(<CampaignLetterList letters={[letter()]} letterCount={1} />);

            fireEvent.click(disclosure());

            expect(reload).not.toHaveBeenCalled();
            expect(screen.queryByTestId("campaign-letters-loading")).not.toBeInTheDocument();
        });

        it("asks once only, even when the disclosure is collapsed and reopened after the letters arrive", () => {
            const { rerender } = render(<CampaignLetterList letters={undefined} letterCount={2} />);

            fireEvent.click(disclosure());
            rerender(<CampaignLetterList letters={[letter()]} letterCount={2} />);
            fireEvent.click(disclosure());
            fireEvent.click(disclosure());

            expect(reload).toHaveBeenCalledTimes(1);
            expect(screen.getByText("Please support this bill.")).toBeInTheDocument();
        });

        it("asks once only while the first request is still in flight", () => {
            render(<CampaignLetterList letters={undefined} letterCount={2} />);

            fireEvent.click(disclosure());
            fireEvent.click(disclosure());
            fireEvent.click(disclosure());

            expect(reload).toHaveBeenCalledTimes(1);
        });

        it("reports a failed fetch and offers a retry that asks again", () => {
            reload.mockImplementation((options) => options.onError?.({ testimony_campaign_letters: "boom" }));

            render(<CampaignLetterList letters={undefined} letterCount={2} />);

            fireEvent.click(disclosure());

            expect(screen.getByTestId("campaign-letters-error")).toHaveTextContent("The letters could not be loaded.");
            expect(screen.queryByTestId("campaign-letters-loading")).not.toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-campaign-letters-retry"));

            expect(reload).toHaveBeenCalledTimes(2);
        });

        it("says no letter text could be produced when the fetch succeeds and returns none", () => {
            const { rerender } = render(<CampaignLetterList letters={undefined} letterCount={2} />);

            fireEvent.click(disclosure());
            rerender(<CampaignLetterList letters={[]} letterCount={2} />);

            expect(screen.getByTestId("campaign-letters-empty")).toHaveTextContent(
                "No letter text could be produced for this campaign.",
            );
            expect(screen.queryByTestId("campaign-letter-items")).not.toBeInTheDocument();
            expect(screen.queryByTestId("campaign-letters-loading")).not.toBeInTheDocument();
        });
    });
});
