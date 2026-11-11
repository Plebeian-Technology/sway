/**
 * NewPositionModal — written to pass against the finished component.
 */
import React from "react";
import { Platform } from "react-native";
import { render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";

const mockPropose = jest.fn();
jest.mock("../../src/hooks/useOrganizationPositions", () => ({
    useOrganizationPositions: () => ({
        positions: [],
        loading: false,
        error: null,
        refresh: jest.fn(),
        propose: mockPropose,
        busy: false,
    }),
}));

jest.mock("../../src/hooks/useBills", () => ({
    useBills: () => ({
        data: [
            { id: 1, external_id: "HB0001", title: "Test Bill One" },
            { id: 2, external_id: "SB0002", title: "Test Bill Two" },
        ],
        loading: false,
        error: null,
        refresh: jest.fn(),
    }),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

import { NewPositionModal } from "../../src/components/NewPositionModal";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("NewPositionModal", () => {
    beforeEach(() => {
        mockPropose.mockReset();
    });

    test("module exports NewPositionModal", () => {
        expect(NewPositionModal).toBeDefined();
    });

    test("renders with testID new-position-modal when visible", () => {
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByTestId("new-position-modal")).toBeTruthy();
    });

    test("has presentationStyle guard on iOS (Modal present, no crash)", () => {
        const originalOS = Platform.OS;
        (Platform as { OS: string }).OS = "ios";
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByTestId("new-position-modal")).toBeTruthy();
        (Platform as { OS: string }).OS = originalOS;
    });

    test("renders summary FormField", () => {
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByTestId("new-position-summary")).toBeTruthy();
    });

    test("renders FOR (Supports) and AGAINST (Opposes) toggle Pressables", () => {
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByText("Supports")).toBeTruthy();
        expect(screen.getByText("Opposes")).toBeTruthy();
    });

    test("renders bill list items from mocked useBills", () => {
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByText("Test Bill One")).toBeTruthy();
        expect(screen.getByText("Test Bill Two")).toBeTruthy();
    });

    test("renders submit Pressable with correct label", () => {
        wrap(<NewPositionModal visible={true} onClose={jest.fn()} orgId={1} membershipId={12} />);
        expect(screen.getByText("Propose position")).toBeTruthy();
    });
});
