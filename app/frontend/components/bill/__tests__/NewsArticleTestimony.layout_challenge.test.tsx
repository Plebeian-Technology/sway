// @lat: [[news-web-testimony#News web testimony]]
// @lat: [[news-web-testimony#Why published opinion commentary sits alongside support and oppose reasoning]]
// @lat: [[news-web-testimony#Clear demarcation from legislative hearing testimony and organizational positions]]
// @lat: [[news-web-testimony#Attribution fidelity and secure citation navigation]]
// @lat: [[news-web-testimony#Multi-theme layout integration]]

import { cleanup, render, screen, within, waitFor } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import type { ThemeId } from "app/frontend/styles/themes";

let mockActiveTheme: ThemeId = "sway";

vi.mock("@inertiajs/react", () => ({
    usePage: () => ({
        props: {
            user: null,
            pending_vote: null,
            errors: {},
            sway_locale: {
                generic_portal_urls: ["https://baltimore.legistar.com"],
            },
        },
    }),
    Link: ({ children, href, ...props }: { children?: React.ReactNode; href?: string }) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
    useForm: function useForm(initial: Record<string, unknown>) {
        const [data, setDataState] = React.useState<Record<string, unknown>>(initial ?? {});
        const setData = (key: string, value: unknown) => setDataState((prev) => ({ ...prev, [key]: value }));
        return {
            data,
            setData,
            post: vi.fn<() => void>(),
            processing: false,
            transform: vi.fn<(cb: (d: unknown) => unknown) => void>(),
            reset: vi.fn<() => void>(),
            errors: {},
        };
    },
    usePoll: vi.fn<(interval: number, options: { only: string[] }) => void>(),
    router: { reload: vi.fn<(opts?: Record<string, unknown>) => void>() },
}));

vi.mock("app/frontend/hooks/useActiveThemeId", () => ({
    useActiveThemeId: () => mockActiveTheme,
}));

