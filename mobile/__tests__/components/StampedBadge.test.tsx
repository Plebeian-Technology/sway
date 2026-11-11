// @lat: [[mobile-jest-first-pass-test-notes#StampedBadge.test.tsx]]

import React from "react";
import { render, screen } from "@testing-library/react-native";
import { StyleSheet } from "react-native";
import { StampedBadge } from "../../src/components/StampedBadge";

// @lat: [[mobile-jest-first-pass-test-notes#StampedBadge.test.tsx]]
function flat(style: unknown): Record<string, unknown> {
    if (Array.isArray(style)) {
        return Object.assign({}, ...style.map(flat));
    }
    if (typeof style === "number") {
        return StyleSheet.flatten(style) as unknown as Record<string, unknown>;
    }
    return (style as Record<string, unknown>) ?? {};
}

describe("StampedBadge — Bootstrap pill + WCAG contrast (Phase 58 D-04)", () => {
    test("renders with default testID 'stamped-badge'", () => {
        render(<StampedBadge label="Passed" color="#5fcf89" />);
        expect(screen.getByTestId("stamped-badge")).toBeTruthy();
    });

    test("respects a custom testID", () => {
        render(<StampedBadge label="Passed" color="#5fcf89" testID="my-badge" />);
        expect(screen.getByTestId("my-badge")).toBeTruthy();
    });

    test("View backgroundColor is solid fill (= input color, not a wash)", () => {
        const { getByTestId } = render(<StampedBadge label="Passed" color="#3c6ef7" />);
        const view = getByTestId("stamped-badge");
        const style = flat(view.props.style);
        expect(style.backgroundColor).toBe("#3c6ef7");
    });

    test("View borderRadius is 4 (--radius-sm)", () => {
        const { getByTestId } = render(<StampedBadge label="In Committee" color="#3c6ef7" />);
        const style = flat(getByTestId("stamped-badge").props.style);
        expect(style.borderRadius).toBe(4);
    });

    test("View borderWidth is 1 (not 1.5)", () => {
        const { getByTestId } = render(<StampedBadge label="In Committee" color="#3c6ef7" />);
        const style = flat(getByTestId("stamped-badge").props.style);
        expect(style.borderWidth).toBe(1);
    });

    // Blue #3c6ef7: white reads better (4.41 : 1 against 3.50 : 1) → #ffffff
    test("blue fill (#3c6ef7) → white label (higher contrast wins)", () => {
        const { getByTestId } = render(<StampedBadge label="In Committee" color="#3c6ef7" />);
        const badge = getByTestId("stamped-badge");
        // The label Text is the first (and only) child
        const labelText = badge.children[0];
        const textStyle = flat((labelText as { props: { style: unknown } }).props.style);
        expect(textStyle.color).toBe("#ffffff");
    });

    // Yellow warning #ffd600: dark ink reads far better (10.92 : 1 against 1.41 : 1) → #212529
    test("yellow fill (#ffd600) → dark ink label (NOT white)", () => {
        const { getByTestId } = render(<StampedBadge label="Warning" color="#ffd600" />);
        const badge = getByTestId("stamped-badge");
        const labelText = badge.children[0];
        const textStyle = flat((labelText as { props: { style: unknown } }).props.style);
        expect(textStyle.color).toBe("#212529");
        expect(textStyle.color).not.toBe("#ffffff");
    });

    // Red #eb5d68, used for Failed and Vetoed: dark ink reads better
    // (4.63 : 1 against 3.33 : 1) → #212529. An earlier cutoff picked white here,
    // which only managed 3.33 : 1.
    test("red fill (#eb5d68) → dark ink label (NOT white)", () => {
        const { getByTestId } = render(<StampedBadge label="Failed" color="#eb5d68" />);
        const badge = getByTestId("stamped-badge");
        const labelText = badge.children[0];
        const textStyle = flat((labelText as { props: { style: unknown } }).props.style);
        expect(textStyle.color).toBe("#212529");
        expect(textStyle.color).not.toBe("#ffffff");
    });

    // Green #5fcf89, used for Passed: dark ink reads better (7.91 : 1) → #212529
    test("green fill (#5fcf89) → dark ink label", () => {
        const { getByTestId } = render(<StampedBadge label="Passed" color="#5fcf89" />);
        const badge = getByTestId("stamped-badge");
        const labelText = badge.children[0];
        const textStyle = flat((labelText as { props: { style: unknown } }).props.style);
        expect(textStyle.color).toBe("#212529");
    });

    test("label Text fontVariant includes 'tabular-nums'", () => {
        const { getByTestId } = render(<StampedBadge label="42" color="#3c6ef7" />);
        const badge = getByTestId("stamped-badge");
        const labelText = badge.children[0];
        const textStyle = flat((labelText as { props: { style: unknown } }).props.style);
        expect(Array.isArray(textStyle.fontVariant)).toBe(true);
        expect((textStyle.fontVariant as string[]).includes("tabular-nums")).toBe(true);
    });

    test("renders label text", () => {
        render(<StampedBadge label="In Committee" color="#3c6ef7" />);
        expect(screen.getByText("In Committee")).toBeTruthy();
    });

    test("accessibilityLabel is 'Status: {label}'", () => {
        const { getByTestId } = render(<StampedBadge label="Tabled" color="#6c757d" />);
        expect(getByTestId("stamped-badge").props.accessibilityLabel).toBe("Status: Tabled");
    });

    test("accessibilityPrefix replaces the word before the label", () => {
        const { getByTestId } = render(<StampedBadge label="Support" color="#1f7a45" accessibilityPrefix="Position" />);
        expect(getByTestId("stamped-badge").props.accessibilityLabel).toBe("Position: Support");
    });

    test("is one accessible element, so the label is announced instead of ignored", () => {
        const { getByTestId } = render(<StampedBadge label="Tabled" color="#6c757d" />);
        expect(getByTestId("stamped-badge").props.accessible).toBe(true);
    });
});
