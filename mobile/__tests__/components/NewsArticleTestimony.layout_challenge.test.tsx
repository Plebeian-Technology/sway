// @lat: [[news-mobile-testimony#News mobile testimony]]
// @lat: [[news-mobile-testimony#Placement of published commentary inside support and oppose cards]]
// @lat: [[news-mobile-testimony#Clear visual demarcation and distinction from organization positions]]
// @lat: [[news-mobile-testimony#Attribution fidelity and institutional fallback]]
// @lat: [[news-mobile-testimony#URL safety and markdown citation parsing]]
// @lat: [[news-mobile-testimony#Zero-node suppression and screen lifecycle]]

const mockUseBill = jest.fn();
const mockUseFocusedSync = jest.fn();
const mockUseBootstrap = jest.fn();
const mockUseSession = jest.fn();
const mockUseCastUserVote = jest.fn();

jest.mock("../../src/hooks/useBill", () => ({
    useBill: () => mockUseBill(),
}));
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: (opts: unknown) => mockUseFocusedSync(opts),
}));
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => mockUseBootstrap(),
}));
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => mockUseSession(),
}));
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
jest.mock("../../src/components/SkeletonCard", () => {
    const ReactMod = require("react");
    const RNMod = require("react-native");
    return {
        SkeletonCard: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
        default: ({ testID }: { testID?: string }) =>
            ReactMod.createElement(RNMod.View, { testID: testID ?? "skeleton-card" }),
    };
});

import React from "react";
import { Linking } from "react-native";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { NewsArticleTestimony, getAttribution } from "../../src/components/NewsArticleTestimony";
import { OrgPositionsSection } from "../../src/components/OrgPositionsSection";
import BillDetailScreen from "../../src/screens/BillDetailScreen";
import BillOfTheMonthScreen from "../../src/screens/BillOfTheMonthScreen";
import type { NewsArticleTestimony as NewsArticleTestimonyType } from "../../src/types/bill";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

interface JsonNode {
    props?: { testID?: string; [key: string]: unknown };
    children?: unknown[] | null;
}

function collectAllText(node: unknown, acc: string[] = []): string[] {
    if (!node || typeof node !== "object") return acc;
    const n = node as { props?: { children?: unknown }; children?: unknown[] };
    if (typeof n.children === "string") {
        acc.push(n.children);
    } else if (Array.isArray(n.children)) {
        for (const child of n.children) {
            if (typeof child === "string") {
                acc.push(child);
            } else {
                collectAllText(child, acc);
            }
        }
    }
    return acc;
}

const baseBillPayload = {
    bill: {
        id: 42,
        title: "Comprehensive Public Transit and Mobility Act",
        bill_number: "HB 4200",
        external_id: "HB4200",
        status: "In Committee",
        status_color: "#3b82f6",
        summary:
            "A comprehensive bill allocating transportation infrastructure funding across multimodal transit networks.",
        link: "https://mgaleg.maryland.gov/bills/HB4200",
    },
    sponsor: { full_name: "Del. Jordan Taylor" },
    user_vote: { support: "for" },
    bill_score: { for: 150, against: 75 },
    organizations: [
        {
            id: 1,
            support: "FOR" as const,
            organization: { name: "Transit Riders Coalition" },
            summary: "Expanding bus lines and rail corridors enhances daily mobility.",
        },
        {
            id: 2,
            support: "AGAINST" as const,
            organization: { name: "Fiscal Responsibility League" },
            summary: "The project financing relies on speculative revenue forecasts.",
        },
    ],
};

const baseBotmBill = {
    id: 99,
    external_id: "SB990",
    external_version: "1",
    title: "Statewide Environmental Protection Act",
    summary: "Mandates stringent watershed emission standards and establishes municipal oversight councils.",
    summary_ai_unreviewed: false,
    link: "https://mgaleg.maryland.gov/bills/SB990",
    chamber: "Senate",
    category: "environment",
    status: "committee",
    active: true,
    scheduled_release_date_utc: null,
    audio_bucket_path: null,
    audio_by_line: null,
    vote_date_time_utc: null,
    introduced_date_time_utc: "2026-01-15T00:00:00Z",
    house_vote_date_time_utc: null,
    senate_vote_date_time_utc: null,
    vote: null,
    categories: ["Environment"],
    legislator_id: 11,
    sway_locale_id: 1,
    created_at: "2026-01-15T00:00:00Z",
};

const baseBotmBootstrapBill = { ...baseBotmBill, user_vote: null };