vi.mock("app/frontend/hooks/useLocales", () => ({
    useLocaleName: () => "baltimore",
    useLocale: () => [{ id: 1, name: "baltimore" }, vi.fn<() => void>(), null],
    useLocales: () => ({ options: [{ id: 1, name: "baltimore" }] }),
}));

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: () => false,
}));
vi.mock("app/frontend/hooks/useActionCableReconnect", () => ({
    useActionCableReconnect: vi.fn<() => void>(),
}));
vi.mock("app/frontend/hooks/usePullToRefresh", () => ({
    usePullToRefresh: vi.fn<() => void>(),
}));
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<(msg: string) => Promise<boolean>>(() => Promise.resolve(true)),
}));
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({
    useOffline: () => ({ isOnline: true, assertBanner: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({
    default: () => <div data-testid="mock-email-modal" />,
}));
vi.mock("app/frontend/components/bill/charts/BillChartsPanel", () => ({
    default: () => <div data-testid="mock-charts" />,
}));
vi.mock("app/frontend/components/bill/charts/BillAffinityPanel", () => ({
    default: () => <div data-testid="mock-affinity" />,
}));

import NewsArticleTestimony from "app/frontend/components/bill/NewsArticleTestimony";
import BillContent from "app/frontend/components/bill/BillContent";
import DefaultBillLayout from "app/frontend/components/bill/layouts/DefaultBillLayout";
import BallotBillLayout from "app/frontend/components/bill/layouts/BallotBillLayout";
import BannerBillLayout from "app/frontend/components/bill/layouts/BannerBillLayout";
import CornerstoreBillLayout from "app/frontend/components/bill/layouts/CornerstoreBillLayout";
import MonochromeBillLayout from "app/frontend/components/bill/layouts/MonochromeBillLayout";
import ServiceManualBillLayout from "app/frontend/components/bill/layouts/ServiceManualBillLayout";
import SwissGridBillLayout from "app/frontend/components/bill/layouts/SwissGridBillLayout";
import Bill from "app/frontend/pages/Bill";
import BillOfTheMonth from "app/frontend/pages/BillOfTheMonth";

const BASE_BILL: sway.IBill = {
    id: 101,
    external_id: "26-0042",
    title: "Urban Tree Canopy Protection Act",
    summary: "Requires commercial developers to preserve existing tree canopy or fund replacement planting.",
    chamber: "council",
    categories: ["Environment", "Planning"],
    legislator_id: 12,
} as sway.IBill;

const BASE_SPONSOR: sway.ILegislator = {
    id: 12,
    full_name: "Councilmember Odette Ramos",
} as sway.ILegislator;

const SAMPLE_ORGS = [
    {
        id: 501,
        bill_id: 101,
        support: Support.For,
        summary: "Reduces stormwater runoff and improves harbor water quality.",
        summary_ai_unreviewed: false,
        organization: {
            id: 1,
            name: "Chesapeake Bay Foundation",
        },
    },
    {
        id: 502,
        bill_id: 101,
        support: Support.Against,
        summary: "Increases development compliance costs on redevelopment parcels.",
        summary_ai_unreviewed: false,
        organization: {
            id: 2,
            name: "Greater Baltimore Chamber of Commerce",
        },
    },
] as unknown as sway.IBillOrganizationPosition[];

// @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
beforeAll(async () => {
    await Promise.all([
        import("app/frontend/components/bill/BillSummaryMarkdown"),
        import("app/frontend/components/bill/layouts/BannerBillLayout"),
        import("app/frontend/components/bill/layouts/BallotBillLayout"),
        import("app/frontend/components/bill/layouts/CornerstoreBillLayout"),
        import("app/frontend/components/bill/layouts/MonochromeBillLayout"),
        import("app/frontend/components/bill/layouts/ServiceManualBillLayout"),
        import("app/frontend/components/bill/layouts/SwissGridBillLayout"),
    ]);
});

afterEach(() => {
    cleanup();
    mockActiveTheme = "sway";
    vi.clearAllMocks();
});

describe("Empirical Challenge Suite: News Article Testimony Web Integration", () => {
    describe("1. Zero-Node Empty Invariant across split and unified layouts", () => {
        it("renders exactly 0 news testimony DOM nodes when news_testimonies is undefined, null, or empty []", () => {
            const billUndefined = { ...BASE_BILL, news_testimonies: undefined };
            const billNull = { ...BASE_BILL, news_testimonies: null as unknown as sway.INewsArticleTestimony[] };
            const billEmpty = { ...BASE_BILL, news_testimonies: [] };

            const { unmount: u1 } = render(<BillContent bill={billUndefined} organizations={[]} />);
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u1();

            const { unmount: u2 } = render(<BillContent bill={billNull} organizations={[]} />);
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u2();

            const { unmount: u3 } = render(<BillContent bill={billEmpty} organizations={[]} />);
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u3();

            const { unmount: u4 } = render(
                <BallotBillLayout
                    bill={billEmpty}
                    sponsor={BASE_SPONSOR}
                    organizations={[]}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u4();

            const { unmount: u5 } = render(
                <BannerBillLayout
                    bill={billEmpty}
                    sponsor={BASE_SPONSOR}
                    organizations={[]}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u5();

            const { unmount: u6 } = render(
                <CornerstoreBillLayout
                    bill={billEmpty}
                    sponsor={BASE_SPONSOR}
                    organizations={[]}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u6();
        });

        it("renders 0 news testimony nodes in Support card when testimonies contains only oppose items", () => {
            const opposeOnlyBill: sway.IBill = {
                ...BASE_BILL,
                news_testimonies: [
                    {
                        id: 101,
                        author_name: "Editorial Columnist",
                        outlet_name: "The Baltimore Sun",
                        url: "https://baltimoresun.com/opinion/oppose",
                        stance: "oppose",
                        argument: "The proposed mandate creates costly delays for infill housing.",
                    },
                ],
            };

            render(<BillContent bill={opposeOnlyBill} organizations={[]} />);

            const whySupportHeading = screen.getByText(PARITY_COPY.bill.content.whySupport);
            const supportCard = whySupportHeading.closest(".bg-card\\/95") as HTMLElement;
            expect(supportCard).toBeInTheDocument();
            expect(within(supportCard).queryByTestId("news-article-testimony")).toBeNull();

            const whyOpposeHeading = screen.getByText(PARITY_COPY.bill.content.whyOppose);
            const opposeCard = whyOpposeHeading.closest(".bg-card\\/95") as HTMLElement;
            expect(opposeCard).toBeInTheDocument();
            expect(within(opposeCard).getByTestId("news-article-testimony")).toBeInTheDocument();
            expect(
                within(opposeCard).getByText("The proposed mandate creates costly delays for infill housing."),
            ).toBeInTheDocument();
        });

        it("renders 0 news testimony nodes in Oppose card when testimonies contains only support items", () => {
            const supportOnlyBill: sway.IBill = {
                ...BASE_BILL,
                news_testimonies: [
                    {
                        id: 201,
                        author_name: "Forestry Advocate",
                        outlet_name: "Maryland Matters",
                        url: "https://marylandmatters.org/opinion/support",
                        stance: "support",
                        argument: "Canopy expansion cools heat islands and protects public health.",
                    },
                ],
            };

            render(<BillContent bill={supportOnlyBill} organizations={[]} />);

            const whyOpposeHeading = screen.getByText(PARITY_COPY.bill.content.whyOppose);
            const opposeCard = whyOpposeHeading.closest(".bg-card\\/95") as HTMLElement;
            expect(opposeCard).toBeInTheDocument();
            expect(within(opposeCard).queryByTestId("news-article-testimony")).toBeNull();

            const whySupportHeading = screen.getByText(PARITY_COPY.bill.content.whySupport);
            const supportCard = whySupportHeading.closest(".bg-card\\/95") as HTMLElement;
            expect(supportCard).toBeInTheDocument();
            expect(within(supportCard).getByTestId("news-article-testimony")).toBeInTheDocument();
            expect(
                within(supportCard).getByText("Canopy expansion cools heat islands and protects public health."),
            ).toBeInTheDocument();
        });
    });

    describe("2. Organization Position Isolation", () => {
        it("never alters organization counts, position summaries, or empty state text when testimonies are added", async () => {
            const billWithMixedNews: sway.IBill = {
                ...BASE_BILL,
                news_testimonies: [
                    {
                        id: 301,
                        author_name: "Columnist Alpha",
                        outlet_name: "The Baltimore Banner",
                        url: "https://baltimorebanner.com/opinion/support-trees",
                        stance: "support",
                        argument: "Strong support from climate economists.",
                    },
                    {
                        id: 302,
                        author_name: "Columnist Beta",
                        outlet_name: "The Baltimore Sun",
                        url: "https://baltimoresun.com/opinion/oppose-trees",
                        stance: "oppose",
                        argument: "Opposition citing construction price spikes.",
                    },
                ],
            };

            const { unmount: u1 } = render(<BillContent bill={billWithMixedNews} organizations={SAMPLE_ORGS} />);

            expect(screen.getByText("Chesapeake Bay Foundation")).toBeInTheDocument();
            expect(
                await screen.findByText("Reduces stormwater runoff and improves harbor water quality."),
            ).toBeInTheDocument();
            expect(screen.getByText("Greater Baltimore Chamber of Commerce")).toBeInTheDocument();
            expect(
                screen.getByText("Increases development compliance costs on redevelopment parcels."),
            ).toBeInTheDocument();

            expect(screen.queryByText(PARITY_COPY.org.noSupport)).toBeNull();
            expect(screen.queryByText(PARITY_COPY.org.noOppose)).toBeNull();

            expect(screen.getByText("Strong support from climate economists.")).toBeInTheDocument();
            expect(screen.getByText("Opposition citing construction price spikes.")).toBeInTheDocument();
            u1();

            const { unmount: u2 } = render(
                <BannerBillLayout
                    bill={billWithMixedNews}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(screen.getByText("Chesapeake Bay Foundation")).toBeInTheDocument();
            expect(screen.getByText("Greater Baltimore Chamber of Commerce")).toBeInTheDocument();
            expect(screen.getAllByTestId("news-article-testimony")).toHaveLength(2);
            u2();

            const { unmount: u3 } = render(<BillContent bill={billWithMixedNews} organizations={[]} />);
            expect(screen.getByText(PARITY_COPY.org.noSupport)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.org.noOppose)).toBeInTheDocument();
            u3();

            const { unmount: u4 } = render(
                <BallotBillLayout
                    bill={billWithMixedNews}
                    sponsor={BASE_SPONSOR}
                    organizations={[]}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(
                screen.getByText("Sway has not yet found statements of support or opposition for this legislation."),
            ).toBeInTheDocument();
            u4();

            const { unmount: u5 } = render(
                <CornerstoreBillLayout
                    bill={billWithMixedNews}
                    sponsor={BASE_SPONSOR}
                    organizations={[]}
                    isAwaitingScoreUpdate={false}
                />,
            );
            expect(screen.getByText("No statements of support or opposition are on file yet.")).toBeInTheDocument();
            u5();
        });

        it("demarcates news commentary with distinct visual badge from organizational positions", () => {
            const billWithNews: sway.IBill = {
                ...BASE_BILL,
                news_testimonies: [
                    {
                        id: 303,
                        author_name: "Marcus Vance",
                        outlet_name: "The Baltimore Sun",
                        url: "https://baltimoresun.com/opinion/trees",
                        stance: "support",
                        argument: "Urban forestry directly reduces summer heat island effects.",
                    },
                ],
            };

            render(<BillContent bill={billWithNews} organizations={SAMPLE_ORGS} />);

            const badges = screen.getAllByText("News commentary");
            expect(badges.length).toBe(1);
            expect(badges[0]).toHaveAttribute("data-variant", "stamp");
            expect(badges[0]).toHaveAttribute("data-tone", "warning");
        });
    });

    describe("3. Multi-Theme Layout Invariants across all 4 layouts and Bill of the Month views", () => {
        const fullTestimoniesBill: sway.IBill = {
            ...BASE_BILL,
            news_testimonies: [
                {
                    id: 401,
                    author_name: "Supporter Jane",
                    outlet_name: "The Baltimore Banner",
                    url: "https://baltimorebanner.com/opinion/support",
                    stance: "support",
                    argument: "Preserves natural shade canopy across East Baltimore.",
                },
                {
                    id: 402,
                    author_name: "Opposer John",
                    outlet_name: "Maryland Matters",
                    url: "https://marylandmatters.org/opinion/oppose",
                    stance: "oppose",
                    argument: "Exceeds municipal regulatory authority under current state code.",
                },
            ],
        };

        it("renders properly under DefaultBillLayout", () => {
            render(
                <DefaultBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            expect(screen.getByText("Preserves natural shade canopy across East Baltimore.")).toBeInTheDocument();
            expect(
                screen.getByText("Exceeds municipal regulatory authority under current state code."),
            ).toBeInTheDocument();
            expect(screen.getAllByTestId("news-article-testimony")).toHaveLength(2);
        });

        it("renders properly under BallotBillLayout with bal-org markup and For/Against stamps", () => {
            render(
                <BallotBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("bal-org");
            expect(items[1]).toHaveClass("bal-org");

            expect(within(items[0]).getByText("For")).toBeInTheDocument();
            expect(within(items[0]).getByText("By Supporter Jane")).toBeInTheDocument();

            expect(within(items[1]).getByText("Against")).toBeInTheDocument();
            expect(within(items[1]).getByText("By Opposer John")).toBeInTheDocument();
        });

        it("renders properly under BannerBillLayout with bn-prov markup and +/- indicators", () => {
            render(
                <BannerBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("bn-prov");
            expect(items[1]).toHaveClass("bn-prov");

            expect(within(items[0]).getByText("+")).toBeInTheDocument();
            expect(within(items[1]).getByText("-")).toBeInTheDocument();
        });

        it("renders properly under CornerstoreBillLayout with cs-org markup and For/Against stamps", () => {
            render(
                <CornerstoreBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("cs-org");
            expect(items[1]).toHaveClass("cs-org");

            expect(within(items[0]).getByText("For")).toBeInTheDocument();
            expect(within(items[1]).getByText("Against")).toBeInTheDocument();
        });

        it("renders properly under MonochromeBillLayout with mcb-org markup", () => {
            render(
                <MonochromeBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("mcb-org");
            expect(items[1]).toHaveClass("mcb-org");

            expect(within(items[0]).getByText("For")).toBeInTheDocument();
            expect(within(items[1]).getByText("Against")).toBeInTheDocument();
        });

        it("renders properly under ServiceManualBillLayout with smb-org markup", () => {
            render(
                <ServiceManualBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("smb-org");
            expect(items[1]).toHaveClass("smb-org");

            expect(within(items[0]).getByText("For")).toBeInTheDocument();
            expect(within(items[1]).getByText("Against")).toBeInTheDocument();
        });

        it("renders properly under SwissGridBillLayout with sgb-org markup", () => {
            render(
                <SwissGridBillLayout
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    isAwaitingScoreUpdate={false}
                />,
            );

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);
            expect(items[0]).toHaveClass("sgb-org");
            expect(items[1]).toHaveClass("sgb-org");

            expect(within(items[0]).getByText("For")).toBeInTheDocument();
            expect(within(items[1]).getByText("Against")).toBeInTheDocument();
        });

        it("renders across active themes dynamically in Bill page view", async () => {
            mockActiveTheme = "sway";
            const { unmount: u1 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(() => expect(screen.getAllByTestId("news-article-testimony")).toHaveLength(2), {
                timeout: 5000,
            });
            u1();

            mockActiveTheme = "ballot";
            const { unmount: u2 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("bal-org");
                },
                { timeout: 5000 },
            );
            u2();

            mockActiveTheme = "banner";
            const { unmount: u3 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("bn-prov");
                },
                { timeout: 5000 },
            );
            u3();

            mockActiveTheme = "cornerstore";
            const { unmount: u4 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("cs-org");
                },
                { timeout: 5000 },
            );
            u4();

            mockActiveTheme = "monochrome";
            const { unmount: u5 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("mcb-org");
                },
                { timeout: 5000 },
            );
            u5();

            mockActiveTheme = "service-manual";
            const { unmount: u6 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("smb-org");
                },
                { timeout: 5000 },
            );
            u6();

            mockActiveTheme = "swiss-grid";
            const { unmount: u7 } = render(
                <Bill
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    const items = screen.getAllByTestId("news-article-testimony");
                    expect(items).toHaveLength(2);
                    expect(items[0]).toHaveClass("sgb-org");
                },
                { timeout: 5000 },
            );
            u7();
        });

        it("renders across active themes in BillOfTheMonth page view and suppresses on nil bill", async () => {
            mockActiveTheme = "ballot";
            const { unmount: u1 } = render(
                <BillOfTheMonth
                    bill={fullTestimoniesBill}
                    sponsor={BASE_SPONSOR}
                    organizations={SAMPLE_ORGS}
                    legislator_votes={[]}
                />,
            );
            await waitFor(
                () => {
                    expect(screen.getAllByTestId("news-article-testimony")).toHaveLength(2);
                },
                { timeout: 5000 },
            );
            u1();

            const { unmount: u2 } = render(
                <BillOfTheMonth bill={undefined} sponsor={BASE_SPONSOR} organizations={[]} legislator_votes={[]} />,
            );
            expect(screen.getByTestId("botm-empty")).toBeInTheDocument();
            expect(screen.queryByTestId("news-article-testimony")).toBeNull();
            u2();
        });
    });

    describe("4. Volumetric & Extreme Stress Boundary Conditions", () => {
        it("handles 50+ testimonies preserving array ordering and unique keys without React key collisions", () => {
            const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
            const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

            const largeList: sway.INewsArticleTestimony[] = Array.from({ length: 60 }, (_, i) => ({
                id: 1000 + i,
                author_name: `Author ${i}`,
                outlet_name: `Publication ${i % 5}`,
                url: `https://example.com/opinion/${i}`,
                stance: i % 2 === 0 ? "support" : "oppose",
                argument: `Argument number ${i} regarding municipal environmental policy.`,
            }));

            render(<NewsArticleTestimony testimonies={largeList} variant="default" />);

            const renderedItems = screen.getAllByTestId("news-article-testimony");
            expect(renderedItems).toHaveLength(60);

            expect(renderedItems[0]).toHaveTextContent("Argument number 0 regarding municipal environmental policy.");
            expect(renderedItems[59]).toHaveTextContent("Argument number 59 regarding municipal environmental policy.");

            const allLogs = [...errorSpy.mock.calls, ...warnSpy.mock.calls].flat().join(" ");
            expect(allLogs).not.toContain('unique "key" prop');

            errorSpy.mockRestore();
            warnSpy.mockRestore();
        });

        it("handles extreme 5,000 character argument strings without crashing or structure corruption", () => {
            const longText = "A".repeat(5000);
            const extremeTestimony: sway.INewsArticleTestimony = {
                id: 2001,
                author_name: "Prolific Essayist",
                outlet_name: "The Longform Review",
                url: "https://longform.example.com/essay",
                stance: "support",
                argument: longText,
            };

            render(<NewsArticleTestimony testimonies={[extremeTestimony]} variant="banner" />);

            const article = screen.getByTestId("news-article-testimony");
            expect(article).toBeInTheDocument();
            expect(article).toHaveTextContent(longText);
        });

        it("defaults null, undefined, and empty string author_name cleanly to '{outlet_name} Editorial Board' without orphaned 'By '", () => {
            const nullAuthor: sway.INewsArticleTestimony = {
                id: 2101,
                author_name: null,
                outlet_name: "The Baltimore Sun",
                url: "https://baltimoresun.com/editorial-1",
                stance: "support",
                argument: "Null author argument.",
            };

            const undefinedAuthor: sway.INewsArticleTestimony = {
                id: 2102,
                author_name: undefined as unknown as null,
                outlet_name: "The Washington Post",
                url: "https://washingtonpost.com/editorial-2",
                stance: "support",
                argument: "Undefined author argument.",
            };

            const emptyStringAuthor: sway.INewsArticleTestimony = {
                id: 2103,
                author_name: "",
                outlet_name: "Maryland Matters",
                url: "https://marylandmatters.org/editorial-3",
                stance: "support",
                argument: "Empty string author argument.",
            };

            const alreadyEditorialBoard: sway.INewsArticleTestimony = {
                id: 2104,
                author_name: null,
                outlet_name: "The Baltimore Banner Editorial Board",
                url: "https://baltimorebanner.com/editorial-4",
                stance: "oppose",
                argument: "Already contains editorial board.",
            };

            const { unmount: u1 } = render(<NewsArticleTestimony testimonies={[nullAuthor]} />);
            expect(screen.getByText("The Baltimore Sun Editorial Board")).toBeInTheDocument();
            expect(screen.queryByText(/^By\s*$/i)).toBeNull();
            u1();

            const { unmount: u2 } = render(<NewsArticleTestimony testimonies={[undefinedAuthor]} />);
            expect(screen.getByText("The Washington Post Editorial Board")).toBeInTheDocument();
            expect(screen.queryByText(/^By\s*$/i)).toBeNull();
            u2();

            const { unmount: u3 } = render(<NewsArticleTestimony testimonies={[emptyStringAuthor]} />);
            expect(screen.getByText("Maryland Matters Editorial Board")).toBeInTheDocument();
            expect(screen.queryByText(/^By\s*$/i)).toBeNull();
            u3();

            const { unmount: u4 } = render(<NewsArticleTestimony testimonies={[alreadyEditorialBoard]} />);
            expect(screen.getAllByText("The Baltimore Banner Editorial Board")).toHaveLength(2);
            expect(screen.queryByText("The Baltimore Banner Editorial Board Editorial Board")).toBeNull();
            u4();
        });

        it("keeps distinct authors at the same outlet as separate distinct items with independent anchors", () => {
            const sameOutletDistinctAuthors: sway.INewsArticleTestimony[] = [
                {
                    id: 3001,
                    author_name: "Author Alice",
                    outlet_name: "The Baltimore Sun",
                    url: "https://baltimoresun.com/opinion/alice",
                    stance: "support",
                    argument: "Alice's perspective on tree protection.",
                },
                {
                    id: 3002,
                    author_name: "Author Bob",
                    outlet_name: "The Baltimore Sun",
                    url: "https://baltimoresun.com/opinion/bob",
                    stance: "support",
                    argument: "Bob's perspective on tree protection.",
                },
            ];

            render(<NewsArticleTestimony testimonies={sameOutletDistinctAuthors} />);

            const items = screen.getAllByTestId("news-article-testimony");
            expect(items).toHaveLength(2);

            expect(screen.getByText("By Author Alice")).toBeInTheDocument();
            expect(screen.getByText("Alice's perspective on tree protection.")).toBeInTheDocument();

            expect(screen.getByText("By Author Bob")).toBeInTheDocument();
            expect(screen.getByText("Bob's perspective on tree protection.")).toBeInTheDocument();

            const links = screen.getAllByRole("link", { name: /The Baltimore Sun/i });
            expect(links).toHaveLength(2);
            expect(links[0]).toHaveAttribute("href", "https://baltimoresun.com/opinion/alice");
            expect(links[1]).toHaveAttribute("href", "https://baltimoresun.com/opinion/bob");
        });

        it("refuses unsafe URL protocols rendering inert text spans without clickable anchors", () => {
            const unsafeTestimonies: sway.INewsArticleTestimony[] = [
                {
                    id: 4001,
                    author_name: "Hacker X",
                    outlet_name: "Exploit Times",
                    url: "javascript:alert('pwned')",
                    stance: "support",
                    argument: "Attempting javascript execution.",
                },
                {
                    id: 4002,
                    author_name: "Hacker Y",
                    outlet_name: "Data Leaks",
                    url: "data:text/html,<script>alert(1)</script>",
                    stance: "oppose",
                    argument: "Attempting data URI injection.",
                },
                {
                    id: 4003,
                    author_name: "Hacker Z",
                    outlet_name: "File Access",
                    url: "file:///etc/shadow",
                    stance: "support",
                    argument: "Attempting local file disclosure.",
                },
            ];

            render(<NewsArticleTestimony testimonies={unsafeTestimonies} />);

            expect(screen.queryByRole("link")).toBeNull();
            expect(screen.getByText("Exploit Times")).toBeInTheDocument();
            expect(screen.getByText("Data Leaks")).toBeInTheDocument();
            expect(screen.getByText("File Access")).toBeInTheDocument();
        });
    });
});
