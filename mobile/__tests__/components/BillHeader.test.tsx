import React from "react";
import { StyleSheet } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { ThemeProvider, type ThemeMode } from "../../src/theme/ThemeProvider";
import { BillHeader } from "../../src/components/BillHeader";
import { swayTokens } from "../../src/theme/tokens";

const wrap = (ui: React.ReactElement, mode: ThemeMode = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("BillHeader", () => {
    test("renders only bill headline, stripping enacting clauses and decks", () => {
        const bill = {
            id: 1,
            external_id: "HB 100",
            title: "Historic Preservation – Conservation Districts – Establishment\n\nFOR the purpose of establishing Conservation Districts",
        };
        wrap(<BillHeader bill={bill} />);

        const headerTitle = screen.getByTestId("bill-header-title");
        expect(headerTitle.props.children).toBe("Historic Preservation");
        expect(screen.queryByText(/establishing Conservation Districts/)).toBeNull();
    });

    test("prefers explicit headline if present on bill object", () => {
        const bill = {
            id: 2,
            external_id: "SB 200",
            title: "Full Raw Title Here",
            headline: "Clean Headline",
        };
        wrap(<BillHeader bill={bill} />);

        const headerTitle = screen.getByTestId("bill-header-title");
        expect(headerTitle.props.children).toBe("Clean Headline");
    });

    test("renders bill number and sponsor when provided", () => {
        const bill = {
            id: 3,
            external_id: "HB 123",
            title: "Clean Water Act",
        };
        wrap(<BillHeader bill={bill} sponsor={{ full_name: "Jane Doe" }} formattedSwayLocaleName="Baltimore" />);

        expect(screen.getByText("HB 123")).toBeTruthy();
        expect(screen.getByText("Sponsored by Jane Doe · Baltimore")).toBeTruthy();
    });

    describe("accessibility", () => {
        test("marks only the title as a header", () => {
            wrap(<BillHeader bill={{ id: 4, external_id: "HB 4", title: "Clean Water Act" }} />);
            expect(screen.getAllByRole("header")).toHaveLength(1);
            expect(screen.getByRole("header").props.testID).toBe("bill-header-title");
            expect(screen.getByTestId("bill-header").props.accessibilityRole).toBeUndefined();
        });

        test("reads the whole sponsor line, locale included", () => {
            wrap(
                <BillHeader
                    bill={{ id: 5, external_id: "HB 5", title: "Clean Water Act" }}
                    sponsor={{ full_name: "Jane Doe" }}
                    formattedSwayLocaleName="Baltimore"
                />,
            );
            expect(screen.getByLabelText("Sponsored by Jane Doe, Baltimore")).toBeTruthy();
        });

        test("reads the chamber with the bill number", () => {
            wrap(<BillHeader bill={{ id: 6, external_id: "HB 6", chamber: "House", title: "Clean Water Act" }} />);
            expect(screen.getByLabelText("Bill number HB 6, House")).toBeTruthy();
        });
    });

    describe("sponsor link", () => {
        const bill = { id: 7, external_id: "HB 7", title: "Clean Water Act" };

        test("renders plain text when no handler is given", () => {
            wrap(<BillHeader bill={bill} sponsor={{ full_name: "Jane Doe" }} />);
            expect(screen.queryByRole("link")).toBeNull();
        });

        test("renders a 44pt link that keeps the whole line as one string when a handler is given", () => {
            const onSponsorPress = jest.fn();
            wrap(
                <BillHeader
                    bill={bill}
                    sponsor={{ full_name: "Jane Doe" }}
                    formattedSwayLocaleName="Baltimore"
                    onSponsorPress={onSponsorPress}
                />,
            );

            const link = screen.getByRole("link");
            expect(link.props.accessibilityLabel).toBe("Sponsored by Jane Doe, Baltimore");
            expect(StyleSheet.flatten(link.props.style).minHeight).toBeGreaterThanOrEqual(44);
            expect(screen.getByText("Sponsored by Jane Doe · Baltimore")).toBeTruthy();

            fireEvent.press(link);
            expect(onSponsorPress).toHaveBeenCalledTimes(1);
        });

        test("shows no link when there is no sponsor", () => {
            wrap(<BillHeader bill={bill} sponsor={null} onSponsorPress={jest.fn()} />);
            expect(screen.queryByRole("link")).toBeNull();
        });
    });

    describe("category chips", () => {
        test("capitalise the category name", () => {
            wrap(<BillHeader bill={{ id: 8, title: "Clean Water Act", categories: ["transparency", "Housing"] }} />);
            expect(screen.getByText("Transparency")).toBeTruthy();
            expect(screen.getByText("Housing")).toBeTruthy();
        });

        test("look like labels, not like tappable filter chips", () => {
            wrap(<BillHeader bill={{ id: 9, title: "Clean Water Act", categories: ["Housing"] }} />);
            const chip = screen.getByText("Housing");
            expect(chip.props.className).toContain("text-muted-foreground-light");
            expect(chip.props.className).not.toContain("text-accent");
            expect(screen.getByTestId("bill-header-category-Housing").props.className).toContain("bg-surface-2-light");
        });
    });

    describe("status badge", () => {
        const bill = { id: 10, title: "Clean Water Act", status: "passed" };

        test("uses the light palette in light mode", () => {
            wrap(<BillHeader bill={bill} />, "light");
            expect(StyleSheet.flatten(screen.getByTestId("bill-header-status").props.style).backgroundColor).toBe(
                swayTokens.light.success,
            );
        });

        test("uses the dark palette in dark mode", () => {
            wrap(<BillHeader bill={bill} />, "dark");
            expect(StyleSheet.flatten(screen.getByTestId("bill-header-status").props.style).backgroundColor).toBe(
                swayTokens.dark.success,
            );
        });
    });

    describe("vote status sentence", () => {
        test("renders under the header by default", () => {
            wrap(<BillHeader bill={{ id: 11, title: "Clean Water Act" }} />);
            expect(screen.getByTestId("bill-header-vote-status")).toBeTruthy();
        });

        test("is left out when showVoteStatus is false", () => {
            wrap(
                <BillHeader
                    bill={{
                        id: 12,
                        title: "Clean Water Act",
                        active: false,
                        vote_date_time_utc: "2026-03-03T12:00:00Z",
                    }}
                    showVoteStatus={false}
                />,
            );
            expect(screen.queryByTestId("bill-header-vote-status")).toBeNull();
            expect(screen.queryByTestId("bill-header-no-longer-in-office")).toBeNull();
        });
    });
});
