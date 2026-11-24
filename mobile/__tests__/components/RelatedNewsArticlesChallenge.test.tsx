const mockUseBill = jest.fn();
jest.mock("../../src/hooks/useBill", () => ({
    useBill: () => mockUseBill(),
}));

const mockUseFocusedSync = jest.fn();
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: (opts: unknown) => mockUseFocusedSync(opts),
}));

const mockUseBootstrap = jest.fn();
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));

const mockUseSession = jest.fn();
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));

const mockUseCastUserVote = jest.fn();
jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => mockUseCastUserVote(),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));

jest.mock("expo-web-browser", () => ({
    openBrowserAsync: jest.fn(async () => ({ type: "dismiss" })),
}));

jest.mock("react-native-reanimated", () => require("react-native-reanimated/mock"));

jest.mock("../../src/components/SkeletonCard", () => ({
    SkeletonCard: ({ testID }: { testID?: string }) =>
        require("react").createElement(require("react-native").View, { testID: testID ?? "skeleton-card" }),
    default: ({ testID }: { testID?: string }) =>
        require("react").createElement(require("react-native").View, { testID: testID ?? "skeleton-card" }),
}));

import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";
import { RelatedNewsArticles } from "../../src/components/RelatedNewsArticles";
import BillDetailScreen from "../../src/screens/BillDetailScreen";
import BillOfTheMonthScreen from "../../src/screens/BillOfTheMonthScreen";
import type { RelatedNewsArticle } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

// @lat: [[news-mobile-links#Placement outside summary and testimony]]
// @lat: [[news-mobile-links#Mobile link safety and external navigation]]
// @lat: [[news-mobile-links#Zero-node suppression and screen lifecycle]]

interface JsonNode {
    type: string;
    props?: Record<string, unknown>;
    children?: (JsonNode | string | null)[] | null;
}

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const sampleArticle: RelatedNewsArticle = {
    id: 1001,
    title: "City Council Approves New Zoning Reform",
    outlet_name: "The Baltimore Sun",
    author_name: "Marcus Vance",
    published_at: "2026-05-15T12:00:00Z",
    article_kind: "reporting",
    match_kind: "direct",
    url: "https://example.com/zoning-reform-2026",
};

const fullBillDetailPayload = {
    bill: {
        id: 42,
        title: "Open Records Act",
        bill_number: "HB 1234",
        external_id: "HB1234",
        status: "Passed",
        status_color: "#5fcf89",
        summary: "A detailed bill summary that tests layout placement and citations.",
        link: "https://mgaleg.maryland.gov/bills/HB1234",
        source_url: "https://mgaleg.maryland.gov/bills/HB1234",
        sway_locale_id: 1,
        related_articles: [sampleArticle],
    },
    sponsor: { full_name: "Sen. Smith" },
    user_vote: null,
    bill_score: { for: 42, against: 18, comparison_suppressed: false, voters_needed: 0 },
    organizations: [],
};

const fullBotmPayload = {
    id: 1,
    title: "Open Records Act",
    bill_number: "HB 1234",
    external_id: "HB1234",
    summary: "Featured bill summary describing public access legislation.",
    organizations: [],
    user_vote: null,
    bill_score: { for: 42, against: 18, comparison_suppressed: false, voters_needed: 0 },
    link: "https://mgaleg.maryland.gov/bills/HB1234",
    sponsor: { full_name: "Sen. Smith" },
    status: "In Committee",
    status_color: "#eab308",
    sway_locale_id: 1,
    related_articles: [sampleArticle],
};

const detailWithArticles = (related_articles: unknown) => ({
    data: { ...fullBillDetailPayload, bill: { ...fullBillDetailPayload.bill, related_articles } },
    loading: false,
    error: null,
    refresh: jest.fn(),
});

const makeBootstrap = (overrides: Record<string, unknown> = {}) => ({
    bootstrap: {
        locale: {
            id: 1,
            name: "Maryland",
            slug: "maryland",
            generic_portal_urls: { senate: "https://example.com/senate" },
        },
        sway_locales: [
            { id: 1, name: "Maryland", slug: "maryland" },
            { id: 2, name: "Baltimore City", slug: "baltimore-city" },
        ],
        bill_of_the_month: fullBotmPayload,
        ...overrides,
    },
    loading: false,
    error: null,
    refetch: jest.fn(),
    needsUpdate: false,
});

