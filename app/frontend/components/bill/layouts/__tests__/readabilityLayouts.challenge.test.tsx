// @lat: [[theme-driven-bill-layout-selection#Theme-driven layout selection on Bill.tsx and Bills.tsx#Monochrome, Service Manual, and Swiss Notice bill detail layouts]]

import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import * as React from "react";
import { Suspense } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { THEMES, type ThemeId } from "app/frontend/styles/themes";
import DefaultBillLayout from "app/frontend/components/bill/layouts/DefaultBillLayout";
import { billLayoutFor } from "app/frontend/components/bill/layouts/index";
import MonochromeBillLayout from "app/frontend/components/bill/layouts/MonochromeBillLayout";

vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
    usePage: () => ({
        props: {
            user: null,
            pending_vote: null,
            errors: {},
        },
    }),
    Link: ({ children, href }: { children?: React.ReactNode; href?: string }) => <a href={href}>{children}</a>,
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post: vi.fn<() => void>(),
            processing: false,
            transform: vi.fn<(callback: (data: unknown) => unknown) => void>(),
            reset: vi.fn<() => void>(),
            errors: {},
        };
    },
}));

vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<(message: string) => Promise<boolean>>(),
}));
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({
    useOffline: () => ({ isOnline: true, assertBanner: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocaleSlug: () => "baltimore",
    useSwayLocale: () => [null, vi.fn<() => void>()],
    useSwayLocales: () => ({ options: [] }),
}));
vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({
    default: () => <div data-testid="email-legislators" />,
}));

await Promise.all([
    import("app/frontend/components/bill/layouts/BannerBillLayout"),
    import("app/frontend/components/bill/layouts/BallotBillLayout"),
    import("app/frontend/components/bill/layouts/CornerstoreBillLayout"),
    import("app/frontend/components/bill/layouts/MonochromeBillLayout"),
    import("app/frontend/components/bill/layouts/ServiceManualBillLayout"),
    import("app/frontend/components/bill/layouts/SwissGridBillLayout"),
]);

const SAMPLE_BILL: sway.IBill = {
    id: 42,
    external_id: "26-0500",
    title: "Neighborhood Air Quality Monitoring Act FOR the purpose of installing air quality sensors across industrial buffer zones; mandating quarterly reporting; and establishing community alert thresholds.",
    summary: "Mandates air quality sensors across industrial buffer zones.",
    chamber: "council",
    categories: ["Environment", "Health"],
    legislator_id: 10,
    active: true,
} as unknown as sway.IBill;

const SAMPLE_SPONSOR: sway.ILegislator = {
    id: 10,
    full_name: "Councilmember Jane Doe",
} as sway.ILegislator;

const READABILITY_THEMES: { themeId: ThemeId; layoutName: string }[] = [
    { themeId: "monochrome", layoutName: "MonochromeBillLayout" },
    { themeId: "service-manual", layoutName: "ServiceManualBillLayout" },
    { themeId: "swiss-grid", layoutName: "SwissGridBillLayout" },
];

