import React from "react";
import { Linking, StyleSheet } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { RelatedNewsArticles } from "../../src/components/RelatedNewsArticles";
import type { RelatedNewsArticle } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { swayTokens } from "../../src/theme/tokens";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("RelatedNewsArticles", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    const sampleArticle: RelatedNewsArticle = {
        id: 10,
        title: "Transit Overhaul Advances",
        outlet_name: "The Baltimore Sun",
        author_name: "Emily Vance",
        published_at: "2026-04-12T14:30:00Z",
        article_kind: "reporting",
        match_kind: "direct",
        url: "https://example.com/story",
    };

    test("renders null (0 nodes) when articles is undefined", () => {
        const { toJSON } = wrap(<RelatedNewsArticles articles={undefined} />);
        expect(toJSON()).toBeNull();
    });

    test("renders null (0 nodes) when articles is null", () => {
        const { toJSON } = wrap(<RelatedNewsArticles articles={null} />);
        expect(toJSON()).toBeNull();
    });

    test("renders null (0 nodes) when articles is empty array []", () => {
        const { toJSON } = wrap(<RelatedNewsArticles articles={[]} />);
        expect(toJSON()).toBeNull();
    });

    test("renders card header 'Related news' and container testID", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        expect(screen.getByTestId("related-news-articles")).toBeTruthy();
        expect(screen.getByText("Related news")).toBeTruthy();
    });

    test("renders article title, outlet name, publication date, and author byline", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        expect(screen.getByText("Transit Overhaul Advances")).toBeTruthy();
        expect(screen.getByText("The Baltimore Sun")).toBeTruthy();
        expect(screen.getByText("April 12, 2026")).toBeTruthy();
        expect(screen.getByText("By Emily Vance")).toBeTruthy();
    });

    test("omits author byline and publication date cleanly when null or undefined", () => {
        const minimalArticle: RelatedNewsArticle = {
            id: 11,
            title: "Quick Wire Note",
            outlet_name: "Associated Press",
            author_name: null,
            published_at: null,
            article_kind: "reporting",
            match_kind: "context",
            url: "https://example.com/wire",
        };
        wrap(<RelatedNewsArticles articles={[minimalArticle]} />);
        expect(screen.getByText("Quick Wire Note")).toBeTruthy();
        expect(screen.getByText("Associated Press")).toBeTruthy();
        expect(screen.queryByText(/By /)).toBeNull();
        expect(screen.queryByText(/•/)).toBeNull();
    });

    test("renders distinct badge for direct coverage versus surrounding context", () => {
        const directArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 1,
            match_kind: "direct",
        };
        const contextArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 2,
            match_kind: "context",
        };
        const { rerender } = wrap(<RelatedNewsArticles articles={[directArticle]} />);
        expect(screen.getByText("Direct coverage")).toBeTruthy();
        expect(screen.queryByText("Context")).toBeNull();

        rerender(
            <ThemeProvider initialMode="light">
                <RelatedNewsArticles articles={[contextArticle]} />
            </ThemeProvider>,
        );
        expect(screen.getByText("Context")).toBeTruthy();
        expect(screen.queryByText("Direct coverage")).toBeNull();
    });

    test("renders distinct badge for op-ed and editorial, omitting badge for standard reporting", () => {
        const opEdArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 1,
            article_kind: "op_ed",
        };
        const editorialArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 2,
            article_kind: "editorial",
        };
        const reportingArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 3,
            article_kind: "reporting",
        };
        const unknownArticle: RelatedNewsArticle = {
            ...sampleArticle,
            id: 4,
            article_kind: "unknown",
        };

        const { rerender } = wrap(<RelatedNewsArticles articles={[opEdArticle]} />);
        expect(screen.getByText("Op-ed")).toBeTruthy();

        rerender(
            <ThemeProvider initialMode="light">
                <RelatedNewsArticles articles={[editorialArticle]} />
            </ThemeProvider>,
        );
        expect(screen.getByText("Editorial")).toBeTruthy();

        rerender(
            <ThemeProvider initialMode="light">
                <RelatedNewsArticles articles={[reportingArticle]} />
            </ThemeProvider>,
        );
        expect(screen.queryByText("Op-ed")).toBeNull();
        expect(screen.queryByText("Editorial")).toBeNull();
        expect(screen.queryByText("Reporting")).toBeNull();

        rerender(
            <ThemeProvider initialMode="light">
                <RelatedNewsArticles articles={[unknownArticle]} />
            </ThemeProvider>,
        );
        expect(screen.queryByText("Op-ed")).toBeNull();
        expect(screen.queryByText("Editorial")).toBeNull();
        expect(screen.queryByText("Unknown")).toBeNull();
    });

    test("pressing safe external link calls Linking.openURL with sanitized URL", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        const link = screen.getByRole("link", { name: "Transit Overhaul Advances" });
        fireEvent.press(link);
        expect(openURLSpy).toHaveBeenCalledWith("https://example.com/story");
    });

    test("supports custom onOpenUrl prop callback", () => {
        const onOpenUrlMock = jest.fn();
        wrap(<RelatedNewsArticles articles={[sampleArticle]} onOpenUrl={onOpenUrlMock} />);
        const link = screen.getByRole("link", { name: "Transit Overhaul Advances" });
        fireEvent.press(link);
        expect(onOpenUrlMock).toHaveBeenCalledWith("https://example.com/story");
        expect(openURLSpy).not.toHaveBeenCalled();
    });

    test("refuses unsafe schemes (javascript:, data:, file:, intent:, credentials) and renders title without link press handler", () => {
        const unsafeArticles: RelatedNewsArticle[] = [
            {
                ...sampleArticle,
                id: 101,
                title: "Malicious Script Link",
                url: "javascript:alert(1)",
            },
            {
                ...sampleArticle,
                id: 102,
                title: "Malicious Data Link",
                url: "data:text/html,<script>alert(1)</script>",
            },
            {
                ...sampleArticle,
                id: 103,
                title: "Local File Link",
                url: "file:///etc/passwd",
            },
            {
                ...sampleArticle,
                id: 104,
                title: "Credentials In URL",
                url: "https://admin:pass@example.com/news",
            },
        ];

        wrap(<RelatedNewsArticles articles={unsafeArticles} />);

        for (const article of unsafeArticles) {
            expect(screen.getByText(article.title)).toBeTruthy();
            expect(screen.queryByRole("link", { name: article.title })).toBeNull();
            fireEvent.press(screen.getByText(article.title));
        }

        expect(openURLSpy).not.toHaveBeenCalled();
    });

    test("accessibility attributes on safe links", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        const link = screen.getByRole("link", { name: "Transit Overhaul Advances" });
        expect(link.props.accessibilityRole).toBe("link");
        expect(link.props.accessibilityLabel).toBe("Transit Overhaul Advances");
        expect(link.props.accessibilityHint).toBe("Opens article in browser");
    });

    test("pads the title link to a 44pt touch target without moving the layout", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        const link = screen.getByRole("link", { name: "Transit Overhaul Advances" });
        const slop = link.props.hitSlop as { top: number; bottom: number };

        const SINGLE_LINE_TITLE_HEIGHT = 24;
        expect(slop.top + slop.bottom + SINGLE_LINE_TITLE_HEIGHT).toBeGreaterThanOrEqual(44);
    });

    test("exposes the card title as a heading", () => {
        wrap(<RelatedNewsArticles articles={[sampleArticle]} />);
        expect(screen.getByRole("header", { name: "Related news" })).toBeTruthy();
    });

    test.each(["light", "dark"] as const)(
        "colours the op-ed and editorial badges with the %s warning token",
        (mode) => {
            const { rerender } = render(
                <ThemeProvider initialMode={mode}>
                    <RelatedNewsArticles articles={[{ ...sampleArticle, id: 1, article_kind: "op_ed" }]} />
                </ThemeProvider>,
            );
            expect(StyleSheet.flatten(screen.getByText("Op-ed").props.style).color).toBe(swayTokens[mode].warning);

            rerender(
                <ThemeProvider initialMode={mode}>
                    <RelatedNewsArticles articles={[{ ...sampleArticle, id: 2, article_kind: "editorial" }]} />
                </ThemeProvider>,
            );
            expect(StyleSheet.flatten(screen.getByText("Editorial").props.style).color).toBe(swayTokens[mode].warning);
        },
    );

    test("lets readers select the title when it is not a link", () => {
        wrap(<RelatedNewsArticles articles={[{ ...sampleArticle, url: "javascript:alert(1)" }]} />);
        expect(screen.getByText("Transit Overhaul Advances").props.selectable).toBe(true);
    });

    test("preserves sequence of multiple articles exactly as provided by server", () => {
        const articles: RelatedNewsArticle[] = [
            { ...sampleArticle, id: 1, title: "First Article" },
            { ...sampleArticle, id: 2, title: "Second Article" },
            { ...sampleArticle, id: 3, title: "Third Article" },
        ];
        wrap(<RelatedNewsArticles articles={articles} />);

        const titleNodes = screen.getAllByRole("link");
        expect(titleNodes.map((n) => n.props.accessibilityLabel)).toEqual([
            "First Article",
            "Second Article",
            "Third Article",
        ]);
    });

    test("renders title/URL-only (textless) articles cleanly", () => {
        const linkOnlyArticle: RelatedNewsArticle = {
            id: 99,
            title: "Link Only Title",
            url: "https://example.com/brief",
            outlet_name: "Wire Service",
            published_at: null,
            author_name: null,
            article_kind: "reporting",
            match_kind: "context",
        };
        wrap(<RelatedNewsArticles articles={[linkOnlyArticle]} />);
        expect(screen.getByText("Link Only Title")).toBeTruthy();
        expect(screen.getByText("Wire Service")).toBeTruthy();
        expect(screen.getByText("Context")).toBeTruthy();
    });
});
