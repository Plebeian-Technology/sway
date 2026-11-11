// @lat: [[mobile-bill-surface-components-design#BillScoreBar]]
import React from "react";
import { render, screen } from "@testing-library/react-native";

import { BillScoreBar } from "../../src/components/BillScoreBar";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("BillScoreBar", () => {
    test("shows the counts and percentages of a bill with votes", () => {
        wrap(<BillScoreBar bill_score={{ for: 42, against: 18 }} />);

        expect(screen.getByText(PARITY_COPY.bill.content.howOthersVoted)).toBeTruthy();
        expect(screen.getByText("For: 42 (70%)")).toBeTruthy();
        expect(screen.getByText("Against: 18 (30%)")).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.bill.noVotesYet)).toBeNull();
    });

    test("groups thousands in the counts", () => {
        wrap(<BillScoreBar bill_score={{ for: 1234, against: 1 }} />);
        expect(screen.getByText(/For: 1,234/)).toBeTruthy();
    });

    test("reads as one sentence to a screen reader, on an element iOS will not skip", () => {
        wrap(<BillScoreBar bill_score={{ for: 42, against: 18 }} />);

        const bar = screen.getByTestId("bill-score-bar");
        expect(bar.props.accessible).toBe(true);
        expect(bar.props.accessibilityLabel).toBe(
            "How others voted: 70 percent for, 30 percent against, 60 total votes",
        );
    });

    test("with no votes it says so and keeps the track visible instead of showing zeros", () => {
        wrap(<BillScoreBar bill_score={{ for: 0, against: 0 }} />);

        expect(screen.getByText(PARITY_COPY.bill.noVotesYet)).toBeTruthy();
        expect(screen.getByTestId("bill-score-bar-track")).toBeTruthy();
        expect(screen.queryByText(/For: 0/)).toBeNull();
        expect(screen.queryByText(/Against: 0/)).toBeNull();
        expect(screen.getByTestId("bill-score-bar").props.accessibilityLabel).toBe(
            `${PARITY_COPY.bill.content.howOthersVoted}: ${PARITY_COPY.bill.noVotesYet}`,
        );
    });

    test("a bill with no score row yet counts as no votes", () => {
        wrap(<BillScoreBar bill_score={null} />);
        expect(screen.getByText(PARITY_COPY.bill.noVotesYet)).toBeTruthy();
        expect(screen.getByTestId("bill-score-bar-track")).toBeTruthy();
    });

    test("keeps an empty track that stands apart from the card in dark mode and is unchanged in light mode", () => {
        wrap(<BillScoreBar bill_score={{ for: 0, against: 0 }} />);

        const className = String(screen.getByTestId("bill-score-bar-track").props.className);
        expect(className).toContain("bg-muted-light");
        expect(className).toContain("dark:bg-border-dark");
        expect(className).not.toContain("dark:bg-muted-dark");
    });

    test("carries no top margin of its own, so the parent's gap alone spaces it", () => {
        wrap(<BillScoreBar bill_score={{ for: 1, against: 1 }} />);
        expect(String(screen.getByTestId("bill-score-bar").props.className ?? "")).not.toMatch(/\bmt-/);
    });
});
