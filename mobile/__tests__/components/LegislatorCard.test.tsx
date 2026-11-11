// @lat: [[mobile-jest-first-pass-test-notes#LegislatorCard.test.tsx]]

// ── Fake modules. These get lifted above the imports below ───────────────────

// ThemeProvider — both Card and Pressable call useTheme.
jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// expo-haptics — Pressable calls impactAsync to make the phone buzz.
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// LegislatorChartsPanel — a bare stand-in, so the tests can confirm it appears
// without pulling in the native SVG drawing code.
jest.mock("../../src/components/LegislatorChartsPanel", () => {
    /* oxlint-disable @typescript-eslint/no-require-imports */
    const ReactMod = require("react");
    const RNMod = require("react-native");
    /* oxlint-enable @typescript-eslint/no-require-imports */
    return {
        LegislatorChartsPanel: ({ testID }: { testID?: string; score?: unknown }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "legislator-charts-panel" }),
        default: ({ testID }: { testID?: string; score?: unknown }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "legislator-charts-panel" }),
    };
});

import React from "react";
import { render, screen, fireEvent } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { LegislatorCard } from "../../src/components/LegislatorCard";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const BASE_SCORE = {
    count_agreed: 10,
    count_disagreed: 3,
    count_no_legislator_vote: 2,
    count_legislator_abstained: 1,
};

const BASE_LEGISLATOR = {
    id: 42,
    full_name: "Alice Smith",
    title: "Senator",
    party: "Democrat",
    email: "alice@example.com",
    phone: "410-555-0100",
    photo_url: null,
    user_legislator_score: BASE_SCORE,
};

describe("LegislatorCard (Phase 35 D-09 refactor)", () => {
    test("renders full_name", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        expect(screen.getByText("Alice Smith")).toBeTruthy();
    });

    test("does not render party label", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        expect(screen.queryByText("Democrat")).toBeNull();
    });

    test("renders three score tile labels: Agreed, Disagreed, No vote", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        expect(screen.getByText("Agreed")).toBeTruthy();
        expect(screen.getByText("Disagreed")).toBeTruthy();
        expect(screen.getByText("No vote")).toBeTruthy();
    });

    test("score tile values have fontVariant: ['tabular-nums'] on their Text nodes", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        // At least 3 Text nodes should use equal-width digits — one per tile
        const allTexts = screen.getAllByText(/^\d+$/);
        const tabularNodes = allTexts.filter((node) => {
            const style = node.props.style;
            if (Array.isArray(style)) {
                return style.some(
                    (s: unknown) =>
                        s &&
                        typeof s === "object" &&
                        "fontVariant" in (s as object) &&
                        Array.isArray((s as { fontVariant: unknown }).fontVariant) &&
                        (s as { fontVariant: string[] }).fontVariant.includes("tabular-nums"),
                );
            }
            return (
                style &&
                typeof style === "object" &&
                "fontVariant" in style &&
                Array.isArray((style as { fontVariant: unknown }).fontVariant) &&
                (style as { fontVariant: string[] }).fontVariant.includes("tabular-nums")
            );
        });
        expect(tabularNodes.length).toBeGreaterThanOrEqual(3);
    });

    test("renders charts toggle (testID=legislator-card-{id}-charts-toggle) when score is present", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        expect(screen.getByTestId(`legislator-card-${BASE_LEGISLATOR.id}-charts-toggle`)).toBeTruthy();
    });

    test("pressing charts toggle renders LegislatorChartsPanel (testID=legislator-charts-panel-{id})", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        expect(screen.queryByTestId(`legislator-charts-panel-${BASE_LEGISLATOR.id}`)).toBeNull();
        fireEvent.press(screen.getByTestId(`legislator-card-${BASE_LEGISLATOR.id}-charts-toggle`));
        expect(screen.getByTestId(`legislator-charts-panel-${BASE_LEGISLATOR.id}`)).toBeTruthy();
    });

    test("pressing charts toggle twice hides LegislatorChartsPanel", () => {
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={() => {}} />);
        fireEvent.press(screen.getByTestId(`legislator-card-${BASE_LEGISLATOR.id}-charts-toggle`));
        fireEvent.press(screen.getByTestId(`legislator-card-${BASE_LEGISLATOR.id}-charts-toggle`));
        expect(screen.queryByTestId(`legislator-charts-panel-${BASE_LEGISLATOR.id}`)).toBeNull();
    });

    test("does NOT render charts toggle when user_legislator_score is null", () => {
        const legislatorNoScore = { ...BASE_LEGISLATOR, user_legislator_score: null };
        wrap(<LegislatorCard legislator={legislatorNoScore} onPress={() => {}} />);
        expect(screen.queryByTestId(`legislator-card-${BASE_LEGISLATOR.id}-charts-toggle`)).toBeNull();
    });

    test("pressing card calls onPress", () => {
        const onPress = jest.fn();
        wrap(<LegislatorCard legislator={BASE_LEGISLATOR} onPress={onPress} />);
        fireEvent.press(screen.getByTestId(`legislator-card-${BASE_LEGISLATOR.id}`));
        expect(onPress).toHaveBeenCalledTimes(1);
    });
});