const baseBotmDetail = {
    sponsor: { full_name: "Sen. Eleanor Vance" },
    user_vote: null,
    bill_score: {
        id: 5,
        bill_id: 99,
        for: 85,
        against: 45,
        districts: [
            {
                bill_score_id: 5,
                district: { name: "MD1", number: 1, region_code: "MD" },
                for: 24,
                against: 12,
            },
            {
                bill_score_id: 5,
                district: { name: "MD2", number: 2, region_code: "MD" },
                for: 8,
                against: 14,
            },
        ],
    },
    organizations: [
        {
            id: 11,
            support: "FOR" as const,
            organization: { name: "Chesapeake Clean Water Action" },
            summary: "Essential protections for regional water quality.",
        },
        {
            id: 12,
            support: "AGAINST" as const,
            organization: { name: "Industrial Commerce Alliance" },
            summary: "Excessive compliance costs for small manufacturers.",
        },
    ],
};

const botmDetail = (billExtras: Record<string, unknown> = {}) => ({
    data: {
        ...baseBotmDetail,
        bill: { ...baseBotmBill, related_articles: [], news_testimonies: [], ...billExtras },
    },
    loading: false,
    error: null,
    refresh: jest.fn(),
});

const LOCALE_BALTIMORE = { id: 1, name: "baltimore-maryland-united_states" };
const SWAY_LOCALES_LIST = [
    { id: 1, name: "Baltimore City, MD" },
    { id: 2, name: "State of Maryland" },
];

function makeBootstrapConfig(overrides: Record<string, unknown> = {}) {
    return {
        bootstrap: {
            bill_of_the_month: baseBotmBootstrapBill,
            locale: LOCALE_BALTIMORE,
            sway_locales: SWAY_LOCALES_LIST,
            ...overrides,
        },
        loading: false,
        error: null,
        refetch: jest.fn(),
        needsUpdate: false,
    };
}

