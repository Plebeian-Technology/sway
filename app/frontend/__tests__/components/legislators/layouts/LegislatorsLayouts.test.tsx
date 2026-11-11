// @lat: [[legislator-directory-layouts#Legislator directory layout selection]]

import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import type { ThemeId } from "app/frontend/styles/themes";
import DefaultLegislatorsLayout from "app/frontend/components/legislators/layouts/DefaultLegislatorsLayout";
import { legislatorsLayoutFor, type ILegislatorsLayoutProps } from "app/frontend/components/legislators/layouts";

vi.mock("@inertiajs/react", () => ({
    router: {
        on: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
        post: vi.fn<() => void>(),
    },
    usePage: () => ({
        props: {
            user: null,
            errors: {},
        },
    }),
    Link: ({ children, href, className }: { children?: React.ReactNode; href?: string; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

class IntersectionObserverStub {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords(): IntersectionObserverEntry[] {
        return [];
    }
}

const SAMPLE_LEGISLATORS: sway.ILegislator[] = [
    {
        id: 1,
        external_id: "rep-1",
        full_name: "Jane Doe",
        title: "Councilmember",
        sway_locale_id: 1,
        district: { id: 1, name: "District 1", number: 1 },
        photo_url: "/photos/jane.jpg",
        email: "jane@example.gov",
        phone: "555-0101",
        user_legislator_score: {
            count_agreed: 12,
            count_disagreed: 3,
            count_no_legislator_vote: 1,
        } as unknown as sway.scoring.IAgreeable,
    } as unknown as sway.ILegislator,
    {
        id: 2,
        external_id: "rep-2",
        full_name: "John Smith",
        title: "Senator",
        sway_locale_id: 1,
        district: { id: 2, name: "District 2", number: 2 },
        user_legislator_score: {
            count_agreed: 8,
            count_disagreed: 7,
            count_no_legislator_vote: 2,
        } as unknown as sway.scoring.IAgreeable,
    } as unknown as sway.ILegislator,
];

const createProps = (overrides: Partial<ILegislatorsLayoutProps> = {}): ILegislatorsLayoutProps => ({
    legislators: SAMPLE_LEGISLATORS,
    activeLegislators: SAMPLE_LEGISLATORS,
    activeTab: "current",
    onTabChange: vi.fn<(tab: string) => void>(),
    currentLocale: { id: 1, name: "baltimore-maryland-united_states" } as sway.ISwayLocale,
    localeOptions: [
        { value: 1, label: "Baltimore City" },
        { value: 2, label: "Maryland" },
    ],
    selectedLocaleId: 1,
    onLocaleChange: vi.fn<(id: number) => void>(),
    waitingForNewTerm: false,
    onFindLegislators: vi.fn<() => void>(),
    currentHistory: undefined,
    isHistoryLoading: false,
    historyFailed: false,
    onRetryHistory: vi.fn<() => void>(),
    termRange: "2024–2028",
    ...overrides,
});

describe("LegislatorsLayouts — layout registry & resolution", () => {
    afterEach(cleanup);

    it("resolves DefaultLegislatorsLayout for standard themes and unknown theme IDs", () => {
        expect(legislatorsLayoutFor("sway")).toBe(DefaultLegislatorsLayout);
        expect(legislatorsLayoutFor("banner")).toBe(DefaultLegislatorsLayout);
        expect(legislatorsLayoutFor("ballot")).toBe(DefaultLegislatorsLayout);
        expect(legislatorsLayoutFor("cornerstore")).toBe(DefaultLegislatorsLayout);
        expect(legislatorsLayoutFor("" as ThemeId)).toBe(DefaultLegislatorsLayout);
        expect(legislatorsLayoutFor("unknown" as ThemeId)).toBe(DefaultLegislatorsLayout);
    });

    it("resolves distinct components for readability themes", () => {
        const mono = legislatorsLayoutFor("monochrome");
        const service = legislatorsLayoutFor("service-manual");
        const swiss = legislatorsLayoutFor("swiss-grid");

        expect(mono).not.toBe(DefaultLegislatorsLayout);
        expect(service).not.toBe(DefaultLegislatorsLayout);
        expect(swiss).not.toBe(DefaultLegislatorsLayout);
        expect(mono).not.toBe(service);
        expect(service).not.toBe(swiss);
    });
});

describe("LegislatorsLayouts — readability theme layout rendering", () => {
    const THEMES_TO_TEST: { themeId: ThemeId; rootClass: string }[] = [
        { themeId: "monochrome", rootClass: "monochrome-legislators" },
        { themeId: "service-manual", rootClass: "service-manual-legislators" },
        { themeId: "swiss-grid", rootClass: "swiss-grid-legislators" },
    ];

    beforeEach(() => {
        vi.stubGlobal("IntersectionObserver", IntersectionObserverStub);
    });

    afterEach(() => {
        cleanup();
        vi.unstubAllGlobals();
    });

    describe.each(THEMES_TO_TEST)("$themeId layout", ({ themeId, rootClass }) => {
        it("renders root class, count line, locale picker, tabs, and representative links", async () => {
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps();

            const { container } = render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            expect(container.querySelector(`.${rootClass}`)).not.toBeNull();

            const countLine = screen.getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("Showing 2 representatives");

            expect(screen.getByText("Jane Doe")).toBeInTheDocument();
            expect(screen.getByText("John Smith")).toBeInTheDocument();

            const repLinks = screen.getAllByRole("link", { name: "View representative" });
            expect(repLinks[0]).toHaveAttribute("href", ROUTES.legislator(1));

            expect(screen.getByText(PARITY_COPY.legislators.tabCurrentTerm)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.legislators.tabLifetime)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.legislators.tabHistory)).toBeInTheDocument();
        });

        it("renders term ended message when waitingForNewTerm is true", async () => {
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeLegislators: [],
                waitingForNewTerm: true,
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            const countLine = screen.getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("The term has ended");
            expect(screen.queryByText(PARITY_COPY.legislators.searchAgain)).toBeNull();
        });

        it("renders none found message and search again button when roster is empty and not waiting", async () => {
            const onFindLegislators = vi.fn<() => void>();
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeLegislators: [],
                waitingForNewTerm: false,
                onFindLegislators,
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            const countLine = screen.getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("No representatives found");

            const searchAgainBtn = screen.getByRole("button", { name: PARITY_COPY.legislators.searchAgain });
            expect(searchAgainBtn).toBeInTheDocument();
            fireEvent.click(searchAgainBtn);
            expect(onFindLegislators).toHaveBeenCalledTimes(1);
        });

        it("renders history tab loading state", async () => {
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: true,
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            expect(screen.getByText(PARITY_COPY.legislators.loading)).toBeInTheDocument();
        });

        it("renders history tab error state with retry button", async () => {
            const onRetryHistory = vi.fn<() => void>();
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: false,
                historyFailed: true,
                currentHistory: undefined,
                onRetryHistory,
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            expect(screen.getByText(PARITY_COPY.legislators.historyLoadError)).toBeInTheDocument();

            const retryBtn = screen.getByRole("button", { name: PARITY_COPY.legislators.historyRetry });
            fireEvent.click(retryBtn);
            expect(onRetryHistory).toHaveBeenCalledTimes(1);
        });

        it("renders history tab empty state when sessions are empty", async () => {
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: false,
                historyFailed: false,
                currentHistory: {
                    sessions: [],
                },
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            expect(screen.getByText(PARITY_COPY.legislators.historyEmptyHeading)).toBeInTheDocument();
            expect(screen.getByText(PARITY_COPY.legislators.historyEmptyBody)).toBeInTheDocument();
        });

        it("renders history sessions with ended stamp", async () => {
            const Layout = legislatorsLayoutFor(themeId);
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: false,
                historyFailed: false,
                currentHistory: {
                    sessions: [
                        {
                            session_label: "2020–2024 City Council",
                            entries: [
                                {
                                    legislator: SAMPLE_LEGISLATORS[0],
                                    term: {
                                        term_start_year: 2020,
                                        term_end_year: 2024,
                                    } as unknown as sway.legislatorHistory.ITerm,
                                    score: {
                                        count_agreed: 5,
                                        count_disagreed: 2,
                                        count_no_legislator_vote: 0,
                                    } as unknown as sway.scoring.IAgreeable,
                                    ended_reason: "term_ended",
                                },
                            ],
                        },
                    ],
                },
            });

            render(
                <React.Suspense fallback={<div data-testid="loading-layout" />}>
                    <Layout {...props} />
                </React.Suspense>,
            );

            await waitFor(() => {
                expect(screen.queryByTestId("loading-layout")).toBeNull();
            });

            expect(screen.getByText("2020–2024 City Council")).toBeInTheDocument();
            expect(screen.getByTestId("legislator-card-ended-stamp")).toBeInTheDocument();
        });
    });
});
