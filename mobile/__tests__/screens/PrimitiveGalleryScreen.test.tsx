import React from "react";
import { render, screen } from "@testing-library/react-native";
import { PrimitiveGalleryScreen } from "../../src/screens/__dev__/PrimitiveGalleryScreen";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light", Medium: "medium", Heavy: "heavy" },
}));

describe("PrimitiveGalleryScreen (PARITY-03 — Phase 33 SC-4)", () => {
    test("renders root ScrollView", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getByTestId("primitives-gallery")).toBeTruthy();
    });

    test("renders both theme section headers", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getByText("SWAY LIGHT")).toBeTruthy();
        expect(screen.getByText("SWAY DARK")).toBeTruthy();
    });

    test("renders Card primitive in both theme sections", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getAllByText("Card content").length).toBeGreaterThanOrEqual(2);
    });

    test("renders Pressable primitive in both theme sections", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getAllByText("Primary action").length).toBeGreaterThanOrEqual(2);
    });

    test("renders EmptyState primitive in both theme sections", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getAllByText("No results").length).toBeGreaterThanOrEqual(2);
    });

    test("renders ListRow primitive in both theme sections", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getAllByText("Row label").length).toBeGreaterThanOrEqual(2);
    });

    test("renders FormField primitive in both theme sections", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getAllByText("Field label").length).toBeGreaterThanOrEqual(2);
    });

    test("each theme section is wrapped in its own subtree", () => {
        render(<PrimitiveGalleryScreen />);
        expect(screen.getByTestId("gallery-section-light")).toBeTruthy();
        expect(screen.getByTestId("gallery-section-dark")).toBeTruthy();
    });

    test("does not throw on initial render", () => {
        expect(() => render(<PrimitiveGalleryScreen />)).not.toThrow();
    });
});
