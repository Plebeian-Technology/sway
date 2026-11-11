import React from "react";
import { Text } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../../src/theme/ThemeProvider";
import { EmptyState } from "../../../src/components/ui/EmptyState";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn().mockResolvedValue(undefined),
    ImpactFeedbackStyle: { Light: "light" },
}));

const wrap = (ui: React.ReactElement, mode: "light" | "dark" = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("EmptyState (PARITY-03)", () => {
    test("renders title", () => {
        wrap(<EmptyState testID="empty" title="No results" />);
        expect(screen.getByText("No results")).toBeTruthy();
    });

    test("renders body when provided", () => {
        wrap(<EmptyState testID="empty" title="No results" body="Nothing here yet." />);
        expect(screen.getByText("Nothing here yet.")).toBeTruthy();
    });

    test("omits body when undefined", () => {
        wrap(<EmptyState testID="empty" title="No results" />);
        expect(screen.queryByText("Nothing here yet.")).toBeNull();
    });

    test("renders CTA when onCtaPress + ctaLabel provided and fires", () => {
        const onCtaPress = jest.fn();
        wrap(<EmptyState testID="empty" title="No results" ctaLabel="Refresh List" onCtaPress={onCtaPress} />);
        fireEvent.press(screen.getByTestId("empty-cta"));
        expect(onCtaPress).toHaveBeenCalledTimes(1);
    });

    test("omits CTA when onCtaPress is undefined", () => {
        wrap(<EmptyState testID="empty" title="No results" body="x" ctaLabel="Refresh List" />);
        expect(screen.queryByTestId("empty-cta")).toBeNull();
        expect(screen.queryByText("Refresh List")).toBeNull();
    });

    test("renders icon node when provided", () => {
        wrap(<EmptyState testID="empty" title="No results" icon={<Text testID="empty-icon">ICON</Text>} />);
        expect(screen.getByTestId("empty-icon")).toBeTruthy();
    });

    test("renders under light and dark theme without crash", () => {
        wrap(<EmptyState testID="empty" title="x" />, "light");
        expect(screen.getByTestId("empty")).toBeTruthy();
        wrap(<EmptyState testID="empty-dark" title="x" />, "dark");
        expect(screen.getByTestId("empty-dark")).toBeTruthy();
    });

    test("default layout keeps the py-12 container and the 40 pt icon", () => {
        wrap(<EmptyState testID="empty" title="No results" />);
        expect(screen.getByTestId("empty").props.className).toContain("py-12");
        expect(screen.UNSAFE_getByProps({ size: 40 })).toBeTruthy();
        expect(screen.UNSAFE_queryByProps({ size: 24 })).toBeNull();
    });

    // @lat: [[mobile-shared-primitives-design#Mobile shared primitives#ui/EmptyState#Compact variant]]
    test("compact uses the py-4 container and the 24 pt icon, keeping title and button", () => {
        const onCtaPress = jest.fn();
        wrap(<EmptyState testID="empty" title="No results" ctaLabel="Refresh List" onCtaPress={onCtaPress} compact />);
        const container = screen.getByTestId("empty");
        expect(container.props.className).toContain("py-4");
        expect(container.props.className).not.toContain("py-12");
        expect(screen.UNSAFE_getByProps({ size: 24 })).toBeTruthy();
        expect(screen.UNSAFE_queryByProps({ size: 40 })).toBeNull();
        expect(screen.getByText("No results")).toBeTruthy();
        fireEvent.press(screen.getByTestId("empty-cta"));
        expect(onCtaPress).toHaveBeenCalledTimes(1);
    });

    test("compact falls back to the title for the accessibility label", () => {
        wrap(<EmptyState testID="empty" title="No results" compact />);
        expect(screen.getByLabelText("No results")).toBeTruthy();
    });
});
