// @lat: [[legislator-directory-layouts#Legislator directory layout selection]]
// @lat: [[legislator-directory-layouts#Legislators page container]]
// @lat: [[legislator-directory-layouts#Legislator directory layout props contract]]
// @lat: [[legislator-directory-layouts#DefaultLegislatorsLayout.tsx]]
// @lat: [[legislator-directory-layouts#MonochromeLegislatorsLayout.tsx]]
// @lat: [[legislator-directory-layouts#ServiceManualLegislatorsLayout.tsx]]
// @lat: [[legislator-directory-layouts#SwissGridLegislatorsLayout.tsx]]

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import * as React from "react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import type { ThemeId } from "app/frontend/styles/themes";
import DefaultLegislatorsLayout from "app/frontend/components/legislators/layouts/DefaultLegislatorsLayout";
import MonochromeLegislatorsLayout from "app/frontend/components/legislators/layouts/MonochromeLegislatorsLayout";
import ServiceManualLegislatorsLayout from "app/frontend/components/legislators/layouts/ServiceManualLegislatorsLayout";
import SwissGridLegislatorsLayout from "app/frontend/components/legislators/layouts/SwissGridLegislatorsLayout";
import {
    legislatorsLayoutFor,
    legislatorListLayoutFor,
    type ILegislatorsLayoutProps,
} from "app/frontend/components/legislators/layouts";

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

class MockIntersectionObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
    takeRecords(): IntersectionObserverEntry[] {
        return [];
    }
}

const buildLegislators = (count: number): sway.ILegislator[] =>
    Array.from({ length: count }, (_, i) => ({
        id: i + 1,
        external_id: `rep-${i + 1}`,
        full_name: `Representative ${i + 1}`,
        title: "Delegate",
        sway_locale_id: 1,
        district: { id: i + 1, name: `District ${i + 1}`, number: i + 1 },
        photo_url: `/photos/rep-${i + 1}.jpg`,
        email: `rep${i + 1}@example.gov`,
        phone: `555-010${i + 1}`,
        user_legislator_score: {
            count_agreed: 10 + i,
            count_disagreed: 2,
            count_no_legislator_vote: 1,
        } as unknown as sway.scoring.IAgreeable,
        lifetime_score: {
            count_agreed: 50 + i,
            count_disagreed: 10,
            count_no_legislator_vote: 5,
        } as unknown as sway.scoring.IAgreeable,
    })) as unknown as sway.ILegislator[];

const SAMPLE_LEGISLATORS = buildLegislators(12);

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

describe("Challenge: Layout Registry & Complete Theme Mapping", () => {
    afterEach(cleanup);

    it.each([["monochrome" as const], ["service-manual" as const], ["swiss-grid" as const]])(
        "resolves readability theme %s to distinct component",
        (themeId) => {
            expect(legislatorsLayoutFor(themeId)).not.toBe(DefaultLegislatorsLayout);
        },
    );

    it.each([["sway" as const], ["banner" as const], ["ballot" as const], ["cornerstore" as const]])(
        "resolves standard theme %s to DefaultLegislatorsLayout",
        (themeId) => {
            expect(legislatorsLayoutFor(themeId)).toBe(DefaultLegislatorsLayout);
        },
    );

    it.each([
        ["" as ThemeId],
        [null as unknown as ThemeId],
        [undefined as unknown as ThemeId],
        ["non-existent-theme" as ThemeId],
    ])("handles invalid theme %s gracefully by falling back to DefaultLegislatorsLayout", (themeId) => {
        expect(legislatorsLayoutFor(themeId)).toBe(DefaultLegislatorsLayout);
    });

    it("ensures legislatorListLayoutFor is an alias for legislatorsLayoutFor", () => {
        expect(legislatorListLayoutFor).toBe(legislatorsLayoutFor);
    });
});

