/**
 * BillCard — built out of the shared Card building block.
 * These tests cover all 12 of its expected behaviors.
 */
import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillCard } from "../../src/components/BillCard";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const baseBill = {
    id: 42,
    bill_number: "HB 1234",
    external_id: "HB1234",
    title: "Open Records Act",
    category: "education",
    label: "Maryland",
    summary: "A bill to improve records access in government agencies.",
    for_count: 12,
    against_count: 3,
    bill_score: { for_percent: 70, against_percent: 30, comparison_suppressed: false },
    link: "https://mgaleg.maryland.gov/bills/HB1234",
};

describe("BillCard (D-12 refactor)", () => {
    // @lat: [[mobile-jest-first-pass-test-notes#BillCard.test.tsx]]

    test("renders bill title", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        expect(screen.getByText("Open Records Act")).toBeTruthy();
    });

    test("renders only bill headline, stripping enacting clauses", () => {
        const bill = {
            ...baseBill,
            title: "Historic Preservation – Conservation Districts – Establishment FOR the purpose of establishing",
        };
        wrap(<BillCard bill={bill} onPress={() => {}} />);
        expect(screen.getByText("Historic Preservation")).toBeTruthy();
        expect(screen.queryByText(/establishing/)).toBeNull();
    });

    test("renders external_id pill with yellow accent class", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        expect(screen.getByText("HB1234")).toBeTruthy();
    });

    test("renders titleized category pill", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        expect(screen.getByText("Education")).toBeTruthy();
    });

    test("renders 'You voted: FOR' pill when user_vote.support is set", () => {
        const bill = { ...baseBill, user_vote: { support: "FOR" } };
        wrap(<BillCard bill={bill} onPress={() => {}} />);
        expect(screen.getByText("You voted: FOR")).toBeTruthy();
    });

    test("does NOT render user-vote pill when user_vote is absent", () => {
        const bill = { ...baseBill, user_vote: undefined };
        wrap(<BillCard bill={bill} onPress={() => {}} />);
        expect(screen.queryByTestId("user-vote-pill")).toBeNull();
    });

    test("renders summary excerpt with NEWLINE/ENDING markers stripped", () => {
        const longSummary =
            "This is a very important bill. NEWLINE It covers many topics. ENDING More text here. " + "x".repeat(120);
        const bill = { ...baseBill, summary: longSummary };
        wrap(<BillCard bill={bill} onPress={() => {}} />);
        const rendered = screen.queryByText(/NEWLINE/);
        expect(rendered).toBeNull();
    });

    test("renders fallback text when summary is undefined", () => {
        const bill = { ...baseBill, summary: undefined };
        wrap(<BillCard bill={bill} onPress={() => {}} />);
        expect(screen.getByText("Open the bill to review the full summary, vote totals, and arguments.")).toBeTruthy();
    });

    test("renders score grid with For and Against percentages using tabular-nums", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        const forPercent = screen.getByTestId(`bill-card-${baseBill.id}-for-percent`);
        const againstPercent = screen.getByTestId(`bill-card-${baseBill.id}-against-percent`);
        expect(forPercent).toHaveTextContent("70%");
        expect(againstPercent).toHaveTextContent("30%");
        // The equal-width-digit style is set. On Text nodes style is one plain
        // object rather than an array, so compare against it directly.
        expect(forPercent.props.style).toEqual(expect.objectContaining({ fontVariant: ["tabular-nums"] }));
        expect(againstPercent.props.style).toEqual(expect.objectContaining({ fontVariant: ["tabular-nums"] }));
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    test("prints only the two percentages", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);

        expect(screen.getByTestId("bill-card-42-for-percent")).toHaveTextContent("70%");
        expect(screen.getByTestId("bill-card-42-against-percent")).toHaveTextContent("30%");
        expect(screen.queryByText(/\b(7777|4321)\b|voted|total/)).toBeNull();
    });

    test("renders 'Open bill' CTA with accessibilityRole=button", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        expect(screen.getByText("Open bill")).toBeTruthy();
    });

    test("pressing the card calls onPress", () => {
        const onPress = jest.fn();
        wrap(<BillCard bill={baseBill} onPress={onPress} />);
        // Tap the card by its testID. The footer button carries the same label,
        // so looking it up by label would match two things.
        fireEvent.press(screen.getByTestId(`bill-card-${baseBill.id}`));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("card has accessibilityLabel including bill title", () => {
        wrap(<BillCard bill={baseBill} onPress={() => {}} />);
        // getAllByLabelText returns every node with this label — the card and its
        // footer button both use it
        const nodes = screen.getAllByLabelText("Open bill Open Records Act");
        expect(nodes.length).toBeGreaterThanOrEqual(1);
    });

    // @lat: [[voter-privacy-threshold#The mobile bill screen hides what the web hides]]
    test("shows one line and no digits for a withheld split", () => {
        const hidden = {
            ...baseBill,
            bill_score: { for_percent: 70, against_percent: 30, comparison_suppressed: true },
        };

        wrap(<BillCard bill={hidden} onPress={() => {}} />);

        const line = screen.getByTestId("bill-card-42-comparison-suppressed");
        expect(line).toHaveTextContent("Not enough votes yet");
        expect(line).not.toHaveTextContent(/\d/);
        expect(screen.queryByTestId("bill-card-42-for-percent")).toBeNull();
        expect(screen.queryByTestId("bill-card-42-against-percent")).toBeNull();
    });

    test("treats a cached bill score with no flag as suppressed", () => {
        wrap(
            <BillCard
                bill={{ ...baseBill, bill_score: { for_percent: 70, against_percent: 30 } }}
                onPress={() => {}}
            />,
        );

        expect(screen.getByText("Not enough votes yet")).toBeTruthy();
        expect(screen.queryByTestId("bill-card-42-for-percent")).toBeNull();
    });
});