describe("NewsArticleTestimony Layout & Volumetric Challenge Suite", () => {
    let openURLSpy: jest.SpyInstance;

    beforeEach(() => {
        openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        mockUseBill.mockReset();
        mockUseFocusedSync.mockReset();
        mockUseBootstrap.mockReset();
        mockUseSession.mockReset();
        mockUseCastUserVote.mockReset();

        mockUseBootstrap.mockReturnValue(makeBootstrapConfig());
        mockUseBill.mockReturnValue(botmDetail());
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false, signOut: jest.fn() });
        mockUseCastUserVote.mockReturnValue({ submit: jest.fn(async () => ({})), isOnline: true, isResolved: true });
    });

    afterEach(() => {
        openURLSpy.mockRestore();
    });

    describe("1. Volumetric stress: 50+ testimonies rendering, ordering, and performance", () => {
        const TOTAL_TESTIMONIES = 60;
        const largeTestimonies: NewsArticleTestimonyType[] = Array.from({ length: TOTAL_TESTIMONIES }, (_, i) => {
            const isSupport = i < 30;
            const index = i + 1;
            return {
                id: 1000 + index,
                author_name: isSupport ? `Support Columnist ${index}` : `Oppose Analyst ${index}`,
                outlet_name: isSupport ? `Support Gazette ${index}` : `Oppose Tribune ${index}`,
                stance: isSupport ? ("support" as const) : ("oppose" as const),
                url: `https://example.com/opinions/volumetric-${index}`,
                argument: isSupport
                    ? `Support argument entry ${index}: Expanding civic infrastructure delivers measurable societal return.`
                    : `Oppose argument entry ${index}: Capital outlays exceed prudent statutory budgetary constraints.`,
            };
        });

        test("renders all 60 items directly with exact preserved array ordering within bounds", () => {
            const start = Date.now();
            wrap(<NewsArticleTestimony testimonies={largeTestimonies} />);
            const elapsed = Date.now() - start;

            expect(elapsed).toBeLessThan(3000);

            const badges = screen.getAllByText("News commentary");
            expect(badges).toHaveLength(60);

            const supportBadges = screen.getAllByText("Support");
            expect(supportBadges).toHaveLength(30);

            const opposeBadges = screen.getAllByText("Oppose");
            expect(opposeBadges).toHaveLength(30);

            const bylines = screen.getAllByText(/By (Support Columnist|Oppose Analyst)/);
            expect(bylines).toHaveLength(60);

            for (let i = 0; i < TOTAL_TESTIMONIES; i++) {
                const expectedName = i < 30 ? `By Support Columnist ${i + 1}` : `By Oppose Analyst ${i + 1}`;
                expect(bylines[i].props.children).toBe(expectedName);
            }
        });

        test("stance='support' filters exactly 30 support items in order and zero oppose items", () => {
            wrap(<NewsArticleTestimony testimonies={largeTestimonies} stance="support" />);

            const badges = screen.getAllByText("News commentary");
            expect(badges).toHaveLength(30);

            expect(screen.queryByText(/Oppose Analyst/)).toBeNull();
            expect(screen.queryByText(/Oppose Tribune/)).toBeNull();
            expect(screen.queryByText(/Oppose argument entry/)).toBeNull();

            const bylines = screen.getAllByText(/By Support Columnist/);
            expect(bylines).toHaveLength(30);
            for (let i = 0; i < 30; i++) {
                expect(bylines[i].props.children).toBe(`By Support Columnist ${i + 1}`);
            }
        });

        test("stance='oppose' filters exactly 30 oppose items in order and zero support items", () => {
            wrap(<NewsArticleTestimony testimonies={largeTestimonies} stance="oppose" />);

            const badges = screen.getAllByText("News commentary");
            expect(badges).toHaveLength(30);

            expect(screen.queryByText(/Support Columnist/)).toBeNull();
            expect(screen.queryByText(/Support Gazette/)).toBeNull();
            expect(screen.queryByText(/Support argument entry/)).toBeNull();

            const bylines = screen.getAllByText(/By Oppose Analyst/);
            expect(bylines).toHaveLength(30);
            for (let i = 0; i < 30; i++) {
                expect(bylines[i].props.children).toBe(`By Oppose Analyst ${i + 31}`);
            }
        });

        test("renders 60 volumetric testimonies through OrgPositionsSection inside respective cards", () => {
            wrap(<OrgPositionsSection positions={[]} newsTestimonies={largeTestimonies} />);

            const supportHeader = screen.getByText(PARITY_COPY.bill.content.whySupport);
            const opposeHeader = screen.getByText(PARITY_COPY.bill.content.whyOppose);
            expect(supportHeader).toBeTruthy();
            expect(opposeHeader).toBeTruthy();

            const commentaryBadges = screen.getAllByText("News commentary");
            expect(commentaryBadges).toHaveLength(60);

            expect(screen.getAllByText(/By Support Columnist/)).toHaveLength(30);
            expect(screen.getAllByText(/By Oppose Analyst/)).toHaveLength(30);
        });
    });

    describe("2. Extreme string stress: 5,000+ chars, markdown paragraphs, and extreme attribution", () => {
        test("renders 5,500+ character single argument string without error or truncation", () => {
            const longSentence =
                "The legislative mandate encompasses vital systemic transit infrastructure modernizations. ";
            const repetitions = Math.ceil(5500 / longSentence.length);
            const massiveArgument = longSentence.repeat(repetitions);
            expect(massiveArgument.length).toBeGreaterThan(5500);

            const extremeTestimony: NewsArticleTestimonyType = {
                id: 901,
                author_name: "Dr. Alexander Long-Formington III",
                outlet_name: "The Metropolitan In-Depth Review",
                stance: "support",
                url: "https://example.com/opinions/deep-dive",
                argument: massiveArgument,
            };

            wrap(<NewsArticleTestimony testimonies={[extremeTestimony]} stance="support" />);

            expect(screen.getByText("By Dr. Alexander Long-Formington III")).toBeTruthy();
            expect(screen.getByText("The Metropolitan In-Depth Review")).toBeTruthy();
            expect(screen.getByText("News commentary")).toBeTruthy();

            const renderedText = screen.getByText(new RegExp(`^${longSentence.slice(0, 40)}`));
            expect(renderedText).toBeTruthy();
            expect(screen.getByText(massiveArgument)).toBeTruthy();
        });

        test("renders multi-paragraph markdown with lists, blockquotes, bold/italic, and clickable links", () => {
            const multiParagraphMarkdown = [
                "### Civic Policy Assessment",
                "",
                "First paragraph detailing statutory considerations with **robust empirical evidence** and *crucial economic impacts*.",
                "",
                "Second paragraph referencing independent audits: review the [MTA Fiscal Audit Report](https://mta.maryland.gov/audit-2026) and [City Budget Analysis](https://baltimorecity.gov/budget-2026) for context.",
                "",
                "> Public infrastructure investments yield long-term societal resilience when audited transparently.",
                "",
                "Key legislative provisions evaluated:",
                "- Dedicated line-item funding safeguards",
                "- Quarterly public reporting requirements",
                "- Mandatory community stakeholder hearings",
                "",
                "Final concluding summary with reference to the [Office of Legislative Services](https://mgaleg.maryland.gov/ols).",
            ].join("\n");

            const markdownTestimony: NewsArticleTestimonyType = {
                id: 902,
                author_name: "Sarah Jenkins, J.D.",
                outlet_name: "Maryland Policy Quarterly",
                stance: "support",
                url: "https://mdpolicy.org/analysis/transit-oversight",
                argument: multiParagraphMarkdown,
            };

            wrap(<NewsArticleTestimony testimonies={[markdownTestimony]} stance="support" />);

            expect(screen.getByText(/First paragraph detailing statutory considerations/)).toBeTruthy();
            expect(
                screen.getByText(/Public infrastructure investments yield long-term societal resilience/),
            ).toBeTruthy();
            expect(screen.getByText(/Dedicated line-item funding safeguards/)).toBeTruthy();
            expect(screen.getByText(/Final concluding summary with reference to/)).toBeTruthy();

            const auditLink = screen.getByRole("link", { name: "MTA Fiscal Audit Report" });
            const cityBudgetLink = screen.getByRole("link", { name: "City Budget Analysis" });
            const olsLink = screen.getByRole("link", { name: "Office of Legislative Services" });

            expect(auditLink).toBeTruthy();
            expect(cityBudgetLink).toBeTruthy();
            expect(olsLink).toBeTruthy();

            fireEvent.press(auditLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://mta.maryland.gov/audit-2026");

            fireEvent.press(cityBudgetLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://baltimorecity.gov/budget-2026");

            fireEvent.press(olsLink);
            expect(openURLSpy).toHaveBeenCalledWith("https://mgaleg.maryland.gov/ols");
        });

        test("handles extreme author and outlet names: 500+ chars, unicode/emoji, and whitespace trimming", () => {
            const extremeAuthor = `Dr. 🏛️ ${"Supercalifragilisticexpialidocious".repeat(15)} 🌍`;
            const extremeOutlet = `The 📰 ${"ExtraordinarilyComprehensiveLongOutletName".repeat(10)} Press`;

            const extremeTestimony: NewsArticleTestimonyType = {
                id: 903,
                author_name: `   ${extremeAuthor}   `,
                outlet_name: `   ${extremeOutlet}   `,
                stance: "oppose",
                url: "https://example.com/opinions/extreme-attribution",
                argument: "Opposition argument under extreme attribution conditions.",
            };

            wrap(<NewsArticleTestimony testimonies={[extremeTestimony]} stance="oppose" />);

            expect(screen.getByText(`By ${extremeAuthor}`)).toBeTruthy();
            expect(screen.getByText(extremeOutlet)).toBeTruthy();
        });

        test("handles various case formats of editorial board without redundant duplication", () => {
            const cases: { outlet: string; expectedByline: string }[] = [
                {
                    outlet: "The Baltimore Sun Editorial Board",
                    expectedByline: "The Baltimore Sun Editorial Board",
                },
                {
                    outlet: "The Washington Post editorial board",
                    expectedByline: "The Washington Post editorial board",
                },
                {
                    outlet: "BALTIMORE BANNER EDITORIAL BOARD",
                    expectedByline: "BALTIMORE BANNER EDITORIAL BOARD",
                },
                {
                    outlet: "Annapolis Gazette",
                    expectedByline: "Annapolis Gazette Editorial Board",
                },
            ];

            const testimonies: NewsArticleTestimonyType[] = cases.map((c, i) => ({
                id: 910 + i,
                author_name: null,
                outlet_name: c.outlet,
                stance: "support",
                url: `https://example.com/ed-board-${i}`,
                argument: `Editorial argument for case ${i}`,
            }));

            wrap(<NewsArticleTestimony testimonies={testimonies} stance="support" />);

            for (const c of cases) {
                expect(screen.getAllByText(c.expectedByline).length).toBeGreaterThanOrEqual(1);
            }
            expect(screen.queryByText(/Editorial Board Editorial Board/i)).toBeNull();
        });

        test("getAttribution trims whitespace and handles null author", () => {
            expect(
                getAttribution({
                    id: 1,
                    author_name: "   Maya Angelou   ",
                    outlet_name: "National Review",
                    stance: "support",
                    url: "https://example.com",
                    argument: "Text",
                }),
            ).toEqual({
                authorByline: "By Maya Angelou",
                outletName: "National Review",
            });

            expect(
                getAttribution({
                    id: 2,
                    author_name: "",
                    outlet_name: "Maryland Gazette",
                    stance: "oppose",
                    url: "https://example.com",
                    argument: "Text",
                }),
            ).toEqual({
                authorByline: "Maryland Gazette Editorial Board",
                outletName: "Maryland Gazette",
            });
        });
    });

    describe("3. Stance isolation: strict segregation between support and oppose containers", () => {
        test("support testimonies NEVER leak into oppose cards, and oppose testimonies NEVER leak into support cards", () => {
            const mixedTestimonies: NewsArticleTestimonyType[] = [
                ...Array.from({ length: 5 }, (_, i) => ({
                    id: 2000 + i,
                    author_name: `Unique Support Author ${i}`,
                    outlet_name: `Support Chronicle ${i}`,
                    stance: "support" as const,
                    url: `https://support.example.com/${i}`,
                    argument: `EXCLUSIVE_SUPPORT_ARGUMENT_TOKEN_${i}`,
                })),
                ...Array.from({ length: 5 }, (_, i) => ({
                    id: 2100 + i,
                    author_name: `Unique Oppose Author ${i}`,
                    outlet_name: `Oppose Gazette ${i}`,
                    stance: "oppose" as const,
                    url: `https://oppose.example.com/${i}`,
                    argument: `EXCLUSIVE_OPPOSE_ARGUMENT_TOKEN_${i}`,
                })),
                {
                    id: 2201,
                    author_name: "Neutral Author",
                    outlet_name: "Neutral Wire",
                    stance: "neutral" as unknown as "support",
                    url: "https://neutral.example.com",
                    argument: "LEAK_NEUTRAL_ARGUMENT_TOKEN",
                },
                {
                    id: 2202,
                    author_name: "Abstain Author",
                    outlet_name: "Abstain Wire",
                    stance: "abstain" as unknown as "oppose",
                    url: "https://abstain.example.com",
                    argument: "LEAK_ABSTAIN_ARGUMENT_TOKEN",
                },
                {
                    id: 2203,
                    author_name: "Empty Arg Author",
                    outlet_name: "Empty Arg Wire",
                    stance: "support",
                    url: "https://empty.example.com",
                    argument: "   ",
                },
            ];

            const { toJSON } = wrap(
                <OrgPositionsSection
                    positions={[
                        { id: 1, support: "FOR", organization: { name: "Supporters Org" }, summary: "Org Support" },
                        { id: 2, support: "AGAINST", organization: { name: "Opponents Org" }, summary: "Org Oppose" },
                    ]}
                    newsTestimonies={mixedTestimonies}
                />,
            );

            const root = toJSON() as JsonNode;
            expect(root).toBeTruthy();

            const cards = (root.children ?? []).filter(
                (child) => typeof child === "object" && child !== null,
            ) as JsonNode[];
            expect(cards).toHaveLength(2);

            const supportCard = cards[0];
            const opposeCard = cards[1];

            const supportCardTexts = collectAllText(supportCard);
            const opposeCardTexts = collectAllText(opposeCard);

            const supportCardBlob = supportCardTexts.join(" ");
            const opposeCardBlob = opposeCardTexts.join(" ");

            expect(supportCardBlob).toContain(PARITY_COPY.bill.content.whySupport);
            expect(opposeCardBlob).toContain(PARITY_COPY.bill.content.whyOppose);

            for (let i = 0; i < 5; i++) {
                expect(supportCardBlob).toContain(`EXCLUSIVE_SUPPORT_ARGUMENT_TOKEN_${i}`);
                expect(supportCardBlob).toContain(`By Unique Support Author ${i}`);
                expect(opposeCardBlob).not.toContain(`EXCLUSIVE_SUPPORT_ARGUMENT_TOKEN_${i}`);
                expect(opposeCardBlob).not.toContain(`Unique Support Author ${i}`);
            }

            for (let i = 0; i < 5; i++) {
                expect(opposeCardBlob).toContain(`EXCLUSIVE_OPPOSE_ARGUMENT_TOKEN_${i}`);
                expect(opposeCardBlob).toContain(`By Unique Oppose Author ${i}`);
                expect(supportCardBlob).not.toContain(`EXCLUSIVE_OPPOSE_ARGUMENT_TOKEN_${i}`);
                expect(supportCardBlob).not.toContain(`Unique Oppose Author ${i}`);
            }

            expect(supportCardBlob).not.toContain("LEAK_NEUTRAL_ARGUMENT_TOKEN");
            expect(opposeCardBlob).not.toContain("LEAK_NEUTRAL_ARGUMENT_TOKEN");
            expect(supportCardBlob).not.toContain("LEAK_ABSTAIN_ARGUMENT_TOKEN");
            expect(opposeCardBlob).not.toContain("LEAK_ABSTAIN_ARGUMENT_TOKEN");
            expect(supportCardBlob).not.toContain("Empty Arg Wire");
            expect(opposeCardBlob).not.toContain("Empty Arg Wire");
        });
    });

    describe("4. Integration invariance across BillDetailScreen & BillOfTheMonthScreen data shapes", () => {
        const supportOnlyTestimonies: NewsArticleTestimonyType[] = [
            {
                id: 501,
                author_name: "Support Columnist Solo",
                outlet_name: "Solo Support Times",
                stance: "support",
                url: "https://example.com/solo-support",
                argument: "Solely positive arguments for transit investment.",
            },
        ];

        const opposeOnlyTestimonies: NewsArticleTestimonyType[] = [
            {
                id: 502,
                author_name: null,
                outlet_name: "Solo Oppose Times",
                stance: "oppose",
                url: "https://example.com/solo-oppose",
                argument: "Solely critical fiscal arguments on project feasibility.",
            },
        ];

        test("BillDetailScreen: renders cleanly when news_testimonies is undefined", () => {
            const payload = {
                ...baseBillPayload,
                bill: { ...baseBillPayload.bill, news_testimonies: undefined },
            };
            mockUseBill.mockReturnValue({ data: payload, loading: false, error: null, refresh: jest.fn() });

            wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByTestId("bill-detail-scroll")).toBeTruthy();
            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("News commentary")).toBeNull();
        });

        test("BillDetailScreen: renders cleanly when news_testimonies is null", () => {
            const payload = {
                ...baseBillPayload,
                bill: { ...baseBillPayload.bill, news_testimonies: null },
            };
            mockUseBill.mockReturnValue({ data: payload, loading: false, error: null, refresh: jest.fn() });

            wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByText("News commentary")).toBeNull();
            expect(screen.getByText("Transit Riders Coalition")).toBeTruthy();
            expect(screen.getByText("Fiscal Responsibility League")).toBeTruthy();
        });

        test("BillDetailScreen: renders cleanly when news_testimonies is empty array", () => {
            const payload = {
                ...baseBillPayload,
                bill: { ...baseBillPayload.bill, news_testimonies: [] },
            };
            mockUseBill.mockReturnValue({ data: payload, loading: false, error: null, refresh: jest.fn() });

            wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("News commentary")).toBeNull();
        });

        test("BillDetailScreen: renders support-only testimony without corrupting oppose card empty state", () => {
            const payload = {
                ...baseBillPayload,
                organizations: [
                    {
                        id: 1,
                        support: "FOR" as const,
                        organization: { name: "Transit Riders Coalition" },
                        summary: "Expanding bus lines and rail corridors enhances daily mobility.",
                    },
                ],
                bill: { ...baseBillPayload.bill, news_testimonies: supportOnlyTestimonies },
            };
            mockUseBill.mockReturnValue({ data: payload, loading: false, error: null, refresh: jest.fn() });

            wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByText("By Support Columnist Solo")).toBeTruthy();
            expect(screen.getByText("Solely positive arguments for transit investment.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);

            expect(screen.getByText("Transit Riders Coalition")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.org.noOppose)).toBeTruthy();
            expect(screen.queryByText(PARITY_COPY.org.noSupport)).toBeNull();
        });

        test("BillDetailScreen: renders oppose-only testimony without corrupting support card empty state", () => {
            const payload = {
                ...baseBillPayload,
                organizations: [
                    {
                        id: 2,
                        support: "AGAINST" as const,
                        organization: { name: "Fiscal Responsibility League" },
                        summary: "The project financing relies on speculative revenue forecasts.",
                    },
                ],
                bill: { ...baseBillPayload.bill, news_testimonies: opposeOnlyTestimonies },
            };
            mockUseBill.mockReturnValue({ data: payload, loading: false, error: null, refresh: jest.fn() });

            wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByText("Solo Oppose Times Editorial Board")).toBeTruthy();
            expect(screen.getByText("Solely critical fiscal arguments on project feasibility.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);

            expect(screen.getByText("Fiscal Responsibility League")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.org.noSupport)).toBeTruthy();
            expect(screen.queryByText(PARITY_COPY.org.noOppose)).toBeNull();
        });

        test("BillOfTheMonthScreen: renders cleanly when news_testimonies is undefined, empty, or populated", () => {
            mockUseBill.mockReturnValue(botmDetail({ news_testimonies: undefined }));
            const { rerender } = wrap(<BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("News commentary")).toBeNull();

            mockUseBill.mockReturnValue(botmDetail({ news_testimonies: supportOnlyTestimonies }));
            rerender(
                <ThemeProvider initialMode="light">
                    <BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByText("By Support Columnist Solo")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);

            mockUseBill.mockReturnValue(botmDetail({ news_testimonies: [] }));
            rerender(
                <ThemeProvider initialMode="light">
                    <BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("News commentary")).toBeNull();
        });
    });

    describe("5. Existing vertical fiber order preservation", () => {
        test("BillDetailScreen: preserves vertical order when both related_articles and news_testimonies are present", () => {
            const payloadWithBoth = {
                ...baseBillPayload,
                bill: {
                    ...baseBillPayload.bill,
                    related_articles: [
                        {
                            id: 11,
                            title: "Transit Network Plan Moves Forward",
                            outlet_name: "The Baltimore Sun",
                            author_name: "Staff Writer",
                            published_at: "2026-04-14T10:00:00Z",
                            article_kind: "reporting",
                            match_kind: "direct",
                            url: "https://example.com/news/11",
                        },
                    ],
                    news_testimonies: [
                        {
                            id: 301,
                            author_name: "Columnist A",
                            outlet_name: "The Daily Review",
                            stance: "support" as const,
                            url: "https://example.com/op/301",
                            argument: "Supportive editorial prose.",
                        },
                    ],
                },
            };

            mockUseBill.mockReturnValue({ data: payloadWithBoth, loading: false, error: null, refresh: jest.fn() });
            const rendered = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);

            fireEvent.press(screen.getByTestId("tab-summaries"));

            const ORDER = ["related-news-articles", "org-positions-section"];
            const allTestIDs = rendered.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);

            const positions = ORDER.map((id) => allTestIDs.indexOf(id));
            for (let i = 0; i < ORDER.length; i++) {
                expect(positions[i]).toBeGreaterThan(-1);
            }
            for (let i = 1; i < positions.length; i++) {
                expect(positions[i]).toBeGreaterThan(positions[i - 1]);
            }
        });

        test("BillDetailScreen: preserves vertical order when related_articles is absent but news_testimonies is present", () => {
            const payloadWithTestimonyOnly = {
                ...baseBillPayload,
                bill: {
                    ...baseBillPayload.bill,
                    related_articles: [],
                    news_testimonies: [
                        {
                            id: 302,
                            author_name: "Columnist B",
                            outlet_name: "The Morning Herald",
                            stance: "oppose" as const,
                            url: "https://example.com/op/302",
                            argument: "Critical editorial prose.",
                        },
                    ],
                },
            };

            mockUseBill.mockReturnValue({
                data: payloadWithTestimonyOnly,
                loading: false,
                error: null,
                refresh: jest.fn(),
            });
            const rendered = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);

            fireEvent.press(screen.getByTestId("tab-summaries"));

            const ORDER = ["org-positions-section"];
            const allTestIDs = rendered.UNSAFE_root.findAll(
                (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
            ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);

            expect(allTestIDs).not.toContain("related-news-articles");

            const positions = ORDER.map((id) => allTestIDs.indexOf(id));
            for (let i = 0; i < ORDER.length; i++) {
                expect(positions[i]).toBeGreaterThan(-1);
            }
            for (let i = 1; i < positions.length; i++) {
                expect(positions[i]).toBeGreaterThan(positions[i - 1]);
            }
        });

        test("BillOfTheMonthScreen: preserves vertical order with news testimonies", () => {
            mockUseBill.mockReturnValue(
                botmDetail({
                    related_articles: [
                        {
                            id: 55,
                            title: "Watershed Bill Clears Senate",
                            outlet_name: "Chesapeake Bay News",
                            author_name: "Reporter C",
                            published_at: "2026-05-01T12:00:00Z",
                            article_kind: "reporting",
                            match_kind: "direct",
                            url: "https://example.com/news/55",
                        },
                    ],
                    news_testimonies: [
                        {
                            id: 701,
                            author_name: "Environmentalist D",
                            outlet_name: "Eco Digest",
                            stance: "support" as const,
                            url: "https://example.com/op/701",
                            argument: "Crucial environmental protection arguments.",
                        },
                    ],
                }),
            );
            const rendered = wrap(<BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />);

            const ORDER_BY_TAB = {
                "tab-bill": ["botm-hero", "bill-summary-section"],
                "tab-votes": ["vote-panel", "bill-score-bar", "district-votes-panel", "take-next-step"],
                "tab-summaries": ["related-news-articles", "org-positions-section"],
            };

            Object.entries(ORDER_BY_TAB).forEach(([tab, order]) => {
                fireEvent.press(screen.getByTestId(tab));
                const allTestIDs = rendered.UNSAFE_root.findAll(
                    (node: { props: Record<string, unknown> }) => typeof node.props.testID === "string",
                ).map((node: { props: Record<string, unknown> }) => node.props.testID as string);

                const positions = order.map((id) => allTestIDs.indexOf(id));
                for (let i = 0; i < order.length; i++) {
                    expect(positions[i]).toBeGreaterThan(-1);
                }
                for (let i = 1; i < positions.length; i++) {
                    expect(positions[i]).toBeGreaterThan(positions[i - 1]);
                }
            });
        });
    });

    describe("6. Route and locale transitions: state hygiene and zero lingering nodes", () => {
        test("BillDetailScreen: transitions between bills clear old testimony nodes and render fresh data without leakage", () => {
            const bill42Payload = {
                ...baseBillPayload,
                bill: {
                    ...baseBillPayload.bill,
                    id: 42,
                    news_testimonies: [
                        {
                            id: 4201,
                            author_name: "Bill 42 Exclusive Pundit",
                            outlet_name: "Outlet 42",
                            stance: "support" as const,
                            url: "https://example.com/4201",
                            argument: "Unique argument 42 specifically for bill 42.",
                        },
                    ],
                },
            };

            const bill43Payload = {
                ...baseBillPayload,
                bill: {
                    ...baseBillPayload.bill,
                    id: 43,
                    news_testimonies: [],
                },
            };

            const bill44Payload = {
                ...baseBillPayload,
                bill: {
                    ...baseBillPayload.bill,
                    id: 44,
                    news_testimonies: [
                        {
                            id: 4401,
                            author_name: "Bill 44 Exclusive Pundit",
                            outlet_name: "Outlet 44",
                            stance: "oppose" as const,
                            url: "https://example.com/4401",
                            argument: "Unique argument 44 specifically for bill 44.",
                        },
                    ],
                },
            };

            mockUseBill.mockReturnValue({ data: bill42Payload, loading: false, error: null, refresh: jest.fn() });
            const { rerender } = wrap(<BillDetailScreen route={{ params: { id: 42 } }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByText("By Bill 42 Exclusive Pundit")).toBeTruthy();
            expect(screen.getByText("Unique argument 42 specifically for bill 42.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);

            mockUseBill.mockReturnValue({ data: bill43Payload, loading: false, error: null, refresh: jest.fn() });
            rerender(
                <ThemeProvider initialMode="light">
                    <BillDetailScreen route={{ params: { id: 43 } }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));
            expect(screen.getByTestId("org-positions-section")).toBeTruthy();

            expect(screen.queryByText("By Bill 42 Exclusive Pundit")).toBeNull();
            expect(screen.queryByText("Unique argument 42 specifically for bill 42.")).toBeNull();
            expect(screen.queryByText("News commentary")).toBeNull();

            mockUseBill.mockReturnValue({ data: bill44Payload, loading: false, error: null, refresh: jest.fn() });
            rerender(
                <ThemeProvider initialMode="light">
                    <BillDetailScreen route={{ params: { id: 44 } }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.queryByText("By Bill 42 Exclusive Pundit")).toBeNull();
            expect(screen.getByText("By Bill 44 Exclusive Pundit")).toBeTruthy();
            expect(screen.getByText("Unique argument 44 specifically for bill 44.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);
        });

        test("BillOfTheMonthScreen: transitions between locales cleanly replace featured bill and eliminate prior testimony", () => {
            const botmLocale1 = { ...baseBotmBootstrapBill, id: 101, title: "Locale 1 Clean Energy Bill" };
            const botmLocale2 = { ...baseBotmBootstrapBill, id: 201, title: "Locale 2 Taxation Bill" };

            mockUseBill.mockReturnValue(
                botmDetail({
                    id: 101,
                    title: "Locale 1 Clean Energy Bill",
                    news_testimonies: [
                        {
                            id: 881,
                            author_name: "Locale 1 Commentator",
                            outlet_name: "City Journal",
                            stance: "support" as const,
                            url: "https://example.com/loc1",
                            argument: "Locale 1 exclusive opinion commentary text.",
                        },
                    ],
                }),
            );
            mockUseBootstrap.mockReturnValue(makeBootstrapConfig({ bill_of_the_month: botmLocale1 }));
            const { rerender } = wrap(<BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />);
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByText("By Locale 1 Commentator")).toBeTruthy();
            expect(screen.getByText("Locale 1 exclusive opinion commentary text.")).toBeTruthy();
            expect(screen.getAllByText("News commentary")).toHaveLength(1);

            mockUseBill.mockReturnValue(botmDetail({ id: 201, title: "Locale 2 Taxation Bill", news_testimonies: [] }));
            mockUseBootstrap.mockReturnValue(makeBootstrapConfig({ bill_of_the_month: botmLocale2 }));
            rerender(
                <ThemeProvider initialMode="light">
                    <BillOfTheMonthScreen navigation={{ navigate: jest.fn() }} />
                </ThemeProvider>,
            );
            fireEvent.press(screen.getByTestId("tab-summaries"));

            expect(screen.getByTestId("org-positions-section")).toBeTruthy();
            expect(screen.queryByText("By Locale 1 Commentator")).toBeNull();
            expect(screen.queryByText("Locale 1 exclusive opinion commentary text.")).toBeNull();
            expect(screen.queryByText("News commentary")).toBeNull();
        });
    });
});
