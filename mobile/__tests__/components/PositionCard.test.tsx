/**
 * PositionCard — written before the component existed, so until it shipped every
 * one of these failed on purpose.
 */
import React from "react";
import { Linking } from "react-native";
import { render, screen, fireEvent } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PositionCard } from "../../src/components/PositionCard";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const basePosition = {
    id: 7,
    support: "FOR",
    summary: "We support this bill for public health reasons.",
    bill: {
        id: 10,
        external_id: "HB0042",
        title: "Public Health Act",
    },
    link: null as string | null,
};

describe("PositionCard", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    test("module exports PositionCard", () => {
        expect(PositionCard).not.toBeNull();
    });

    test("renders bill title", () => {
        wrap(<PositionCard position={basePosition} />);
        expect(screen.getByText("Public Health Act")).toBeTruthy();
    });

    test("renders SUPPORTS badge for FOR support", () => {
        wrap(<PositionCard position={basePosition} />);
        expect(screen.getByText("Supports")).toBeTruthy();
    });

    test("renders OPPOSES badge for AGAINST support", () => {
        const position = { ...basePosition, support: "AGAINST" };
        wrap(<PositionCard position={position} />);
        expect(screen.getByText("Opposes")).toBeTruthy();
    });

    test("renders summary text", () => {
        wrap(<PositionCard position={basePosition} />);
        expect(screen.getByText("We support this bill for public health reasons.")).toBeTruthy();
    });

    test("does not render source link when link is null", () => {
        wrap(<PositionCard position={basePosition} />);
        expect(screen.queryByText("Source")).toBeNull();
    });

    test("renders source link when link is provided and opens on press", () => {
        const position = { ...basePosition, link: "https://example.com/bill" };
        wrap(<PositionCard position={position} />);
        const sourceLink = screen.getByText("Source");
        expect(sourceLink).toBeTruthy();
        fireEvent.press(sourceLink);
        expect(openURLSpy).toHaveBeenCalledWith("https://example.com/bill");
    });

    test.each(["sway://organizations/1/memberships/5", "javascript:alert(1)", "tel:4105551234"])(
        "does not render or open unsafe link scheme: %s",
        (unsafeLink) => {
            const position = { ...basePosition, link: unsafeLink };
            wrap(<PositionCard position={position} />);
            expect(screen.queryByText("Source")).toBeNull();
            expect(openURLSpy).not.toHaveBeenCalled();
        },
    );

    test("has testID position-card-{id}", () => {
        wrap(<PositionCard position={basePosition} />);
        expect(screen.getByTestId("position-card-7")).toBeTruthy();
    });

    test("accepts custom testID", () => {
        wrap(<PositionCard position={basePosition} testID="custom-position-card" />);
        expect(screen.getByTestId("custom-position-card")).toBeTruthy();
    });

    test("renders no testimony for a Neutral position, which carries none", () => {
        const position = { ...basePosition, support: "ABSTAIN", summary: null };
        wrap(<PositionCard position={position} />);

        expect(screen.getByTestId("position-card-7")).toBeTruthy();
        expect(screen.queryByText("We support this bill for public health reasons.")).toBeNull();
    });

    test("renders summary text as markdown", () => {
        const position = { ...basePosition, summary: "Supports **clean water**.\n\n- item one" };
        wrap(<PositionCard position={position} />);

        expect(screen.getByText("clean water")).toBeTruthy();
        expect(screen.getByText("item one")).toBeTruthy();
        expect(screen.queryByText(/\*\*/)).toBeNull();
    });
});
