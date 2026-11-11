// @lat: [[unlinked-bill-presentation#Cross-platform parity in unlinked presentation]]
// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries]]

import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { Suspense } from "react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { hasValidSourceLink } from "app/frontend/components/bill/sway_utils/billSourceLink";

const GENERIC_PORTAL_URLS = [
    "https://baltimore.legistar.com",
    "https://baltimore.legistar.com/LegislationSearch.aspx",
    "https://congress.gov",
    "https://www.congress.gov",
    "https://mgaleg.maryland.gov",
    "https://mgaleg.maryland.gov/mgawebsite",
];

// Mock Inertia and locales
vi.mock("@inertiajs/react", () => ({
    usePage: () => ({
        props: {
            user: null,
            pending_vote: null,
            errors: {},
            sway_locale: {
                generic_portal_urls: GENERIC_PORTAL_URLS,
            },
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

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocaleSlug: () => "baltimore",
    useSwayLocale: () => [null, vi.fn<() => void>()],
    useSwayLocales: () => ({ options: [] }),
}));

vi.mock("app/frontend/components/bill/EmailLegislatorsModal", () => ({
    default: () => <div data-testid="mock-email-modal" />,
}));
vi.mock("app/frontend/components/ui/confirm-dialog", () => ({
    useConfirm: () => vi.fn<(message: string) => Promise<boolean>>(),
}));
vi.mock("app/frontend/components/contexts/hooks/useOffline", () => ({
    useOffline: () => ({ isOnline: true, assertBanner: vi.fn<() => void>() }),
}));
vi.mock("app/frontend/components/bill/charts/BillChartsPanel", () => ({
    default: () => <div data-testid="mock-charts" />,
}));
vi.mock("app/frontend/components/bill/charts/BillAffinityPanel", () => ({
    default: () => <div data-testid="mock-affinity" />,
}));
vi.mock("app/frontend/components/bill/BillAsIntroduced", () => ({
    default: () => <div data-testid="mock-as-introduced" />,
}));

import BillContent from "app/frontend/components/bill/BillContent";
import BallotBillLayout from "app/frontend/components/bill/layouts/BallotBillLayout";
import BannerBillLayout from "app/frontend/components/bill/layouts/BannerBillLayout";
import CornerstoreBillLayout from "app/frontend/components/bill/layouts/CornerstoreBillLayout";

const BASE_BILL: sway.IBill = {
    id: 101,
    external_id: "24-0001",
    title: "Ordinance on Street Trees",
    summary: "Requires planting native street trees across the city.",
    summary_ai_unreviewed: true,
    status: "passed",
    link: "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=FEDCBA",
    sway_locale_id: 1,
    legislator_id: 10,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
} as unknown as sway.IBill;

const SPONSOR = { id: 10, full_name: "Zeke Cohen" } as sway.ILegislator;

afterEach(cleanup);

describe("Milestone M3 Adversarial Challenge: Real Summary Rendering & Layout Parity", () => {
    // Resolve lazy markdown renderer chunk before any example is on the clock.
    // @lat: [[admin-chunks-are-not-precached#Why the bill layouts do not import the markdown renderer directly]]
    beforeAll(async () => {
        await import("app/frontend/components/bill/BillSummaryMarkdown");
    });

    describe("1. Themed layouts pass billId and billLink down through real markdown renderer", () => {
        const layouts = [
            { name: "BallotBillLayout", Component: BallotBillLayout },
            { name: "BannerBillLayout", Component: BannerBillLayout },
            { name: "CornerstoreBillLayout", Component: CornerstoreBillLayout },
        ];

        it.each(layouts)("$name renders official source link when valid", async ({ Component }) => {
            render(
                <Suspense fallback={<div>Loading...</div>}>
                    <Component
                        bill={BASE_BILL}
                        sponsor={SPONSOR}
                        organizations={[]}
                        user_vote={undefined}
                        isAwaitingScoreUpdate={false}
                    />
                </Suspense>,
            );

            await waitFor(
                () => {
                    expect(screen.getByTestId("bill-source-text-link")).toBeInTheDocument();
                },
                { timeout: 5000 },
            );

            const link = screen.getByTestId("bill-source-text-link");
            expect(link).toHaveAttribute("href", BASE_BILL.link);
            expect(screen.queryByTestId("summary-no-source-link")).not.toBeInTheDocument();
            expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
        });

        it.each(layouts)(
            "$name suppresses link and shows unavailable copy when link is generic search URL",
            async ({ Component }) => {
                const genericBill = {
                    ...BASE_BILL,
                    link: "https://baltimore.legistar.com/LegislationSearch.aspx",
                };

                render(
                    <Suspense fallback={<div>Loading...</div>}>
                        <Component
                            bill={genericBill}
                            sponsor={SPONSOR}
                            organizations={[]}
                            user_vote={undefined}
                            isAwaitingScoreUpdate={false}
                        />
                    </Suspense>,
                );

                await waitFor(
                    () => {
                        expect(screen.getByTestId("summary-no-source-link")).toBeInTheDocument();
                    },
                    { timeout: 5000 },
                );

                expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
                expect(screen.getByTestId("summary-no-source-link")).toHaveTextContent(
                    PARITY_COPY.bill.officialSourceUnavailable,
                );
                expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
            },
        );

        it.each(layouts)(
            "$name suppresses link and shows unavailable copy when link has query parameters",
            async ({ Component }) => {
                const queryBill = {
                    ...BASE_BILL,
                    link: "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
                };

                render(
                    <Suspense fallback={<div>Loading...</div>}>
                        <Component
                            bill={queryBill}
                            sponsor={SPONSOR}
                            organizations={[]}
                            user_vote={undefined}
                            isAwaitingScoreUpdate={false}
                        />
                    </Suspense>,
                );

                await waitFor(
                    () => {
                        expect(screen.getByTestId("summary-no-source-link")).toBeInTheDocument();
                    },
                    { timeout: 5000 },
                );

                expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
                expect(screen.getByTestId("summary-no-source-link")).toHaveTextContent(
                    PARITY_COPY.bill.officialSourceUnavailable,
                );
                expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
            },
        );

        it.each(layouts)("$name preserves summary report action when link is null", async ({ Component }) => {
            const unlinkedBill = {
                ...BASE_BILL,
                link: null,
                summary_ai_unreviewed: false, // reviewed summary + null link
            };

            render(
                <Suspense fallback={<div>Loading...</div>}>
                    <Component
                        bill={unlinkedBill}
                        sponsor={SPONSOR}
                        organizations={[]}
                        user_vote={undefined}
                        isAwaitingScoreUpdate={false}
                    />
                </Suspense>,
            );

            await waitFor(
                () => {
                    expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
                },
                { timeout: 5000 },
            );

            expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
            expect(screen.getByTestId("summary-no-source-link")).toHaveTextContent(
                PARITY_COPY.bill.officialSourceUnavailable,
            );

            // Clicking report button opens dialog
            fireEvent.click(screen.getByTestId("btn-report-inaccurate-summary"));
            expect(screen.getByTestId("report-summary-form")).toBeInTheDocument();
        });
    });

    describe("2. BillContent with UNMOCKED LazyBillSummaryMarkdown (live integration)", () => {
        it("renders both primary action and summary unavailable notices without test ID collision", async () => {
            const unlinkedBill = { ...BASE_BILL, link: null };

            render(<BillContent bill={unlinkedBill} organizations={[]} />);

            await waitFor(
                () => {
                    // Wait for lazy markdown to resolve
                    expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
                },
                { timeout: 5000 },
            );

            // BillContent renders 'no-source-link' and AiUnreviewedNotice renders 'summary-no-source-link'
            expect(screen.getByTestId("no-source-link")).toBeInTheDocument();
            expect(screen.getByTestId("summary-no-source-link")).toBeInTheDocument();
            expect(screen.getAllByTestId("no-source-link")).toHaveLength(1);
            expect(screen.getAllByTestId("summary-no-source-link")).toHaveLength(1);
        });

        it("suppresses external links and renders both unavailable notices when link has query parameters", async () => {
            const queryBill = {
                ...BASE_BILL,
                link: "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
            };

            render(<BillContent bill={queryBill} organizations={[]} />);

            await waitFor(
                () => {
                    expect(screen.getByTestId("btn-report-inaccurate-summary")).toBeInTheDocument();
                },
                { timeout: 5000 },
            );

            expect(screen.queryByRole("link", { name: /Baltimore Legistar/i })).not.toBeInTheDocument();
            expect(screen.queryByTestId("bill-source-text-link")).not.toBeInTheDocument();
            expect(screen.getByTestId("no-source-link")).toBeInTheDocument();
            expect(screen.getByTestId("summary-no-source-link")).toBeInTheDocument();
        });
    });

    describe("3. Edge-case URL inputs in hasValidSourceLink and AiUnreviewedNotice", () => {
        it("suppresses generic URLs with trailing slashes", () => {
            expect(
                hasValidSourceLink("https://baltimore.legistar.com/LegislationSearch.aspx/", GENERIC_PORTAL_URLS),
            ).toBe(false);
            expect(hasValidSourceLink("https://congress.gov/", GENERIC_PORTAL_URLS)).toBe(false);
            expect(hasValidSourceLink("https://www.congress.gov/", GENERIC_PORTAL_URLS)).toBe(false);
            expect(hasValidSourceLink("https://mgaleg.maryland.gov/mgawebsite/", GENERIC_PORTAL_URLS)).toBe(false);
        });

        it("suppresses generic URLs with leading and trailing whitespace", () => {
            expect(
                hasValidSourceLink("  https://baltimore.legistar.com/LegislationSearch.aspx  ", GENERIC_PORTAL_URLS),
            ).toBe(false);
            expect(hasValidSourceLink("\thttps://congress.gov\n", GENERIC_PORTAL_URLS)).toBe(false);
        });

        it("rejects search and portal URLs with query parameters, protocol variations, or mixed casing", () => {
            const hasQueryParam = hasValidSourceLink(
                "https://baltimore.legistar.com/LegislationSearch.aspx?Mode=Advanced",
                GENERIC_PORTAL_URLS,
            );
            const isMixedCase = hasValidSourceLink("https://Congress.gov", GENERIC_PORTAL_URLS);
            const isHttp = hasValidSourceLink("http://congress.gov", GENERIC_PORTAL_URLS);
            const isHttpLegistar = hasValidSourceLink(
                "http://baltimore.legistar.com/LegislationSearch.aspx",
                GENERIC_PORTAL_URLS,
            );

            expect(hasQueryParam).toBe(false);
            expect(isMixedCase).toBe(false);
            expect(isHttp).toBe(false);
            expect(isHttpLegistar).toBe(false);
        });
    });
});