function findNodeByTestId(node: JsonNode | null | undefined, testID: string): JsonNode | null {
    if (!node || typeof node !== "object") return null;
    if (node.props?.testID === testID) return node;
    if (Array.isArray(node.children)) {
        for (const child of node.children) {
            if (typeof child === "object" && child !== null) {
                const found = findNodeByTestId(child as JsonNode, testID);
                if (found) return found;
            }
        }
    }
    return null;
}

function extractAllStrings(node: unknown, acc: string[] = []): string[] {
    if (node === null || node === undefined) return acc;
    if (typeof node === "string") {
        acc.push(node);
        return acc;
    }
    if (typeof node === "object" && "children" in (node as Record<string, unknown>)) {
        const children = (node as { children: unknown[] }).children;
        if (Array.isArray(children)) {
            for (const child of children) {
                extractAllStrings(child, acc);
            }
        }
    }
    return acc;
}

describe("Milestone 20 Challenge: Related News Articles In Mobile", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        mockUseSession.mockReturnValue({
            isAuthenticated: false,
            loading: false,
            signOut: jest.fn(),
            signOutAll: jest.fn(),
        });
        mockUseCastUserVote.mockReturnValue({
            submit: jest.fn(async () => ({})),
            isOnline: true,
        });
        mockUseFocusedSync.mockReturnValue({ refresh: jest.fn() });
        mockUseBootstrap.mockReturnValue(makeBootstrap());
    });

    afterEach(() => {
        openURLSpy.mockRestore();
        jest.clearAllMocks();
    });

    describe("Vector 1: Strict Empty State Zero-Node Invariant", () => {
        test("standalone component returns null and 0 native nodes for articles = []", () => {
            const { toJSON } = wrap(<RelatedNewsArticles articles={[]} />);
            expect(toJSON()).toBeNull();
        });

        test("standalone component returns null and 0 native nodes for articles = undefined", () => {
            const { toJSON } = wrap(<RelatedNewsArticles articles={undefined} />);
            expect(toJSON()).toBeNull();
        });

        test("standalone component returns null and 0 native nodes for articles = null", () => {
            const { toJSON } = wrap(<RelatedNewsArticles articles={null} />);
            expect(toJSON()).toBeNull();
        });

        test("BillDetailScreen: renders no blank FadeInItem and no 16px gap when articles is empty or missing", () => {
            mockUseBill.mockReturnValue({
                data: fullBillDetailPayload,
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            const renderedWithNews = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(renderedWithNews.getByTestId("tab-summaries"));
            const jsonWithNews = renderedWithNews.toJSON() as JsonNode;
            const containerWithNews = findNodeByTestId(jsonWithNews, "bill-detail-summaries") as JsonNode;
            const withNewsChildren = containerWithNews?.children ?? [];

            const payloadEmpty = {
                ...fullBillDetailPayload,
                bill: { ...fullBillDetailPayload.bill, related_articles: [] },
            };
            mockUseBill.mockReturnValue({
                data: payloadEmpty,
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            const renderedEmpty = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(renderedEmpty.getByTestId("tab-summaries"));
            const jsonEmpty = renderedEmpty.toJSON() as JsonNode;
            const containerEmpty = findNodeByTestId(jsonEmpty, "bill-detail-summaries") as JsonNode;
            const emptyChildren = containerEmpty?.children ?? [];

            const payloadNull = {
                ...fullBillDetailPayload,
                bill: { ...fullBillDetailPayload.bill, related_articles: null },
            };
            mockUseBill.mockReturnValue({
                data: payloadNull,
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            const renderedNull = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(renderedNull.getByTestId("tab-summaries"));
            const jsonNull = renderedNull.toJSON() as JsonNode;
            const containerNull = findNodeByTestId(jsonNull, "bill-detail-summaries") as JsonNode;
            const nullChildren = containerNull?.children ?? [];

            expect(withNewsChildren.length).toBe(2);
            expect(emptyChildren.length).toBe(1);
            expect(nullChildren.length).toBe(1);
            expect(withNewsChildren.length).toBe(emptyChildren.length + 1);
            expect(emptyChildren.length).toBe(nullChildren.length);

            expect(findNodeByTestId(jsonEmpty, "related-news-articles")).toBeNull();
            expect(findNodeByTestId(jsonNull, "related-news-articles")).toBeNull();

            for (const child of emptyChildren) {
                if (typeof child === "object" && child !== null) {
                    const c = child as JsonNode;
                    expect(c.children && c.children.length > 0).toBe(true);
                }
            }
        });

        test("BillOfTheMonthScreen: renders no blank FadeInItem and no 16px gap when articles is empty or missing", () => {
            mockUseBill.mockReturnValue(detailWithArticles([sampleArticle]));
            const renderedWithNews = wrap(
                <BillOfTheMonthScreen navigation={{ getParent: () => ({ navigate: jest.fn() }) } as never} />,
            );
            fireEvent.press(renderedWithNews.getByTestId("tab-summaries"));
            const jsonWithNews = renderedWithNews.toJSON() as JsonNode;
            const containerWithNews = findNodeByTestId(jsonWithNews, "botm-summaries") as JsonNode;
            const withNewsChildren = containerWithNews?.children ?? [];

            mockUseBill.mockReturnValue(detailWithArticles([]));
            const renderedEmpty = wrap(
                <BillOfTheMonthScreen navigation={{ getParent: () => ({ navigate: jest.fn() }) } as never} />,
            );
            fireEvent.press(renderedEmpty.getByTestId("tab-summaries"));
            const jsonEmpty = renderedEmpty.toJSON() as JsonNode;
            const containerEmpty = findNodeByTestId(jsonEmpty, "botm-summaries") as JsonNode;
            const emptyChildren = containerEmpty?.children ?? [];

            mockUseBill.mockReturnValue(detailWithArticles(null));
            const renderedNull = wrap(
                <BillOfTheMonthScreen navigation={{ getParent: () => ({ navigate: jest.fn() }) } as never} />,
            );
            fireEvent.press(renderedNull.getByTestId("tab-summaries"));
            const jsonNull = renderedNull.toJSON() as JsonNode;
            const containerNull = findNodeByTestId(jsonNull, "botm-summaries") as JsonNode;
            const nullChildren = containerNull?.children ?? [];

            expect(withNewsChildren.length).toBe(emptyChildren.length + 1);
            expect(emptyChildren.length).toBe(nullChildren.length);
            expect(findNodeByTestId(jsonEmpty, "related-news-articles")).toBeNull();
            expect(findNodeByTestId(jsonNull, "related-news-articles")).toBeNull();

            expect(findNodeByTestId(jsonEmpty, "org-positions-section")).not.toBeNull();
        });
    });

    describe("Vector 2: Textless Article Presentation Invariant", () => {
        test("approved articles without retrieved body text render title, outlet, author, and date normally", () => {
            const textlessArticle: RelatedNewsArticle = {
                id: 201,
                title: "Harbor Clean Energy Initiative Receives State Endorsement",
                outlet_name: "Chesapeake Bay Journal",
                author_name: "Timothy Alpert",
                published_at: "2026-03-20T08:15:00Z",
                article_kind: "reporting",
                match_kind: "direct",
                url: "https://example.com/harbor-clean-energy",
            };

            wrap(<RelatedNewsArticles articles={[textlessArticle]} />);

            const titleLink = screen.getByRole("link", {
                name: "Harbor Clean Energy Initiative Receives State Endorsement",
            });
            expect(titleLink).toBeTruthy();

            expect(screen.getByText("Chesapeake Bay Journal")).toBeTruthy();
            expect(screen.getByText("By Timothy Alpert")).toBeTruthy();
            expect(screen.getByText("March 20, 2026")).toBeTruthy();
            expect(screen.getByText("Direct coverage")).toBeTruthy();

            fireEvent.press(titleLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://example.com/harbor-clean-energy");
        });

        test("textless title/URL-only link with no author and no date renders title and outlet without errors", () => {
            const bareLinkArticle: RelatedNewsArticle = {
                id: 202,
                title: "Governor Signs Clean Water Executive Order",
                outlet_name: "Associated Press",
                author_name: null,
                published_at: null,
                article_kind: "reporting",
                match_kind: "context",
                url: "https://example.com/gov-order",
            };

            wrap(<RelatedNewsArticles articles={[bareLinkArticle]} />);

            expect(screen.getByText("Governor Signs Clean Water Executive Order")).toBeTruthy();
            expect(screen.getByText("Associated Press")).toBeTruthy();
            expect(screen.getByText("Context")).toBeTruthy();
            expect(screen.queryByText(/By /)).toBeNull();
            expect(screen.queryByText(/•/)).toBeNull();
        });
    });

    describe("Vector 3: Volumetric Stress & Extreme String Testing", () => {
        test("volumetric stress: array of 100 articles renders complete sequence without crash or item loss", () => {
            const hundredArticles: RelatedNewsArticle[] = Array.from({ length: 100 }, (_, i) => ({
                id: i + 1,
                title: `Civic Journalism Dispatch Issue #${i + 1}`,
                outlet_name: `Newsroom Alpha ${i % 5}`,
                author_name: `Journalist ${i}`,
                published_at: "2026-01-01T00:00:00Z",
                article_kind: i % 3 === 0 ? "op_ed" : i % 3 === 1 ? "editorial" : "reporting",
                match_kind: i % 2 === 0 ? "direct" : "context",
                url: `https://example.com/article-${i + 1}`,
            }));

            wrap(<RelatedNewsArticles articles={hundredArticles} />);

            const renderedLinks = screen.getAllByRole("link");
            expect(renderedLinks).toHaveLength(100);

            for (let i = 1; i <= 100; i++) {
                expect(screen.getByTestId(`related-article-${i}`)).toBeTruthy();
            }

            expect(renderedLinks[0].props.accessibilityLabel).toBe("Civic Journalism Dispatch Issue #1");
            expect(renderedLinks[99].props.accessibilityLabel).toBe("Civic Journalism Dispatch Issue #100");
        });

        test("extreme string stress: 5,000 character title renders without crashing", () => {
            const superLongTitle = "A".repeat(5000);
            const longArticle: RelatedNewsArticle = {
                id: 5001,
                title: superLongTitle,
                outlet_name: "The Long Read",
                author_name: "Lengthy Author",
                published_at: "2026-04-01T12:00:00Z",
                article_kind: "reporting",
                match_kind: "direct",
                url: "https://example.com/5000-char-story",
            };

            expect(() => {
                wrap(<RelatedNewsArticles articles={[longArticle]} />);
            }).not.toThrow();

            const link = screen.getByRole("link");
            expect(link.props.accessibilityLabel).toBe(superLongTitle);
        });

        test("missing optional fields: no 'undefined', 'null', or orphan bullets appear anywhere in rendered tree", () => {
            const articleWithNulls: RelatedNewsArticle = {
                id: 999,
                title: "Simple Wire Headline",
                outlet_name: "Reuters",
                author_name: null,
                published_at: null,
                article_kind: null,
                match_kind: "context",
                url: "https://example.com/wire-news",
            };

            const rendered = wrap(<RelatedNewsArticles articles={[articleWithNulls]} />);
            const json = rendered.toJSON();
            const allStrings = extractAllStrings(json);

            for (const str of allStrings) {
                expect(str.toLowerCase()).not.toContain("undefined");
                expect(str.toLowerCase()).not.toContain("null");
                expect(str.trim()).not.toBe("•");
            }
        });

        test("bullet separator formatting invariant across author and date presence combinations", () => {
            const both: RelatedNewsArticle = {
                ...sampleArticle,
                id: 1,
                author_name: "Jane Doe",
                published_at: "2026-06-01T00:00:00Z",
            };
            const r1 = wrap(<RelatedNewsArticles articles={[both]} />);
            const bullets1 = r1.getAllByText("•");
            expect(bullets1).toHaveLength(2);

            const authorOnly: RelatedNewsArticle = {
                ...sampleArticle,
                id: 2,
                author_name: "Jane Doe",
                published_at: null,
            };
            const r2 = wrap(<RelatedNewsArticles articles={[authorOnly]} />);
            const bullets2 = r2.getAllByText("•");
            expect(bullets2).toHaveLength(1);

            const dateOnly: RelatedNewsArticle = {
                ...sampleArticle,
                id: 3,
                author_name: null,
                published_at: "2026-06-01T00:00:00Z",
            };
            const r3 = wrap(<RelatedNewsArticles articles={[dateOnly]} />);
            const bullets3 = r3.getAllByText("•");
            expect(bullets3).toHaveLength(1);

            const neither: RelatedNewsArticle = {
                ...sampleArticle,
                id: 4,
                author_name: null,
                published_at: null,
            };
            const r4 = wrap(<RelatedNewsArticles articles={[neither]} />);
            expect(r4.queryAllByText("•")).toHaveLength(0);
        });

        test("malformed and invalid date strings do not crash and emit no stray bullets", () => {
            const badDates = ["invalid-date", "2026-99-99", "0000-00-00", "not-iso", ""];
            for (const badDate of badDates) {
                const article: RelatedNewsArticle = {
                    ...sampleArticle,
                    id: 99,
                    author_name: null,
                    published_at: badDate,
                };
                const r = wrap(<RelatedNewsArticles articles={[article]} />);
                expect(r.queryAllByText("•")).toHaveLength(0);
            }
        });

        test("adversarial string content renders cleanly as text", () => {
            const hostileArticle: RelatedNewsArticle = {
                id: 777,
                title: "<script>alert('pwned')</script> &amp; <b>bold</b> 🏛️ Transit Reform 🚀",
                outlet_name: "Emoji Times 🗞️ <iframe src='foo'>",
                author_name: "Hacker <img onerror=alert(1)>",
                published_at: "2026-07-04T12:00:00Z",
                article_kind: "reporting",
                match_kind: "direct",
                url: "https://example.com/safe-url",
            };

            wrap(<RelatedNewsArticles articles={[hostileArticle]} />);
            expect(
                screen.getByText("<script>alert('pwned')</script> &amp; <b>bold</b> 🏛️ Transit Reform 🚀"),
            ).toBeTruthy();
            expect(screen.getByText("Emoji Times 🗞️ <iframe src='foo'>")).toBeTruthy();
            expect(screen.getByText("By Hacker <img onerror=alert(1)>")).toBeTruthy();
        });

        test("refuses dangerous URL schemes by rendering non-pressable plain text", () => {
            const dangerousUrls = [
                "javascript:alert(document.cookie)",
                "data:text/html,<script>alert(1)</script>",
                "file:///etc/shadow",
                "intent://package.name/#Intent;scheme=test;end",
                "blob:https://example.com/guid",
                "about:blank",
                "https://admin:password@evil.com/leak",
            ];

            for (let i = 0; i < dangerousUrls.length; i++) {
                const article: RelatedNewsArticle = {
                    ...sampleArticle,
                    id: 1000 + i,
                    title: `Dangerous Link #${i}`,
                    url: dangerousUrls[i],
                };
                const r = wrap(<RelatedNewsArticles articles={[article]} />);
                expect(r.queryByRole("link", { name: `Dangerous Link #${i}` })).toBeNull();
                expect(r.getByText(`Dangerous Link #${i}`)).toBeTruthy();
            }
        });
    });

    describe("Vector 4: Ordering Preservation", () => {
        test("articles render in the exact sequence provided in the array", () => {
            const articleA: RelatedNewsArticle = { ...sampleArticle, id: 1, title: "Alpha News Article" };
            const articleB: RelatedNewsArticle = { ...sampleArticle, id: 2, title: "Beta News Article" };
            const articleC: RelatedNewsArticle = { ...sampleArticle, id: 3, title: "Gamma News Article" };

            const r1 = wrap(<RelatedNewsArticles articles={[articleA, articleB, articleC]} />);
            expect(r1.getAllByRole("link").map((l) => l.props.accessibilityLabel)).toEqual([
                "Alpha News Article",
                "Beta News Article",
                "Gamma News Article",
            ]);

            const r2 = wrap(<RelatedNewsArticles articles={[articleC, articleA, articleB]} />);
            expect(r2.getAllByRole("link").map((l) => l.props.accessibilityLabel)).toEqual([
                "Gamma News Article",
                "Alpha News Article",
                "Beta News Article",
            ]);

            const r3 = wrap(<RelatedNewsArticles articles={[articleB, articleC, articleA]} />);
            expect(r3.getAllByRole("link").map((l) => l.props.accessibilityLabel)).toEqual([
                "Beta News Article",
                "Gamma News Article",
                "Alpha News Article",
            ]);
        });
    });

    describe("Vector 5: Screen Invariant & Boundary Isolation", () => {
        test("BillDetailScreen: RelatedNewsArticles sits before org positions, outside summary and testimony", () => {
            mockUseBill.mockReturnValue({
                data: fullBillDetailPayload,
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            const rendered = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);

            const summaryNode = findNodeByTestId(rendered.toJSON() as JsonNode, "bill-summary-section");
            expect(summaryNode).not.toBeNull();
            expect(findNodeByTestId(summaryNode, "related-news-articles")).toBeNull();

            fireEvent.press(screen.getByTestId("tab-summaries"));

            const allTestIDs = screen.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);

            const newsIdx = allTestIDs.indexOf("related-news-articles");
            const orgIdx = allTestIDs.indexOf("org-positions-section");

            expect(newsIdx).toBeGreaterThan(-1);
            expect(orgIdx).toBeGreaterThan(-1);
            expect(newsIdx).toBeLessThan(orgIdx);

            fireEvent.press(screen.getByTestId("tab-votes"));
            const testimonyNode = findNodeByTestId(rendered.toJSON() as JsonNode, "take-next-step");
            expect(testimonyNode).not.toBeNull();
            expect(findNodeByTestId(testimonyNode, "related-news-articles")).toBeNull();
        });

        test("BillOfTheMonthScreen: RelatedNewsArticles sits before org positions, outside summary and testimony", () => {
            mockUseBill.mockReturnValue(detailWithArticles([sampleArticle]));
            const rendered = wrap(
                <BillOfTheMonthScreen navigation={{ getParent: () => ({ navigate: jest.fn() }) } as never} />,
            );

            const summaryNode = findNodeByTestId(rendered.toJSON() as JsonNode, "bill-summary-section");
            expect(summaryNode).not.toBeNull();
            expect(findNodeByTestId(summaryNode, "related-news-articles")).toBeNull();

            fireEvent.press(screen.getByTestId("tab-summaries"));

            const allTestIDs = screen.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);

            const newsIdx = allTestIDs.indexOf("related-news-articles");
            const orgIdx = allTestIDs.indexOf("org-positions-section");

            expect(newsIdx).toBeGreaterThan(-1);
            expect(orgIdx).toBeGreaterThan(-1);
            expect(newsIdx).toBeLessThan(orgIdx);

            fireEvent.press(screen.getByTestId("tab-votes"));
            const testimonyNode = findNodeByTestId(rendered.toJSON() as JsonNode, "take-next-step");
            expect(testimonyNode).not.toBeNull();
            expect(findNodeByTestId(testimonyNode, "related-news-articles")).toBeNull();
        });

        test("stale state synchronization: switching bills immediately updates related articles without ghost remnants", () => {
            const bill1 = {
                ...fullBillDetailPayload,
                bill: {
                    ...fullBillDetailPayload.bill,
                    id: 101,
                    title: "First Bill",
                    related_articles: [
                        { ...sampleArticle, id: 501, title: "Bill 101 Headline Alpha" },
                        { ...sampleArticle, id: 502, title: "Bill 101 Headline Beta" },
                    ],
                },
            };

            const bill2 = {
                ...fullBillDetailPayload,
                bill: {
                    ...fullBillDetailPayload.bill,
                    id: 102,
                    title: "Second Bill Without News",
                    related_articles: [],
                },
            };

            const bill3 = {
                ...fullBillDetailPayload,
                bill: {
                    ...fullBillDetailPayload.bill,
                    id: 103,
                    title: "Third Bill With Distinct News",
                    related_articles: [{ ...sampleArticle, id: 503, title: "Bill 103 Fresh Headline" }],
                },
            };

            mockUseBill.mockReturnValue({ data: bill1, loading: false, error: null, refresh: jest.fn() });
            const { rerender } = wrap(<BillDetailScreen route={{ params: { id: 101 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByText("Bill 101 Headline Alpha")).toBeTruthy();
            expect(screen.getByText("Bill 101 Headline Beta")).toBeTruthy();

            mockUseBill.mockReturnValue({ data: bill2, loading: false, error: null, refresh: jest.fn() });
            rerender(
                <ThemeProvider initialMode="light">
                    <BillDetailScreen route={{ params: { id: 102 } }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("Bill 101 Headline Alpha")).toBeNull();
            expect(screen.queryByText("Bill 101 Headline Beta")).toBeNull();
            expect(screen.queryByTestId("related-news-articles")).toBeNull();

            mockUseBill.mockReturnValue({ data: bill3, loading: false, error: null, refresh: jest.fn() });
            rerender(
                <ThemeProvider initialMode="light">
                    <BillDetailScreen route={{ params: { id: 103 } }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByText("Bill 103 Fresh Headline")).toBeTruthy();
            expect(screen.queryByText("Bill 101 Headline Alpha")).toBeNull();
        });
    });
});
