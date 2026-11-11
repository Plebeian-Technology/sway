import React from "react";
import { Linking, StyleSheet } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { NewsArticleTestimony, getAttribution } from "../../src/components/NewsArticleTestimony";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { swayTokens } from "../../src/theme/tokens";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("NewsArticleTestimony", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    const supportTestimony: NewsArticleTestimonyType = {
        id: 1,
        author_name: "Emily Vance",
        outlet_name: "The Baltimore Banner",
        stance: "support",
        url: "https://thebaltimorebanner.com/opinion/support-transit",
        argument: "Investing in regional transit expands economic opportunity across Baltimore.",
    };

    const opposeTestimony: NewsArticleTestimonyType = {
        id: 2,
        author_name: null,
        outlet_name: "The Baltimore Sun",
        stance: "oppose",
        url: "https://baltimoresun.com/opinion/editorial/transit-costs",
        argument: "The proposed capital funding mechanism lacks oversight and fiscal safeguards.",
    };

    describe("empty and mismatched stance suppression (zero-node invariant)", () => {
        test("renders null (0 nodes) when testimonies is undefined", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={undefined} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null (0 nodes) when testimonies is null", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={null} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null (0 nodes) when testimonies is empty array", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[]} />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when stance='support' but only oppose testimonies exist", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[opposeTestimony]} stance="support" />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when stance='oppose' but only support testimonies exist", () => {
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="oppose" />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when items have empty or whitespace argument", () => {
            const emptyArgTestimony: NewsArticleTestimonyType = {
                ...supportTestimony,
                argument: "   ",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[emptyArgTestimony]} stance="support" />);
            expect(toJSON()).toBeNull();
        });

        test("renders null when item has unknown or invalid stance", () => {
            const invalidStanceTestimony = {
                ...supportTestimony,
                stance: "neutral" as unknown as "support",
            };
            const { toJSON } = wrap(<NewsArticleTestimony testimonies={[invalidStanceTestimony]} stance="support" />);
            expect(toJSON()).toBeNull();
        });
    });

    describe("attribution formatting", () => {
        test("formats byline as 'By <author_name>' when author is present", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            expect(screen.getByText("By Emily Vance")).toBeTruthy();
            expect(screen.getByText("The Baltimore Banner")).toBeTruthy();
        });

        test("formats byline as '<outlet_name> Editorial Board' when author is null or absent", () => {
            wrap(<NewsArticleTestimony testimonies={[opposeTestimony]} stance="oppose" />);
            expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeTruthy();
            expect(screen.getByText("The Baltimore Sun")).toBeTruthy();
        });

        test("avoids duplicate 'Editorial Board' when outlet_name already includes it", () => {
            const boardTestimony: NewsArticleTestimonyType = {
                id: 3,
                author_name: null,
                outlet_name: "Washington Post Editorial Board",
                stance: "support",
                url: "https://washingtonpost.com/opinions",
                argument: "Regional infrastructure demands prompt legislative approval.",
            };
            wrap(<NewsArticleTestimony testimonies={[boardTestimony]} stance="support" />);
            expect(screen.getAllByText("Washington Post Editorial Board")).toHaveLength(2);
            expect(screen.queryByText(/Editorial Board Editorial Board/)).toBeNull();
        });

        test("getAttribution helper produces correct byline and outlet", () => {
            expect(getAttribution(supportTestimony)).toEqual({
                authorByline: "By Emily Vance",
                outletName: "The Baltimore Banner",
            });

            expect(getAttribution(opposeTestimony)).toEqual({
                authorByline: "The Baltimore Sun Editorial Board",
                outletName: "The Baltimore Sun",
            });

            const alreadyBoard: NewsArticleTestimonyType = {
                id: 4,
                author_name: null,
                outlet_name: "The Daily Record Editorial Board",
                stance: "oppose",
                url: "https://example.com/dr",
                argument: "Test argument",
            };
            expect(getAttribution(alreadyBoard)).toEqual({
                authorByline: "The Daily Record Editorial Board",
                outletName: "The Daily Record Editorial Board",
            });
        });
    });

    describe("visual demarcation", () => {
        test("renders 'News commentary' stamp badge on every testimony item", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony, opposeTestimony]} />);
            const badges = screen.getAllByText("News commentary");
            expect(badges).toHaveLength(2);
        });

        test("renders stance badges ('Support' / 'Oppose') when stance prop is omitted", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony, opposeTestimony]} />);
            expect(screen.getByText("Support")).toBeTruthy();
            expect(screen.getByText("Oppose")).toBeTruthy();
        });

        test.each(["light", "dark"] as const)("colours the stamp badge with the %s warning token", (mode) => {
            render(
                <ThemeProvider initialMode={mode}>
                    <NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />
                </ThemeProvider>,
            );
            const label = StyleSheet.flatten(screen.getByText("News commentary").props.style);
            expect(label.color).toBe(swayTokens[mode].warning);
        });

        test("lets readers select the author byline", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            expect(screen.getByText("By Emily Vance").props.selectable).toBe(true);
        });

        test("omits stance badges when stance prop is explicitly filtered", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            expect(screen.queryByText("Support")).toBeNull();
            expect(screen.getByText("News commentary")).toBeTruthy();
        });
    });

    describe("argument content and markdown rendering", () => {
        test("renders argument content via CitedMarkdown", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            expect(
                screen.getByText("Investing in regional transit expands economic opportunity across Baltimore."),
            ).toBeTruthy();
        });

        test("renders markdown links within argument content as clickable links", () => {
            const testimonyWithMarkdownLink: NewsArticleTestimonyType = {
                id: 5,
                author_name: "Marcus Cole",
                outlet_name: "Maryland Matters",
                stance: "support",
                url: "https://marylandmatters.org/opinion/transit",
                argument: "According to the [MTA Fiscal Audit](https://mta.maryland.gov/audit), funding is viable.",
            };
            wrap(<NewsArticleTestimony testimonies={[testimonyWithMarkdownLink]} stance="support" />);
            const markdownLink = screen.getByRole("link", { name: "MTA Fiscal Audit" });
            expect(markdownLink).toBeTruthy();
            fireEvent.press(markdownLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://mta.maryland.gov/audit");
        });

        // @lat: [[news-mobile-testimony#News mobile testimony#URL safety and markdown citation parsing]]
        test("lets readers select the argument and keeps its citation links pressable", () => {
            const testimonyWithMarkdownLink: NewsArticleTestimonyType = {
                id: 6,
                author_name: "Marcus Cole",
                outlet_name: "Maryland Matters",
                stance: "support",
                url: "https://marylandmatters.org/opinion/transit",
                argument: "According to the [MTA Fiscal Audit](https://mta.maryland.gov/audit), funding is viable.",
            };
            wrap(<NewsArticleTestimony testimonies={[testimonyWithMarkdownLink]} stance="support" />);
            expect(screen.getByText(/According to the/).props.selectable).toBe(true);

            fireEvent.press(screen.getByRole("link", { name: "MTA Fiscal Audit" }));
            expect(openURLSpy).toHaveBeenCalledWith("https://mta.maryland.gov/audit");
        });
    });

    describe("citation link safety and navigation", () => {
        test("opens safe citation URL via Linking.openURL on press", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            const citationLink = screen.getByRole("link", { name: "The Baltimore Banner" });
            expect(citationLink.props.accessibilityRole).toBe("link");
            expect(citationLink.props.accessibilityHint).toBe("Opens article in browser");

            fireEvent.press(citationLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://thebaltimorebanner.com/opinion/support-transit");
        });

        test("pads the outlet link to a 44pt touch target without reaching into the argument above it", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" />);
            const link = screen.getByRole("link", { name: "The Baltimore Banner" });
            const slop = link.props.hitSlop as { top: number; bottom: number; left: number; right: number };

            const OUTLET_LINK_HEIGHT = 18;
            const GAP_ABOVE_LINK = 4;
            expect(slop.top).toBeLessThanOrEqual(GAP_ABOVE_LINK);
            expect(slop.top + slop.bottom + OUTLET_LINK_HEIGHT).toBeGreaterThanOrEqual(44);
        });

        test("supports custom onOpenUrl prop callback", () => {
            const onOpenUrlMock = jest.fn();
            wrap(<NewsArticleTestimony testimonies={[supportTestimony]} stance="support" onOpenUrl={onOpenUrlMock} />);
            const citationLink = screen.getByRole("link", { name: "The Baltimore Banner" });
            fireEvent.press(citationLink);

            expect(onOpenUrlMock).toHaveBeenCalledWith("https://thebaltimorebanner.com/opinion/support-transit");
            expect(openURLSpy).not.toHaveBeenCalled();
        });

        test("refuses unsafe schemes (javascript:, data:, file:, credentials) by rendering inert plain text without link role", () => {
            const unsafeTestimonies: NewsArticleTestimonyType[] = [
                {
                    id: 101,
                    author_name: "Bad Actor",
                    outlet_name: "Script News",
                    stance: "support",
                    url: "javascript:alert(1)",
                    argument: "Arguments with malicious script url.",
                },
                {
                    id: 102,
                    author_name: "Data Exporter",
                    outlet_name: "Data News",
                    stance: "support",
                    url: "data:text/html,<script>alert(1)</script>",
                    argument: "Arguments with data uri.",
                },
                {
                    id: 103,
                    author_name: "Local Attacker",
                    outlet_name: "File News",
                    stance: "support",
                    url: "file:///etc/passwd",
                    argument: "Arguments with local file url.",
                },
                {
                    id: 104,
                    author_name: "Phisher",
                    outlet_name: "Phish News",
                    stance: "support",
                    url: "https://admin:pass@example.com/steal",
                    argument: "Arguments with credentials in url.",
                },
            ];

            wrap(<NewsArticleTestimony testimonies={unsafeTestimonies} stance="support" />);

            for (const item of unsafeTestimonies) {
                expect(screen.getByText(item.outlet_name)).toBeTruthy();
                expect(screen.queryByRole("link", { name: item.outlet_name })).toBeNull();
                fireEvent.press(screen.getByText(item.outlet_name));
            }

            expect(openURLSpy).not.toHaveBeenCalled();
        });
    });

    describe("stance segregation", () => {
        test("stance='support' filters only support items and excludes oppose items", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony, opposeTestimony]} stance="support" />);
            expect(screen.getByText("By Emily Vance")).toBeTruthy();
            expect(screen.queryByText("The Baltimore Sun Editorial Board")).toBeNull();
        });

        test("stance='oppose' filters only oppose items and excludes support items", () => {
            wrap(<NewsArticleTestimony testimonies={[supportTestimony, opposeTestimony]} stance="oppose" />);
            expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeTruthy();
            expect(screen.queryByText("By Emily Vance")).toBeNull();
        });
    });

    describe("volumetric rendering and ordering", () => {
        test("renders multiple testimonies preserving provided array order", () => {
            const testimonies: NewsArticleTestimonyType[] = [
                { ...supportTestimony, id: 10, author_name: "First Columnist" },
                { ...supportTestimony, id: 11, author_name: "Second Columnist" },
                { ...supportTestimony, id: 12, author_name: "Third Columnist" },
            ];
            wrap(<NewsArticleTestimony testimonies={testimonies} stance="support" />);

            const bylines = screen.getAllByText(/By /);
            expect(bylines.map((b) => b.props.children)).toEqual([
                "By First Columnist",
                "By Second Columnist",
                "By Third Columnist",
            ]);
        });
    });
});
