import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillAsIntroduced } from "../../src/components/BillAsIntroduced";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const wrap = (title: string) =>
    render(
        <ThemeProvider initialMode="light">
            <BillAsIntroduced title={title} />
        </ThemeProvider>,
    );

const DASH_TITLE = "Clean Energy Act - modernizing the grid";
const SHORT_CLAUSE_TITLE = "Parks – Funding FOR the purpose of funding parks";
const LONG_CLAUSE_TITLE = `Parks – Funding FOR the purpose of ${"funding the maintenance of public parks, ".repeat(12)}and for related purposes`;

describe("BillAsIntroduced", () => {
    test("renders nothing when the stored title is only the headline", () => {
        wrap("Parks Funding");
        expect(screen.queryByTestId("bill-as-introduced")).toBeNull();
    });

    test("renders nothing for a title of only whitespace around the headline", () => {
        wrap("  Parks Funding \n");
        expect(screen.queryByTestId("bill-as-introduced")).toBeNull();
    });

    test("prints the deck of a dashed title that has no enacting clause", () => {
        wrap(DASH_TITLE);
        expect(screen.getByTestId("bill-as-introduced")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.bill.asIntroduced)).toBeTruthy();
        expect(screen.getByText(DASH_TITLE)).toBeTruthy();
    });

    test("prints the full title under the As introduced label", () => {
        wrap(SHORT_CLAUSE_TITLE);
        expect(screen.getByText(PARITY_COPY.bill.asIntroduced)).toBeTruthy();
        expect(screen.getByText(SHORT_CLAUSE_TITLE)).toBeTruthy();
    });

    test("shows the title in the foreground colour and lets the reader select it", () => {
        wrap(SHORT_CLAUSE_TITLE);
        const text = screen.getByText(SHORT_CLAUSE_TITLE);
        expect(text.props.selectable).toBe(true);
        expect(text.props.className).toContain("text-foreground-light");
        expect(text.props.className).toContain("dark:text-foreground-dark");
        expect(text.props.className).not.toContain("text-muted-foreground");
    });

    test("leaves a short title unclamped and offers no toggle", () => {
        wrap(SHORT_CLAUSE_TITLE);
        expect(screen.getByText(SHORT_CLAUSE_TITLE).props.numberOfLines).toBeUndefined();
        expect(screen.queryByText(PARITY_COPY.bill.showMore)).toBeNull();
    });

    test("folds a long title to four lines behind a Show more button", () => {
        wrap(LONG_CLAUSE_TITLE);
        expect(screen.getByText(LONG_CLAUSE_TITLE).props.numberOfLines).toBe(4);
        expect(screen.getByRole("button", { name: PARITY_COPY.bill.showMore }).props.accessibilityState).toEqual(
            expect.objectContaining({ expanded: false }),
        );
    });

    test("Show more opens the whole title and Show less folds it again", () => {
        wrap(LONG_CLAUSE_TITLE);

        fireEvent.press(screen.getByText(PARITY_COPY.bill.showMore));
        expect(screen.getByText(LONG_CLAUSE_TITLE).props.numberOfLines).toBeUndefined();
        expect(screen.getByRole("button", { name: PARITY_COPY.bill.showLess }).props.accessibilityState).toEqual(
            expect.objectContaining({ expanded: true }),
        );

        fireEvent.press(screen.getByText(PARITY_COPY.bill.showLess));
        expect(screen.getByText(LONG_CLAUSE_TITLE).props.numberOfLines).toBe(4);
    });
});
