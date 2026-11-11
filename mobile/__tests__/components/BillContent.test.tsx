import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { BillContent } from "../../src/components/BillContent";

describe("BillContent", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    test("renders summary with clickable citation link", () => {
        render(
            <ThemeProvider initialMode="light">
                <BillContent
                    bill={{
                        id: 1,
                        title: "Test Bill",
                        summary:
                            "Analysis reported by [The Baltimore Banner](https://www.thebaltimorebanner.com/story).",
                    }}
                />
            </ThemeProvider>,
        );

        expect(screen.getByText("Sway summary")).toBeTruthy();
        const link = screen.getByRole("link", { name: "The Baltimore Banner" });
        expect(link).toBeTruthy();
        fireEvent.press(link);
        expect(openURLSpy).toHaveBeenCalledWith("https://www.thebaltimorebanner.com/story");
    });

    test("renders bill text when present", () => {
        render(
            <ThemeProvider initialMode="light">
                <BillContent
                    bill={{
                        id: 2,
                        title: "Test Bill 2",
                        text: "Official statutory language.",
                    }}
                />
            </ThemeProvider>,
        );

        expect(screen.getByText("Bill text")).toBeTruthy();
        expect(screen.getByTestId("bill-content-body")).toBeTruthy();
    });

    test("renders empty fallback when neither summary nor body is present", () => {
        render(
            <ThemeProvider initialMode="light">
                <BillContent
                    bill={{
                        id: 3,
                        title: "Test Bill 3",
                    }}
                />
            </ThemeProvider>,
        );

        expect(screen.getByTestId("bill-content-empty")).toBeTruthy();
    });
});
