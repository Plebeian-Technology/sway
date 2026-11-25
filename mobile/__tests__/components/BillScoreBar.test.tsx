// @lat: [[mobile-bill-surface-components-design#BillScoreBar]]
import React from "react";
import { render, screen } from "@testing-library/react-native";

import { BillScoreBar } from "../../src/components/BillScoreBar";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("BillScoreBar", () => {
    const SPLIT = { for_percent: 70, against_percent: 30, comparison_suppressed: false };

    test("shows the percentages of a bill with votes", () => {
        wrap(<BillScoreBar bill_score={SPLIT} />);

        expect(screen.getByText(PARITY_COPY.bill.content.howOthersVoted)).toBeTruthy();
        expect(screen.getByText("For: 70%")).toBeTruthy();
        expect(screen.getByText("Against: 30%")).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.bill.noVotesYet)).toBeNull();
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    test("prints only the two percentages, with no total", () => {
        wrap(<BillScoreBar bill_score={SPLIT} />);

        const bar = screen.getByTestId("bill-score-bar");
        expect(bar).toHaveTextContent("How others votedFor: 70%Against: 30%");
        expect(bar.props.accessibilityLabel).not.toMatch(/total/);
    });

    test("reads as one sentence to a screen reader, on an element iOS will not skip", () => {
        wrap(<BillScoreBar bill_score={SPLIT} />);

        const bar = screen.getByTestId("bill-score-bar");
        expect(bar.props.accessible).toBe(true);
        expect(bar.props.accessibilityLabel).toBe("How others voted: 70 percent for, 30 percent against");
    });

    test("with no percentages it says so and keeps the track visible instead of showing zeros", () => {
        wrap(<BillScoreBar bill_score={{ for_percent: 0, against_percent: 0, comparison_suppressed: false }} />);

        expect(screen.getByText(PARITY_COPY.bill.noVotesYet)).toBeTruthy();
        expect(screen.getByTestId("bill-score-bar-track")).toBeTruthy();
        expect(screen.queryByText(/For: 0/)).toBeNull();
        expect(screen.queryByText(/Against: 0/)).toBeNull();
        expect(screen.getByTestId("bill-score-bar").props.accessibilityLabel).toBe(
            `${PARITY_COPY.bill.content.howOthersVoted}: ${PARITY_COPY.bill.noVotesYet}`,
        );
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    test("draws nothing for a suppressed score, a score with no flag, or no score", () => {
        for (const score of [
            { ...SPLIT, comparison_suppressed: true },
            { for_percent: 70, against_percent: 30 },
            null,
        ]) {
            const { unmount } = wrap(<BillScoreBar bill_score={score} />);
            expect(screen.queryByTestId("bill-score-bar")).toBeNull();
            expect(screen.queryByText(/For:/)).toBeNull();
            unmount();
        }
    });

    test("keeps an empty track that stands apart from the card in dark mode and is unchanged in light mode", () => {
        wrap(<BillScoreBar bill_score={{ for_percent: 0, against_percent: 0, comparison_suppressed: false }} />);

        const className = String(screen.getByTestId("bill-score-bar-track").props.className);
        expect(className).toContain("bg-muted-light");
        expect(className).toContain("dark:bg-border-dark");
        expect(className).not.toContain("dark:bg-muted-dark");
    });

    test("carries no top margin of its own, so the parent's gap alone spaces it", () => {
        wrap(<BillScoreBar bill_score={{ for_percent: 50, against_percent: 50, comparison_suppressed: false }} />);
        expect(String(screen.getByTestId("bill-score-bar").props.className ?? "")).not.toMatch(/\bmt-/);
    });
});
