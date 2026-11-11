import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { CategoryChipStrip } from "../../src/components/CategoryChipStrip";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const CATS = ["Immigration", "Police", "Health"];

const wrap = (selected: string[], onToggle = jest.fn(), onClear?: () => void) =>
    render(
        <ThemeProvider initialMode="light">
            <CategoryChipStrip categories={CATS} selected={selected} onToggle={onToggle} onClear={onClear} />
        </ThemeProvider>,
    );

const openSheet = () => fireEvent.press(screen.getByTestId("category-chip-strip"));

describe("CategoryChipStrip", () => {
    test("Test 1: renders a single trigger and no option rows until it is pressed", () => {
        wrap([]);
        expect(screen.getByTestId("category-chip-strip")).toBeTruthy();
        expect(screen.queryByTestId("chip-Immigration")).toBeNull();
        expect(screen.queryByTestId("chip-Police")).toBeNull();
        expect(screen.queryByTestId("chip-Health")).toBeNull();
    });

    test("Test 2: the trigger shows a count badge only when something is selected", () => {
        const { rerender } = wrap([]);
        expect(screen.queryByTestId("category-filter-count")).toBeNull();
        rerender(
            <ThemeProvider initialMode="light">
                <CategoryChipStrip categories={CATS} selected={["Immigration", "Police"]} onToggle={jest.fn()} />
            </ThemeProvider>,
        );
        expect(screen.getByTestId("category-filter-count")).toBeTruthy();
        expect(screen.getByText("2")).toBeTruthy();
    });

    test("Test 3: the trigger is a button whose label carries the selected count", () => {
        wrap(["Police"]);
        const trigger = screen.getByTestId("category-chip-strip");
        expect(trigger.props.accessibilityRole).toBe("button");
        expect(trigger.props.accessibilityLabel).toContain(PARITY_COPY.bills.categoriesLabel);
        expect(trigger.props.accessibilityLabel).toContain("1 selected");
    });

    test("Test 4: pressing the trigger lists one row per category", () => {
        wrap([]);
        openSheet();
        expect(screen.getByTestId("chip-Immigration")).toBeTruthy();
        expect(screen.getByTestId("chip-Police")).toBeTruthy();
        expect(screen.getByTestId("chip-Health")).toBeTruthy();
    });

    test("Test 5: pressing a row calls onToggle with that category name", () => {
        const onToggle = jest.fn();
        wrap([], onToggle);
        openSheet();
        fireEvent.press(screen.getByTestId("chip-Health"));
        expect(onToggle).toHaveBeenCalledWith("Health");
    });

    test("Test 6: each row has accessibilityRole=checkbox and accessibilityState.checked matches selected status", () => {
        wrap(["Police"]);
        openSheet();
        const policeRow = screen.getByTestId("chip-Police");
        const immigrationRow = screen.getByTestId("chip-Immigration");
        expect(policeRow.props.accessibilityRole).toBe("checkbox");
        expect(policeRow.props.accessibilityState).toEqual(expect.objectContaining({ checked: true }));
        expect(immigrationRow.props.accessibilityState).toEqual(expect.objectContaining({ checked: false }));
    });

    test("Test 7: each row has accessibilityLabel containing Add/Remove and the category name", () => {
        wrap(["Police"]);
        openSheet();
        expect(screen.getByTestId("chip-Police").props.accessibilityLabel).toContain("Remove");
        expect(screen.getByTestId("chip-Police").props.accessibilityLabel).toContain("Police");
        expect(screen.getByTestId("chip-Immigration").props.accessibilityLabel).toContain("Add");
        expect(screen.getByTestId("chip-Immigration").props.accessibilityLabel).toContain("Immigration");
    });

    test("Test 8: the search box narrows the rows and reports when nothing matches", () => {
        wrap([]);
        openSheet();
        fireEvent.changeText(screen.getByTestId("category-filter-search"), "POL");
        expect(screen.getByTestId("chip-Police")).toBeTruthy();
        expect(screen.queryByTestId("chip-Immigration")).toBeNull();
        fireEvent.changeText(screen.getByTestId("category-filter-search"), "nothing here");
        expect(screen.getByTestId("category-filter-empty")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.bills.noCategoriesFound)).toBeTruthy();
    });

    test("Test 9: Clear all shows only with a selection and calls onClear", () => {
        const onClear = jest.fn();
        const { rerender } = wrap([], jest.fn(), onClear);
        openSheet();
        expect(screen.queryByTestId("category-filter-clear")).toBeNull();

        rerender(
            <ThemeProvider initialMode="light">
                <CategoryChipStrip categories={CATS} selected={["Police"]} onToggle={jest.fn()} onClear={onClear} />
            </ThemeProvider>,
        );
        fireEvent.press(screen.getByTestId("category-filter-clear"));
        expect(onClear).toHaveBeenCalledTimes(1);
    });

    test("Test 10: without onClear, Clear all toggles every selected category off", () => {
        const onToggle = jest.fn();
        wrap(["Police", "Health"], onToggle);
        openSheet();
        fireEvent.press(screen.getByTestId("category-filter-clear"));
        expect(onToggle).toHaveBeenCalledWith("Police");
        expect(onToggle).toHaveBeenCalledWith("Health");
    });

    test("Test 11: Done closes the sheet", () => {
        wrap([]);
        openSheet();
        expect(screen.getByTestId("chip-Police")).toBeTruthy();
        fireEvent.press(screen.getByTestId("category-filter-done"));
        expect(screen.queryByTestId("chip-Police")).toBeNull();
    });
});
