// @lat: [[testimony-letters#Presenting public testimony on bill pages]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockReload = vi.fn<(...args: unknown[]) => void>();

vi.mock("@inertiajs/react", () => ({
    router: {
        reload: (...args: unknown[]) => mockReload(...args),
    },
}));

import PublicTestimonySection from "app/frontend/components/bill/PublicTestimonySection";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import type { sway } from "sway";

const SAMPLE_COUNTS: sway.IPublicTestimonyCounts = {
    total: 25,
    support: 15,
    oppose: 7,
    neutral: 3,
};

const SAMPLE_LETTERS: sway.IPublicTestimonyLetter[] = [
    {
        position: 1,
        label: "Constituent Letter #1",
        stance: "support",
        body_text: "I strongly support this bill for clean neighborhood air.",
    },
    {
        position: 2,
        label: "Constituent Letter #2",
        stance: "oppose",
        body_text: "I oppose the fee increases mandated by this bill.",
    },
    {
        position: 3,
        label: "Constituent Letter #3",
        stance: "neutral",
        body_text: "Neutral comments on procedural timelines.",
    },
];

describe("PublicTestimonySection", () => {
    beforeEach(() => {
        vi.clearAllMocks();
    });

    afterEach(() => {
        cleanup();
    });

    describe("1. Zero visual footprint when no public letters exist", () => {
        it("returns null when counts is undefined", () => {
            const { container } = render(<PublicTestimonySection counts={undefined} />);
            expect(container.firstChild).toBeNull();
            expect(screen.queryByTestId("public-testimony-section")).not.toBeInTheDocument();
        });

        it("returns null when counts is null", () => {
            const { container } = render(<PublicTestimonySection counts={null} />);
            expect(container.firstChild).toBeNull();
            expect(screen.queryByTestId("public-testimony-section")).not.toBeInTheDocument();
        });

        it("returns null when counts.total === 0", () => {
            const emptyCounts: sway.IPublicTestimonyCounts = {
                total: 0,
                support: 0,
                oppose: 0,
                neutral: 0,
            };
            const { container } = render(<PublicTestimonySection counts={emptyCounts} />);
            expect(container.firstChild).toBeNull();
            expect(screen.queryByTestId("public-testimony-section")).not.toBeInTheDocument();
        });
    });

    describe("2. Renders section heading, letter counts, and stance pills when counts.total > 0", () => {
        it("renders the Public Testimony card with heading, subtitle, stance pills, and browse button", () => {
            render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            expect(screen.getByTestId("public-testimony-section")).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.publicTestimony.section.heading)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.publicTestimony.section.subtitle(25))).toBeInTheDocument();

            const supportPill = screen.getByTestId("pill-support");
            expect(supportPill).toHaveTextContent(`15 ${PARITY_COPY.publicTestimony.section.supportPill}`);

            const opposePill = screen.getByTestId("pill-oppose");
            expect(opposePill).toHaveTextContent(`7 ${PARITY_COPY.publicTestimony.section.opposePill}`);

            const neutralPill = screen.getByTestId("pill-neutral");
            expect(neutralPill).toHaveTextContent(`3 ${PARITY_COPY.publicTestimony.section.neutralPill}`);

            const browseButton = screen.getByTestId("btn-browse-public-testimony");
            expect(browseButton).toHaveTextContent(PARITY_COPY.publicTestimony.section.browseButton);

            expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
        });

        it("uses semantic theme tokens for stance pills without raw palette or dark: classes", () => {
            const { container } = render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            const supportPill = screen.getByTestId("pill-support");
            expect(supportPill.className).toContain("text-success");
            expect(supportPill.className).toContain("bg-success/12");
            expect(supportPill.className).toContain("border-success");

            const opposePill = screen.getByTestId("pill-oppose");
            expect(opposePill.className).toContain("text-destructive");
            expect(opposePill.className).toContain("bg-destructive/12");
            expect(opposePill.className).toContain("border-destructive");

            const neutralPill = screen.getByTestId("pill-neutral");
            expect(neutralPill.className).toContain("text-foreground");
            expect(neutralPill.className).toContain("bg-surface-2");
            expect(neutralPill.className).toContain("border-border-strong");

            const html = container.innerHTML;
            expect(html).not.toMatch(/\bdark:/);
            expect(html).not.toMatch(/\b(emerald|rose|slate|amber|green|red)-\d+/);
        });
    });

    describe("3. Clicking the Browse button opens BrowseTestimonyModal", () => {
        it("opens the modal with the 'all' filter tab active", () => {
            render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            expect(screen.queryByRole("dialog")).not.toBeInTheDocument();

            fireEvent.click(screen.getByTestId("btn-browse-public-testimony"));

            const dialog = screen.getByRole("dialog");
            expect(dialog).toBeInTheDocument();
            expect(screen.getByRole("heading", { name: PARITY_COPY.publicTestimony.modal.title })).toBeInTheDocument();
            expect(screen.getByText("Ordinance on Street Trees")).toBeInTheDocument();

            const allTab = screen.getByTestId("tab-all");
            expect(allTab).toHaveAttribute("data-state", "active");
        });
    });

    describe("4. Clicking a stance pill opens BrowseTestimonyModal with that filter active", () => {
        it("opens the modal with the support tab active when clicking support pill", () => {
            render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            fireEvent.click(screen.getByTestId("pill-support"));

            expect(screen.getByRole("dialog")).toBeInTheDocument();
            const supportTab = screen.getByTestId("tab-support");
            expect(supportTab).toHaveAttribute("data-state", "active");
        });

        it("opens the modal with the oppose tab active when clicking oppose pill", () => {
            render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            fireEvent.click(screen.getByTestId("pill-oppose"));

            expect(screen.getByRole("dialog")).toBeInTheDocument();
            const opposeTab = screen.getByTestId("tab-oppose");
            expect(opposeTab).toHaveAttribute("data-state", "active");
        });

        it("opens the modal with the neutral tab active when clicking neutral pill", () => {
            render(
                <PublicTestimonySection
                    counts={SAMPLE_COUNTS}
                    letters={SAMPLE_LETTERS}
                    billTitle="Ordinance on Street Trees"
                />,
            );

            fireEvent.click(screen.getByTestId("pill-neutral"));

            expect(screen.getByRole("dialog")).toBeInTheDocument();
            const neutralTab = screen.getByTestId("tab-neutral");
            expect(neutralTab).toHaveAttribute("data-state", "active");
        });
    });
});
