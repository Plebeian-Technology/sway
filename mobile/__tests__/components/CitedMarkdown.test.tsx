import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { CitedMarkdown } from "../../src/components/CitedMarkdown";

describe("CitedMarkdown", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    test("renders null or empty content cleanly", () => {
        const { toJSON } = render(<CitedMarkdown content={null} />);
        expect(toJSON()).toBeNull();
    });

    test("renders plain text without links", () => {
        render(<CitedMarkdown content="Standard plain text content." />);
        expect(screen.getByText("Standard plain text content.")).toBeTruthy();
        expect(screen.queryByRole("link")).toBeNull();
    });

    test("renders multiple links with press handlers", () => {
        render(
            <CitedMarkdown content="See [Outlet One](https://one.com/story) and [Outlet Two](https://two.com/story) for details." />,
        );

        const linkOne = screen.getByRole("link", { name: "Outlet One" });
        const linkTwo = screen.getByRole("link", { name: "Outlet Two" });

        expect(linkOne).toBeTruthy();
        expect(linkTwo).toBeTruthy();

        fireEvent.press(linkOne);
        expect(openURLSpy).toHaveBeenCalledWith("https://one.com/story");

        fireEvent.press(linkTwo);
        expect(openURLSpy).toHaveBeenCalledWith("https://two.com/story");
    });

    test("calls custom onOpenUrl when provided", () => {
        const customOpen = jest.fn();
        render(<CitedMarkdown content="Visit [Custom Site](https://example.com/item)" onOpenUrl={customOpen} />);

        const link = screen.getByRole("link", { name: "Custom Site" });
        fireEvent.press(link);
        expect(customOpen).toHaveBeenCalledWith("https://example.com/item");
        expect(openURLSpy).not.toHaveBeenCalled();
    });

    test("renders unsafe link as inert text without link role", () => {
        render(<CitedMarkdown content="Caution: [Evil Script](javascript:alert(1)) in summary." />);

        expect(screen.getByText(/Caution: Evil Script in summary\./)).toBeTruthy();
        expect(screen.queryByRole("link")).toBeNull();
    });

    // @lat: [[news-mobile-testimony#News mobile testimony#URL safety and markdown citation parsing]]
    test("renders the root text selectable when selectable is set", () => {
        render(<CitedMarkdown content="Copyable argument." testID="argument" selectable />);
        expect(screen.getByTestId("argument").props.selectable).toBe(true);
    });

    test("renders the root text not selectable by default", () => {
        render(<CitedMarkdown content="Locked argument." testID="argument" />);
        expect(screen.getByTestId("argument").props.selectable).toBe(false);
    });

    test("keeps citation links pressable when selectable is set", () => {
        render(<CitedMarkdown content="See [Outlet One](https://one.com/story) for details." selectable />);

        fireEvent.press(screen.getByRole("link", { name: "Outlet One" }));
        expect(openURLSpy).toHaveBeenCalledWith("https://one.com/story");
    });

    test("truncation preserves link intact when link crosses boundary", () => {
        const content = "1234567890 [My Link](https://example.com/my-link) 1234567890";
        render(<CitedMarkdown content={content} maxChars={15} expanded={false} />);

        const link = screen.getByRole("link", { name: "My Link" });
        expect(link).toBeTruthy();
        expect(screen.getByText(/…/)).toBeTruthy();
    });
});
