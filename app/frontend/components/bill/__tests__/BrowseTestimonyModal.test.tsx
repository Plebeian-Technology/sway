// @lat: [[testimony-letters#Browsing constituent testimony in the modal]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockReload = vi.fn<(...args: unknown[]) => void>();
const mockPatch = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        reload: (...args: unknown[]) => mockReload(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
    },
}));

import BrowseTestimonyModal, {
    IPublicTestimonyCounts,
    IPublicTestimonyLetter,
} from "app/frontend/components/bill/BrowseTestimonyModal";

const SAMPLE_COUNTS: IPublicTestimonyCounts = {
    total: 25,
    support: 15,
    oppose: 7,
    neutral: 3,
};

const makeLetters = (
    count: number,
    stance: "support" | "oppose" | "neutral" = "support",
    startPosition = 1,
): IPublicTestimonyLetter[] =>
    Array.from({ length: count }, (_, idx) => {
        const pos = startPosition + idx;
        return {
            position: pos,
            label: `Constituent Letter #${pos}`,
            stance,
            body_text: `Testimony text for constituent letter ${pos}.`,
        };
    });

const SAMPLE_LETTERS: IPublicTestimonyLetter[] = [
    ...makeLetters(15, "support", 1),
    ...makeLetters(7, "oppose", 16),
    ...makeLetters(3, "neutral", 23),
];

