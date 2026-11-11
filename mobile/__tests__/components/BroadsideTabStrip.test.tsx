// @lat: [[mobile-jest-first-pass-test-notes#BroadsideTabStrip.test.tsx]]

import React from "react";
import { render, fireEvent } from "@testing-library/react-native";
import { BroadsideTabStrip } from "../../src/components/BroadsideTabStrip";

const TABS = [
    { key: "positions", label: "Positions" },
    { key: "changes", label: "Pending Changes" },
    { key: "members", label: "Members" },
];

describe("BroadsideTabStrip", () => {
    test("renders all tab items with the correct labels", () => {
        const { getByText } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />);
        expect(getByText("Positions")).toBeTruthy();
        expect(getByText("Pending Changes")).toBeTruthy();
        expect(getByText("Members")).toBeTruthy();
    });

    test("each tab has accessibilityRole='tab' (Pitfall 6)", () => {
        const { getAllByRole } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />);
        const tabs = getAllByRole("tab");
        expect(tabs).toHaveLength(3);
    });

    test("active tab has accessibilityState.selected=true", () => {
        const { getByRole } = render(<BroadsideTabStrip tabs={TABS} activeKey="changes" onChange={jest.fn()} />);
        const changeTab = getByRole("tab", { name: "Pending Changes" });
        expect(changeTab.props.accessibilityState).toEqual(expect.objectContaining({ selected: true }));
    });

    test("inactive tabs have accessibilityState.selected=false", () => {
        const { getByRole } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />);
        const changesTab = getByRole("tab", { name: "Pending Changes" });
        const membersTab = getByRole("tab", { name: "Members" });
        expect(changesTab.props.accessibilityState).toEqual(expect.objectContaining({ selected: false }));
        expect(membersTab.props.accessibilityState).toEqual(expect.objectContaining({ selected: false }));
    });

    test("pressing a tab calls onChange with the tab key", () => {
        const onChange = jest.fn();
        const { getByRole } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={onChange} />);
        fireEvent.press(getByRole("tab", { name: "Members" }));
        expect(onChange).toHaveBeenCalledWith("members");
    });

    test("testID prop is applied to the container", () => {
        const { getByTestId } = render(
            <BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} testID="my-tab-strip" />,
        );
        expect(getByTestId("my-tab-strip")).toBeTruthy();
    });

    test("each tab item has testID=tab-{key}", () => {
        const { getByTestId } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />);
        expect(getByTestId("tab-positions")).toBeTruthy();
        expect(getByTestId("tab-changes")).toBeTruthy();
        expect(getByTestId("tab-members")).toBeTruthy();
    });

    test("the strip is a tablist, so screen readers announce the tabs as a group", () => {
        const { getByTestId, getAllByRole } = render(
            <BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />,
        );
        const strip = getByTestId("broadside-tab-strip");
        expect(strip.props.accessibilityRole).toBe("tablist");
        expect(strip.props.accessible).toBeUndefined();
        expect(getAllByRole("tab")).toHaveLength(3);
    });

    test("tab labels cap text scaling and shrink to one line instead of breaking mid-word", () => {
        const { getByText } = render(<BroadsideTabStrip tabs={TABS} activeKey="positions" onChange={jest.fn()} />);
        for (const label of ["Positions", "Pending Changes", "Members"]) {
            const props = getByText(label).props;
            expect(props.maxFontSizeMultiplier).toBe(1.3);
            expect(props.numberOfLines).toBe(1);
            expect(props.adjustsFontSizeToFit).toBe(true);
            expect(props.allowFontScaling).not.toBe(false);
        }
    });

    test("renders only two tabs when given 2-tab config", () => {
        const TWO_TABS = TABS.slice(0, 2);
        const { getAllByRole } = render(
            <BroadsideTabStrip tabs={TWO_TABS} activeKey="positions" onChange={jest.fn()} />,
        );
        expect(getAllByRole("tab")).toHaveLength(2);
    });
});
