import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillsSortStrip } from "../../src/components/BillsSortStrip";
import { DEFAULT_BILLS_SORT, type BillsSortValue } from "../../src/utils/billsList";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const wrap = (value: BillsSortValue = DEFAULT_BILLS_SORT, onChange = jest.fn()) =>
    render(
        <ThemeProvider initialMode="light">
            <BillsSortStrip value={value} onChange={onChange} />
        </ThemeProvider>,
    );

describe("BillsSortStrip", () => {
    test("renders one chip per PARITY_COPY.bills.sortOptions entry with its label", () => {
        wrap();
        PARITY_COPY.bills.sortOptions.forEach((option) => {
            expect(screen.getByTestId(`sort-${option.value}`)).toBeTruthy();
            expect(screen.getByText(option.label)).toBeTruthy();
        });
    });

    test("the active option has default variant (bg-accent), others outline (bg-surface-3)", () => {
        wrap("title:asc");
        expect(screen.getByTestId("sort-title:asc").props.className).toContain("bg-accent-light");
        expect(screen.getByTestId(`sort-${DEFAULT_BILLS_SORT}`).props.className).toContain("bg-surface-3-light");
    });

    test("pressing a chip calls onChange with that sort value", () => {
        const onChange = jest.fn();
        wrap(DEFAULT_BILLS_SORT, onChange);
        fireEvent.press(screen.getByTestId("sort-title:desc"));
        expect(onChange).toHaveBeenCalledWith("title:desc");
    });

    test("chips are radio-role with checked state matching the active value", () => {
        wrap("introduced_date_time_utc:asc");
        const active = screen.getByTestId("sort-introduced_date_time_utc:asc");
        const inactive = screen.getByTestId("sort-title:asc");
        expect(active.props.accessibilityRole).toBe("radio");
        expect(active.props.accessibilityState).toEqual(expect.objectContaining({ checked: true }));
        expect(inactive.props.accessibilityState).toEqual(expect.objectContaining({ checked: false }));
    });

    test("chip labels use theme-aware text classes instead of hardcoded black", () => {
        wrap("title:asc");
        const activeLabel = screen.getByText("Title A–Z");
        const inactiveLabel = screen.getByText("Newest first");
        expect(activeLabel.props.className).toContain("text-primary-foreground-light");
        expect(inactiveLabel.props.className).toContain("text-foreground-light");
        expect(inactiveLabel.props.className).toContain("dark:text-foreground-dark");
    });
});