describe("BrowseTestimonyModal", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    afterEach(() => {
        cleanup();
    });

    it("1. renders when isOpen={true} with header, tabs, and count badges", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                billTitle="HB-100: Clean Energy Standards"
            />,
        );

        expect(screen.getByRole("heading", { name: "Public Testimony" })).toBeInTheDocument();
        expect(screen.getByText("HB-100: Clean Energy Standards")).toBeInTheDocument();
        expect(screen.getByText("25 constituent letters")).toBeInTheDocument();

        expect(screen.getByTestId("tab-all")).toHaveTextContent("All (25)");
        expect(screen.getByTestId("tab-support")).toHaveTextContent("Support (15)");
        expect(screen.getByTestId("tab-oppose")).toHaveTextContent("Oppose (7)");
        expect(screen.getByTestId("tab-neutral")).toHaveTextContent("Neutral (3)");

        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
        expect(screen.getByText("Constituent Letter #1")).toBeInTheDocument();
    });

    it("2. does not render / stays hidden when isOpen={false}", () => {
        render(
            <BrowseTestimonyModal
                isOpen={false}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        expect(screen.queryByText("Public Testimony")).not.toBeInTheDocument();
        expect(screen.queryByTestId("letters-list")).not.toBeInTheDocument();
    });

    it("3. filters letters when clicking different stance tabs (Support, Oppose, Neutral, All)", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-16")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("tab-oppose"));
        expect(screen.getByTestId("testimony-letter-16")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-22")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-1")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("tab-neutral"));
        expect(screen.getByTestId("testimony-letter-23")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-25")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-16")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("tab-support"));
        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-23")).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId("tab-all"));
        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
    });

    it("4. paginates letters (10 per page), disabling Previous on page 1, disabling Next on last page", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        const prevButton = screen.getByTestId("pagination-prev");
        const nextButton = screen.getByTestId("pagination-next");
        const indicator = screen.getByTestId("pagination-indicator");

        expect(indicator).toHaveTextContent("Page 1 of 3");
        expect(prevButton).toBeDisabled();
        expect(nextButton).toBeEnabled();
        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-10")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-11")).not.toBeInTheDocument();

        fireEvent.click(nextButton);
        expect(indicator).toHaveTextContent("Page 2 of 3");
        expect(prevButton).toBeEnabled();
        expect(nextButton).toBeEnabled();
        expect(screen.queryByTestId("testimony-letter-1")).not.toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-11")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-20")).toBeInTheDocument();

        fireEvent.click(nextButton);
        expect(indicator).toHaveTextContent("Page 3 of 3");
        expect(prevButton).toBeEnabled();
        expect(nextButton).toBeDisabled();
        expect(screen.getByTestId("testimony-letter-21")).toBeInTheDocument();
        expect(screen.getByTestId("testimony-letter-25")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-20")).not.toBeInTheDocument();

        fireEvent.click(prevButton);
        expect(indicator).toHaveTextContent("Page 2 of 3");
        expect(screen.getByTestId("testimony-letter-11")).toBeInTheDocument();
    });

    it("5. resets pagination to page 1 upon tab switch", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        fireEvent.click(screen.getByTestId("pagination-next"));
        expect(screen.getByTestId("pagination-indicator")).toHaveTextContent("Page 2 of 3");

        fireEvent.click(screen.getByTestId("tab-support"));
        expect(screen.getByTestId("pagination-indicator")).toHaveTextContent("Page 1 of 2");
        expect(screen.getByTestId("testimony-letter-1")).toBeInTheDocument();
        expect(screen.getByTestId("pagination-prev")).toBeDisabled();
    });

    it("6. calls router.reload({ only: ['public_testimony_letters'] }) when opened without letters", () => {
        render(
            <BrowseTestimonyModal isOpen={true} onClose={vi.fn<() => void>()} counts={SAMPLE_COUNTS} letters={null} />,
        );

        expect(mockReload).toHaveBeenCalledTimes(1);
        expect(mockReload).toHaveBeenCalledWith(
            expect.objectContaining({
                only: ["public_testimony_letters"],
            }),
        );
        expect(mockReload.mock.calls[0][0]).not.toHaveProperty("preserveScroll");

        expect(screen.getByTestId("loading-state")).toBeInTheDocument();
        expect(screen.getByText("Loading testimony…")).toBeInTheDocument();
    });

    it("7. calls onClose when close button is clicked", () => {
        const handleClose = vi.fn<() => void>();
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={handleClose}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        const closeButton = screen.getByRole("button", { name: "Close" });
        fireEvent.click(closeButton);

        expect(handleClose).toHaveBeenCalledTimes(1);
    });

    it("supports initialFilter prop to open on a specific stance tab", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                initialFilter="oppose"
            />,
        );

        expect(screen.getByTestId("testimony-letter-16")).toBeInTheDocument();
        expect(screen.queryByTestId("testimony-letter-1")).not.toBeInTheDocument();
    });

    it("renders friendly empty message when a tab has no letters", () => {
        const supportOnlyLetters = makeLetters(5, "support");
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={{ total: 5, support: 5, oppose: 0, neutral: 0 }}
                letters={supportOnlyLetters}
            />,
        );

        fireEvent.click(screen.getByTestId("tab-oppose"));
        expect(screen.getByTestId("empty-state")).toBeInTheDocument();
        expect(screen.getByText("No constituent testimony found.")).toBeInTheDocument();
    });

    it("does not trigger router.reload when letters are already provided", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
            />,
        );

        expect(mockReload).not.toHaveBeenCalled();
    });

    it("does not trigger router.reload when counts total is 0", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={{ total: 0, support: 0, oppose: 0, neutral: 0 }}
                letters={null}
            />,
        );

        expect(mockReload).not.toHaveBeenCalled();
    });

    it("supports open, onOpenChange, and initialStance props and reloads when counts is omitted", () => {
        const handleOpenChange = vi.fn<(open: boolean) => void>();
        render(<BrowseTestimonyModal open={true} onOpenChange={handleOpenChange} initialStance="oppose" />);

        expect(mockReload).toHaveBeenCalledWith(
            expect.objectContaining({
                only: ["public_testimony_letters"],
            }),
        );

        fireEvent.click(screen.getByRole("button", { name: "Close" }));
        expect(handleOpenChange).toHaveBeenCalledWith(false);
    });

    it("transitions from loading to empty state when router.reload finishes or errors without returning letters", () => {
        mockReload.mockImplementationOnce((opts: unknown) => {
            const options = opts as { onFinish?: () => void };
            options.onFinish?.();
        });

        render(<BrowseTestimonyModal open={true} counts={SAMPLE_COUNTS} letters={undefined} />);

        expect(screen.queryByTestId("loading-state")).not.toBeInTheDocument();
        expect(screen.getByTestId("empty-state")).toBeInTheDocument();
    });

    it("uses semantic theme tokens and stamp badges without raw palette or dark: classes", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                billTitle="HB-100: Clean Energy Standards"
            />,
        );

        const letterCard = screen.getByTestId("testimony-letter-1");
        expect(letterCard.className).toContain("bg-card");
        expect(letterCard.className).toContain("border-border-strong");

        const badge = letterCard.querySelector('[data-slot="badge"]');
        expect(badge).toHaveAttribute("data-variant", "stamp");
        expect(badge).toHaveAttribute("data-tone", "success");

        const dialogHtml = screen.getByRole("dialog").innerHTML;
        expect(dialogHtml).not.toMatch(/\bdark:/);
        expect(dialogHtml).not.toMatch(/\b(emerald|rose|slate|amber|green|red)-\d+/);
    });

    it("renders stance override select when canOverrideStance={true} and billId is provided, and calls router.patch on change", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                billId={169}
                canOverrideStance={true}
            />,
        );

        const select = screen.getByTestId("select-letter-stance-1");
        expect(select).toHaveValue("support");

        fireEvent.change(select, { target: { value: "oppose" } });

        expect(mockPatch).toHaveBeenCalledWith(
            "/bills/169/testimony_letter_stance",
            { position: 1, stance: "oppose" },
            {
                preserveScroll: true,
                preserveState: true,
                only: ["public_testimony_counts", "public_testimony_letters", "flash"],
            },
        );
    });

    it("omits stance override select when canOverrideStance is false or omitted", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                billId={169}
            />,
        );

        expect(screen.queryByTestId("select-letter-stance-1")).not.toBeInTheDocument();
        expect(screen.queryByTestId("remove-letter-1")).not.toBeInTheDocument();
    });

    it("renders Remove button when canOverrideStance={true} and billId is provided, and calls router.patch with excluded: true", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={SAMPLE_COUNTS}
                letters={SAMPLE_LETTERS}
                billId={169}
                canOverrideStance={true}
            />,
        );

        const removeBtn = screen.getByTestId("remove-letter-1");
        expect(removeBtn).toHaveAttribute("aria-label", "Remove Constituent Letter #1");

        fireEvent.click(removeBtn);

        expect(mockPatch).toHaveBeenCalledWith(
            "/bills/169/testimony_letter_stance",
            { position: 1, excluded: true },
            {
                preserveScroll: true,
                preserveState: true,
                only: ["public_testimony_counts", "public_testimony_letters", "flash"],
            },
        );
    });

    it("triggers router.reload({ only: ['public_testimony_letters'] }) when letters is an empty array but counts.total > 0", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={{ total: 3, support: 1, oppose: 2, neutral: 0 }}
                letters={[]}
            />,
        );

        expect(mockReload).toHaveBeenCalledTimes(1);
        expect(mockReload).toHaveBeenCalledWith(
            expect.objectContaining({
                only: ["public_testimony_letters"],
            }),
        );
    });

    it("triggers router.reload({ only: ['public_testimony_letters'] }) when letters length does not match counts.total", () => {
        render(
            <BrowseTestimonyModal
                isOpen={true}
                onClose={vi.fn<() => void>()}
                counts={{ total: 2, support: 1, oppose: 1, neutral: 0 }}
                letters={[SAMPLE_LETTERS[0]]}
            />,
        );

        expect(mockReload).toHaveBeenCalledTimes(1);
        expect(mockReload).toHaveBeenCalledWith(
            expect.objectContaining({
                only: ["public_testimony_letters"],
            }),
        );
    });
});
