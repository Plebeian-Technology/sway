import React from "react";
import { Text } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import BillSectionTabs from "../../src/components/BillSectionTabs";

const renderTabs = () =>
    render(
        <BillSectionTabs
            bill={<Text>Bill content</Text>}
            votes={<Text>Votes content</Text>}
            summaries={<Text>Summaries content</Text>}
        />,
    );

describe("BillSectionTabs", () => {
    test("renders the Bill, Votes and Summaries tab labels", () => {
        renderTabs();
        expect(screen.getByRole("tab", { name: "Bill" })).toBeTruthy();
        expect(screen.getByRole("tab", { name: "Votes" })).toBeTruthy();
        expect(screen.getByRole("tab", { name: "Summaries" })).toBeTruthy();
    });

    test("shows only the Bill content by default", () => {
        renderTabs();
        expect(screen.getByText("Bill content")).toBeTruthy();
        expect(screen.queryByText("Votes content")).toBeNull();
        expect(screen.queryByText("Summaries content")).toBeNull();
    });

    test("pressing the Votes tab shows only the Votes content and selects that tab", () => {
        renderTabs();
        fireEvent.press(screen.getByTestId("tab-votes"));

        expect(screen.getByText("Votes content")).toBeTruthy();
        expect(screen.queryByText("Bill content")).toBeNull();
        expect(screen.queryByText("Summaries content")).toBeNull();
        expect(screen.getByTestId("tab-votes").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true }),
        );
        expect(screen.getByTestId("tab-bill").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: false }),
        );
    });
});