describe("Challenge: CSS Scoping and Token Purity", () => {
    const cssFiles = [
        {
            file: "MonochromeLegislatorsLayout.css",
            scope: '[data-theme="monochrome"]',
        },
        {
            file: "ServiceManualLegislatorsLayout.css",
            scope: '[data-theme="service-manual"]',
        },
        {
            file: "SwissGridLegislatorsLayout.css",
            scope: '[data-theme="swiss-grid"]',
        },
    ];

    it.each(cssFiles)("ensures all selectors in $file are scoped under $scope", ({ file, scope }) => {
        const filePath = resolve(process.cwd(), "app/frontend/components/legislators/layouts", file);
        const cssContent = readFileSync(filePath, "utf-8");
        const cleanContent = cssContent
            .replace(/\/\*[\s\S]*?\*\//g, "")
            .replace(/@media[^{]+\{([\s\S]+?\}\s*\})/g, "$1");

        const rules = cleanContent
            .split("}")
            .map((r) => r.trim())
            .filter(Boolean);
        const unscopedSelectors: string[] = [];

        for (const rule of rules) {
            const selectorPart = rule.split("{")[0]?.trim();
            if (selectorPart && !selectorPart.startsWith("@")) {
                const selectors = selectorPart.split(",").map((s) => s.trim());
                for (const selector of selectors) {
                    if (!selector.startsWith(scope)) {
                        unscopedSelectors.push(selector);
                    }
                }
            }
        }

        expect(unscopedSelectors).toEqual([]);
    });
});

describe("Challenge: Stress-Testing Boundary States across all 4 layouts", () => {
    const LAYOUT_CASES = [
        { name: "Default", Component: DefaultLegislatorsLayout },
        { name: "Monochrome", Component: MonochromeLegislatorsLayout },
        { name: "ServiceManual", Component: ServiceManualLegislatorsLayout },
        { name: "SwissGrid", Component: SwissGridLegislatorsLayout },
    ];

    beforeEach(() => {
        vi.stubGlobal("IntersectionObserver", MockIntersectionObserver);
    });

    afterEach(() => {
        cleanup();
        vi.unstubAllGlobals();
    });

    describe.each(LAYOUT_CASES)("$name layout edge-case behavior", ({ Component }) => {
        it("handles undefined currentLocale without crashing", () => {
            const props = createProps({
                currentLocale: undefined,
            });

            const { getByTestId } = render(<Component {...props} />);
            const countLine = getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("Showing 12 representatives for .");
        });

        it("handles null / undefined termRange without rendering empty elements or text", () => {
            const propsNull = createProps({ termRange: null });
            const { queryByText: queryText1 } = render(<Component {...propsNull} />);
            expect(queryText1("null")).toBeNull();
            expect(queryText1("undefined")).toBeNull();
            cleanup();

            const propsUndefined = createProps({ termRange: undefined as unknown as null });
            const { queryByText: queryText2 } = render(<Component {...propsUndefined} />);
            expect(queryText2("null")).toBeNull();
            expect(queryText2("undefined")).toBeNull();
        });

        it("renders termRange properly when supplied", () => {
            const props = createProps({ termRange: "2023–2027" });
            const { getByText } = render(<Component {...props} />);
            expect(getByText("2023–2027")).toBeInTheDocument();
        });

        it("handles above-the-fold threshold: renders 8 items above fold and wraps 4 items in MountWhenNear", () => {
            const props = createProps({ activeLegislators: SAMPLE_LEGISLATORS });
            render(<Component {...props} />);

            for (let i = 1; i <= 8; i++) {
                expect(screen.getByText(`Representative ${i}`)).toBeInTheDocument();
            }
            for (let i = 9; i <= 12; i++) {
                expect(screen.queryByText(`Representative ${i}`)).toBeNull();
            }
            expect(screen.getAllByTestId("mount-when-near-placeholder")).toHaveLength(4);
        });

        it("renders empty list with search again button and triggers callback", () => {
            const onFindLegislators = vi.fn<() => void>();
            const props = createProps({
                activeLegislators: [],
                waitingForNewTerm: false,
                onFindLegislators,
            });

            render(<Component {...props} />);
            const countLine = screen.getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("No representatives found");

            const searchBtn = screen.getByRole("button", { name: PARITY_COPY.legislators.searchAgain });
            fireEvent.click(searchBtn);
            expect(onFindLegislators).toHaveBeenCalledTimes(1);
        });

        it("renders waitingForNewTerm without search again button", () => {
            const props = createProps({
                activeLegislators: [],
                waitingForNewTerm: true,
            });

            render(<Component {...props} />);
            const countLine = screen.getByTestId("legislators-count-line");
            expect(countLine.textContent).toContain("The term has ended");
            expect(screen.queryByRole("button", { name: PARITY_COPY.legislators.searchAgain })).toBeNull();
        });

        it("handles history error state and retry click", () => {
            const onRetryHistory = vi.fn<() => void>();
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: false,
                historyFailed: true,
                currentHistory: undefined,
                onRetryHistory,
            });

            render(<Component {...props} />);
            expect(screen.getByText(PARITY_COPY.legislators.historyLoadError)).toBeInTheDocument();

            const retryBtn = screen.getByRole("button", { name: PARITY_COPY.legislators.historyRetry });
            fireEvent.click(retryBtn);
            expect(onRetryHistory).toHaveBeenCalledTimes(1);
        });

        it("handles history multi-session rendering with ended stamps", () => {
            const props = createProps({
                activeTab: "history",
                isHistoryLoading: false,
                historyFailed: false,
                currentHistory: {
                    sessions: [
                        {
                            session_label: "2020–2024 Session",
                            entries: [
                                {
                                    legislator: SAMPLE_LEGISLATORS[0],
                                    term: {
                                        term_start_year: 2020,
                                        term_end_year: 2024,
                                    } as unknown as sway.legislatorHistory.ITerm,
                                    score: {
                                        count_agreed: 10,
                                        count_disagreed: 1,
                                        count_no_legislator_vote: 0,
                                    } as unknown as sway.scoring.IAgreeable,
                                    ended_reason: "term_ended",
                                },
                            ],
                        },
                        {
                            session_label: "2016–2020 Session",
                            entries: [
                                {
                                    legislator: SAMPLE_LEGISLATORS[1],
                                    term: {
                                        term_start_year: 2016,
                                        term_end_year: 2020,
                                    } as unknown as sway.legislatorHistory.ITerm,
                                    score: {
                                        count_agreed: 5,
                                        count_disagreed: 5,
                                        count_no_legislator_vote: 0,
                                    } as unknown as sway.scoring.IAgreeable,
                                    ended_reason: "term_ended",
                                },
                            ],
                        },
                    ],
                },
            });

            render(<Component {...props} />);
            expect(screen.getByText("2020–2024 Session")).toBeInTheDocument();
            expect(screen.getByText("2016–2020 Session")).toBeInTheDocument();
            expect(screen.getAllByTestId("legislator-card-ended-stamp")).toHaveLength(2);
        });
    });
});
