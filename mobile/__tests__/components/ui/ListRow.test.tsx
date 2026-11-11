import React from "react";
import { Text } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../../src/theme/ThemeProvider";
import { ListRow } from "../../../src/components/ui/ListRow";

const wrap = (ui: React.ReactElement, mode: "light" | "dark" = "light") =>
    render(<ThemeProvider initialMode={mode}>{ui}</ThemeProvider>);

describe("ListRow (PARITY-03)", () => {
    test("interactive row has accessibilityRole=button and fires onPress", () => {
        const onPress = jest.fn();
        wrap(<ListRow testID="row" label="Row label" onPress={onPress} />);
        const node = screen.getByTestId("row");
        expect(node.props.accessibilityRole).toBe("button");
        fireEvent.press(node);
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("interactive row renders chevron affordance", () => {
        wrap(<ListRow testID="row" label="Row label" onPress={() => {}} />);
        expect(screen.getByTestId("row-chevron")).toBeTruthy();
    });

    test("static row has accessibilityRole=none (suppress container announcement) and no chevron", () => {
        wrap(<ListRow testID="row" label="Row label" />);
        const node = screen.getByTestId("row");
        // accessibilityRole="none" tells the system this box is not interactive,
        // so VoiceOver reads the inner Text once instead of announcing both it
        // and the box around it.
        expect(node.props.accessibilityRole).toBe("none");
        expect(screen.queryByTestId("row-chevron")).toBeNull();
    });

    test("leftSlot and rightSlot render their nodes", () => {
        wrap(
            <ListRow
                testID="row"
                label="Row label"
                onPress={() => {}}
                leftSlot={<Text testID="left">L</Text>}
                rightSlot={<Text testID="right">R</Text>}
            />,
        );
        expect(screen.getByTestId("left")).toBeTruthy();
        expect(screen.getByTestId("right")).toBeTruthy();
    });

    test("enforces 44pt minimum height", () => {
        wrap(<ListRow testID="row" label="x" onPress={() => {}} />);
        const style = screen.getByTestId("row").props.style;
        const flat = Array.isArray(style) ? Object.assign({}, ...style.filter(Boolean)) : style;
        expect(flat.minHeight).toBe(44);
    });

    test("renders under light and dark theme without crash", () => {
        wrap(<ListRow testID="row" label="x" onPress={() => {}} />, "light");
        expect(screen.getByTestId("row")).toBeTruthy();
        wrap(<ListRow testID="row-dark" label="x" onPress={() => {}} />, "dark");
        expect(screen.getByTestId("row-dark")).toBeTruthy();
    });
});
