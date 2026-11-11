import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { Markdown, markdownContentLength, markdownExceedsLimit } from "../../src/components/Markdown";

describe("Markdown", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    test("renders nothing for empty content", () => {
        expect(render(<Markdown content={null} />).toJSON()).toBeNull();
        expect(render(<Markdown content="" />).toJSON()).toBeNull();
        expect(render(<Markdown content="[1]: https://example.com/only-def" />).toJSON()).toBeNull();
    });

    test("makes paragraphs, headings and list items selectable only when asked", () => {
        const content = "# Heading\n\nA paragraph.\n\n- list item";
        const { unmount } = render(<Markdown content={content} />);
        for (const text of ["Heading", "A paragraph.", "list item"]) {
            expect(screen.getByText(text).props.selectable).toBeFalsy();
        }
        unmount();

        render(<Markdown content={content} selectable />);
        for (const text of ["Heading", "A paragraph.", "list item"]) {
            expect(screen.getByText(text).props.selectable).toBe(true);
        }
    });

    test("renders emphasis, strong, strikethrough and inline code without their marks", () => {
        render(<Markdown content="**bold** and *italic* and ~~gone~~ and `code`" />);

        expect(screen.getByText("bold")).toBeTruthy();
        expect(screen.getByText("italic")).toBeTruthy();
        expect(screen.getByText("gone")).toBeTruthy();
        expect(screen.getByText("code")).toBeTruthy();
        expect(screen.queryByText(/\*\*|~~|`/)).toBeNull();
    });

    test("renders headings with the header role", () => {
        render(<Markdown content={"# Title\n\nBody"} />);

        expect(screen.getByRole("header", { name: "Title" })).toBeTruthy();
        expect(screen.getByText("Body")).toBeTruthy();
    });

    test("renders unordered, ordered and task lists with markers", () => {
        render(<Markdown content={"- apple\n- pear\n\n3. three\n4. four\n\n- [x] done\n- [ ] todo"} />);

        expect(screen.getAllByText("•")).toHaveLength(2);
        expect(screen.getByText("3.")).toBeTruthy();
        expect(screen.getByText("4.")).toBeTruthy();
        expect(screen.getByText("☑")).toBeTruthy();
        expect(screen.getByText("☐")).toBeTruthy();
        expect(screen.getByText("done")).toBeTruthy();
    });

    test("renders a GFM table as header and body cells", () => {
        render(<Markdown content={"| Org | Stance |\n| --- | :---: |\n| Sierra Club | Support |"} />);

        expect(screen.getByText("Org")).toBeTruthy();
        expect(screen.getByText("Stance")).toBeTruthy();
        expect(screen.getByText("Sierra Club")).toBeTruthy();
        expect(screen.getByText("Support")).toBeTruthy();
        expect(screen.queryByText(/---/)).toBeNull();
    });

    test("renders blockquotes and fenced code blocks", () => {
        render(<Markdown content={"> quoted words\n\n```\nconst x = 1;\n```"} />);

        expect(screen.getByText("quoted words")).toBeTruthy();
        expect(screen.getByText("const x = 1;")).toBeTruthy();
        expect(screen.queryByText(/```/)).toBeNull();
    });

    test("opens a safe link and passes it to onOpenUrl when given", () => {
        const onOpenUrl = jest.fn();
        const { unmount } = render(<Markdown content="See [the bill](https://example.com/bill)." />);

        fireEvent.press(screen.getByRole("link", { name: "the bill" }));
        expect(openURLSpy).toHaveBeenCalledWith("https://example.com/bill");
        unmount();

        render(<Markdown content="See [the bill](https://example.com/bill)." onOpenUrl={onOpenUrl} />);
        fireEvent.press(screen.getByRole("link", { name: "the bill" }));
        expect(onOpenUrl).toHaveBeenCalledWith("https://example.com/bill");
    });

    test("resolves reference-style links through their definition and keeps the first definition on duplicates", () => {
        render(
            <Markdown
                content={"Read [the filing][1].\n\n[1]: https://example.com/filing\n[1]: https://example.com/other"}
            />,
        );

        fireEvent.press(screen.getByRole("link", { name: "the filing" }));
        expect(openURLSpy).toHaveBeenCalledWith("https://example.com/filing");
        expect(screen.queryByText(/example\.com\/filing/)).toBeNull();
    });

    test("shows an unsafe link as plain text that cannot be pressed", () => {
        render(<Markdown content="Do not [click](javascript:alert(1)) this." />);

        expect(screen.queryByRole("link")).toBeNull();
        expect(screen.getByText(/click/)).toBeTruthy();
        expect(openURLSpy).not.toHaveBeenCalled();
    });

    test("ignores a link with an empty label", () => {
        render(<Markdown content="Text [](https://example.com) here" />);

        expect(screen.queryByRole("link")).toBeNull();
        expect(screen.getByText("Text  here")).toBeTruthy();
    });

    test("shows raw html as text instead of interpreting it", () => {
        render(<Markdown content={'<script>alert("x")</script>'} />);

        expect(screen.getByText(/<script>/)).toBeTruthy();
    });

    describe("truncation", () => {
        test("cuts text at maxChars, adds an ellipsis, and expands on request", () => {
            const content = "a".repeat(30);
            const { rerender } = render(<Markdown content={content} maxChars={10} />);

            expect(screen.getByText("a".repeat(10))).toBeTruthy();
            expect(screen.getByText("…")).toBeTruthy();

            rerender(<Markdown content={content} maxChars={10} expanded />);
            expect(screen.getByText(content)).toBeTruthy();
            expect(screen.queryByText("…")).toBeNull();
        });

        test("keeps a link whole when the cut would land inside it", () => {
            render(
                <Markdown
                    content="Intro [a very long link label](https://example.com/x) trailing words"
                    maxChars={12}
                />,
            );

            expect(screen.getByRole("link", { name: "a very long link label" })).toBeTruthy();
            expect(screen.queryByText(/trailing/)).toBeNull();
            expect(screen.getByText("…")).toBeTruthy();
        });

        test("drops whole blocks after the budget is spent", () => {
            render(<Markdown content={"First paragraph.\n\nSecond paragraph."} maxChars={16} />);

            expect(screen.getByText("First paragraph.")).toBeTruthy();
            expect(screen.queryByText("Second paragraph.")).toBeNull();
            expect(screen.getByText("…")).toBeTruthy();
        });

        test("shows no ellipsis when everything fits", () => {
            render(<Markdown content="Short." maxChars={50} />);

            expect(screen.queryByText("…")).toBeNull();
        });

        test("does not mark content as truncated when an atomic link at the end crosses maxChars with no following nodes", () => {
            const content = `Intro [a very long link label](https://example.com/x)\n\n[unused]: https://example.com/def`;
            render(<Markdown content={content} maxChars={10} />);

            expect(screen.getByRole("link", { name: "a very long link label" })).toBeTruthy();
            expect(screen.queryByText("…")).toBeNull();
            expect(markdownExceedsLimit(content, 10)).toBe(false);
        });

        test("drops trailing thematic breaks after the budget is exhausted", () => {
            const content = "1234567890\n\n---";
            render(<Markdown content={content} maxChars={10} />);

            expect(screen.getByText("1234567890")).toBeTruthy();
            expect(screen.getByText("…")).toBeTruthy();
            expect(markdownExceedsLimit(content, 10)).toBe(true);
        });

        test("does not mark content as truncated when only a trailing hard break or empty link follows the budget", () => {
            const content = "1234567890\\\n[](https://example.com)![](https://example.com/a.png)";
            render(<Markdown content={content} maxChars={10} />);

            expect(screen.getByText("1234567890")).toBeTruthy();
            expect(screen.queryByText("…")).toBeNull();
            expect(markdownExceedsLimit(content, 10)).toBe(false);
        });

        test("treats footnote references as atomic when crossing maxChars", () => {
            const content = "12345678[^1]\n\n[^1]: Note";
            render(<Markdown content={content} maxChars={10} />);

            expect(screen.getByText("12345678[1]")).toBeTruthy();
            expect(screen.getByText("…")).toBeTruthy();
            expect(markdownExceedsLimit(content, 10)).toBe(true);
        });
    });

    test("markdownContentLength counts what a reader sees, including image references and footnote references", () => {
        expect(markdownContentLength("**bold** [link](https://example.com)")).toBe("bold link".length);
        expect(markdownContentLength("![alt text][img]\n\n[img]: https://example.com/a.png")).toBe("alt text".length);
        expect(markdownContentLength("Claim[^1]\n\n[^1]: Note")).toBe("Claim[1]Note".length);
        expect(markdownContentLength(null)).toBe(0);
    });
});