describe("Empirical Challenge: Readability Bill Detail Layouts", () => {
    beforeEach(() => vi.clearAllMocks());
    afterEach(cleanup);

    describe("1. Distinct Layout Mapping for all 7 Themes", () => {
        it("resolves distinct, unique layout instances across all 7 registered themes", () => {
            const allThemeIds: ThemeId[] = THEMES.map((t) => t.id);
            expect(allThemeIds).toHaveLength(7);
            expect(allThemeIds).toContain("sway");
            expect(allThemeIds).toContain("banner");
            expect(allThemeIds).toContain("ballot");
            expect(allThemeIds).toContain("cornerstore");
            expect(allThemeIds).toContain("monochrome");
            expect(allThemeIds).toContain("service-manual");
            expect(allThemeIds).toContain("swiss-grid");

            const layouts = allThemeIds.map((id) => billLayoutFor(id));

            expect(billLayoutFor("sway")).toBe(DefaultBillLayout);

            for (const themeId of [
                "banner",
                "ballot",
                "cornerstore",
                "monochrome",
                "service-manual",
                "swiss-grid",
            ] as ThemeId[]) {
                expect(billLayoutFor(themeId)).not.toBe(DefaultBillLayout);
            }

            const distinctLayouts = new Set(layouts);
            expect(distinctLayouts.size).toBe(7);
        });
    });

    describe.each(READABILITY_THEMES)("2. Invariant & Boundary Stress: %s theme ($layoutName)", ({ themeId }) => {
        const renderTestLayout = (overrideProps: Partial<React.ComponentProps<typeof MonochromeBillLayout>> = {}) => {
            const Layout = billLayoutFor(themeId);
            return render(
                <Suspense fallback={<div data-testid="loading" />}>
                    <Layout
                        bill={SAMPLE_BILL}
                        sponsor={SAMPLE_SPONSOR}
                        organizations={[]}
                        isAwaitingScoreUpdate={false}
                        {...overrideProps}
                    />
                </Suspense>,
            );
        };

        it("Invariant 1: Renders external bill ID", async () => {
            renderTestLayout();
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());
            expect(screen.getAllByText(/26-0500/).length).toBeGreaterThan(0);
        });

        it("Invariant 2 & 3: Short title in headline and full title in As Introduced", async () => {
            renderTestLayout();
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            const headline = screen.getByTestId("bill-title");
            expect(headline.textContent).toContain("Neighborhood Air Quality Monitoring Act");
            expect(headline.textContent).not.toContain("FOR the purpose of");

            expect(document.body.textContent).toContain(
                "installing air quality sensors across industrial buffer zones",
            );
        });

        it("Invariant 4: Support and Oppose vote choices are operable", async () => {
            renderTestLayout();
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            const supportBtn = screen.getByRole("button", { name: /Support this legislation/i });
            const opposeBtn = screen.getByRole("button", { name: /Oppose this legislation/i });

            expect(supportBtn).toBeEnabled();
            expect(opposeBtn).toBeEnabled();
        });

        it("Invariant 5 & 6: Zero-node when empty and populated when articles/testimonies are provided", async () => {
            const { unmount } = renderTestLayout({
                bill: { ...SAMPLE_BILL, related_articles: [], news_testimonies: [] },
            });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());
            expect(screen.queryByTestId("related-news-articles")).toBeNull();
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            unmount();

            renderTestLayout({
                bill: {
                    ...SAMPLE_BILL,
                    related_articles: [
                        {
                            id: 901,
                            title: "Sensors Deployment Plan Announced",
                            url: "https://example.com/sensors",
                            outlet_name: "Civic Daily",
                            published_at: "2026-04-10T12:00:00Z",
                            article_kind: "reporting",
                            match_kind: "direct",
                        } as sway.INewsArticle,
                    ],
                    news_testimonies: [
                        {
                            id: 902,
                            author_name: "Elena Rostova",
                            outlet_name: "Clean Air Journal",
                            url: "https://example.com/opinion/elena",
                            stance: "support",
                            argument: "Real-time monitoring directly protects children in adjacent residential zones.",
                        } as sway.INewsArticleTestimony,
                    ],
                },
            });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(screen.getByTestId("related-news-articles")).toBeInTheDocument();
            expect(screen.getByText("Sensors Deployment Plan Announced")).toBeInTheDocument();
            expect(screen.getByTestId("news-article-testimony")).toBeInTheDocument();
            expect(screen.getByText(/Real-time monitoring directly protects/)).toBeInTheDocument();
        });

        it("Stress: Survives title without 'FOR the purpose of' boilerplate cleanly", async () => {
            const shortBill = {
                ...SAMPLE_BILL,
                title: "Clean Water Protection Initiative",
            };
            renderTestLayout({ bill: shortBill });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            const heading = screen.getByTestId("bill-title");
            expect(heading.textContent).toContain("Clean Water Protection Initiative");
            expect(document.body.textContent).toContain("Clean Water Protection Initiative");
        });

        it("Stress: Missing optional properties (null sponsor, undefined categories, undefined chamber)", async () => {
            const strippedBill = {
                ...SAMPLE_BILL,
                chamber: undefined,
                categories: undefined,
                legislator_id: 0,
            } as unknown as sway.IBill;
            renderTestLayout({ bill: strippedBill, sponsor: undefined });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(screen.getByTestId("bill-title")).toBeInTheDocument();
            expect(screen.queryByText("Councilmember Jane Doe")).toBeNull();
        });

        it("Stress: Zero-score edge case handles 0% votes without NaN rendering", async () => {
            const zeroScore = {
                for: 0,
                against: 0,
            } as unknown as sway.IBillScore;

            renderTestLayout({ bill_score: zeroScore });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(document.body.textContent).not.toContain("NaN");
            expect(screen.getAllByText(/\b0\b|\b0%/).length).toBeGreaterThan(0);
        });

        it("Stress: Extreme vote tallies handle large numbers with comma formatting", async () => {
            const extremeScore = {
                for: 1250000,
                against: 850000,
            } as unknown as sway.IBillScore;

            renderTestLayout({ bill_score: extremeScore });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(document.body.textContent).toContain("1,250,000");
            expect(document.body.textContent).toContain("850,000");
        });

        it("Stress: Inactive bill with user vote suppresses EmailLegislatorsModal", async () => {
            const inactiveBill = { ...SAMPLE_BILL, active: false };
            const userVote = { id: 1, bill_id: 42, support: Support.For } as unknown as sway.IUserVote;

            renderTestLayout({ bill: inactiveBill, user_vote: userVote });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(screen.queryByTestId("email-legislators")).toBeNull();
        });

        it("Stress: Active bill with user vote displays EmailLegislatorsModal", async () => {
            const activeBill = { ...SAMPLE_BILL, active: true };
            const userVote = { id: 1, bill_id: 42, support: Support.For } as unknown as sway.IUserVote;

            renderTestLayout({ bill: activeBill, user_vote: userVote });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            expect(screen.getByTestId("email-legislators")).toBeInTheDocument();
        });

        it("renders ShareBillButton both when user_vote is present and when user_vote is undefined", async () => {
            const { unmount } = renderTestLayout({ user_vote: undefined });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());
            expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
            unmount();

            const userVote = { id: 1, bill_id: 42, support: Support.For } as unknown as sway.IUserVote;
            renderTestLayout({ user_vote: userVote });
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());
            expect(screen.getByTestId("btn-share-bill")).toBeInTheDocument();
        });
    });

    describe("3. SwissGrid Specialized Split Stance Verification", () => {
        it("splits testimonies strictly between Why Support and Why Oppose rows", async () => {
            const Layout = billLayoutFor("swiss-grid");
            const billWithSplitTestimonies = {
                ...SAMPLE_BILL,
                news_testimonies: [
                    {
                        id: 701,
                        author_name: "Pro-Sensor Researcher",
                        outlet_name: "Urban Science",
                        url: "https://example.com/pro",
                        stance: "support",
                        argument: "Precision monitoring pinpoints localized particulate spikes.",
                    } as sway.INewsArticleTestimony,
                    {
                        id: 702,
                        author_name: "Anti-Regulation Analyst",
                        outlet_name: "Fiscal Review",
                        url: "https://example.com/anti",
                        stance: "oppose",
                        argument: "Compliance cost burdens mid-sized manufacturing operators.",
                    } as sway.INewsArticleTestimony,
                ],
            };

            render(
                <Suspense fallback={<div data-testid="loading" />}>
                    <Layout
                        bill={billWithSplitTestimonies}
                        sponsor={SAMPLE_SPONSOR}
                        organizations={[]}
                        isAwaitingScoreUpdate={false}
                    />
                </Suspense>,
            );
            await waitFor(() => expect(screen.queryByTestId("loading")).toBeNull());

            const whySupportHeading = screen.getByText(PARITY_COPY.bill.content.whySupport);
            const supportRow = whySupportHeading.closest(".sgb-row") as HTMLElement;
            expect(supportRow).toBeInTheDocument();
            expect(within(supportRow).getByText(/Precision monitoring pinpoints/)).toBeInTheDocument();
            expect(within(supportRow).queryByText(/Compliance cost burdens/)).toBeNull();

            const whyOpposeHeading = screen.getByText(PARITY_COPY.bill.content.whyOppose);
            const opposeRow = whyOpposeHeading.closest(".sgb-row") as HTMLElement;
            expect(opposeRow).toBeInTheDocument();
            expect(within(opposeRow).getByText(/Compliance cost burdens/)).toBeInTheDocument();
            expect(within(opposeRow).queryByText(/Precision monitoring pinpoints/)).toBeNull();
        });
    });
});
