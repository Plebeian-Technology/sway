// @lat: [[theme-driven-bill-layout-selection#Theme-driven layout selection on Bill.tsx and Bills.tsx]]
// @lat: [[bill-list-layouts-design#MonochromeBillListLayout.tsx]]

import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import * as React from "react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { sway } from "sway";

import { Support } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { THEMES, type ThemeId } from "app/frontend/styles/themes";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { billListLayoutFor } from "app/frontend/components/bill/list-layouts/index";
import {
    BILLS_LOAD_MORE_LABEL,
    BILLS_LOADING_MORE_LABEL,
    BILLS_SEARCH_PLACEHOLDER,
    DEFAULT_BILLS_SORT,
    type BillListLayoutProps,
    type ILegislativeSessionOption,
} from "app/frontend/components/bill/list-layouts/types";

let deferredResolved = true;
let mockUser: { is_admin?: boolean } | null = null;

vi.mock("@inertiajs/react", () => ({
    Deferred: ({ children, fallback }: { data: string; children: React.ReactNode; fallback?: React.ReactNode }) =>
        deferredResolved ? children : fallback,
    router: {
        on: vi.fn<() => void>(),
        reload: vi.fn<() => void>(),
    },
    usePage: () => ({
        props: {
            user: mockUser,
            errors: {},
        },
    }),
    Link: ({
        children,
        href,
        "aria-label": ariaLabel,
        className,
    }: {
        children?: React.ReactNode;
        href?: string;
        "aria-label"?: string;
        className?: string;
    }) => (
        <a href={href} aria-label={ariaLabel} className={className}>
            {children}
        </a>
    ),
}));

await Promise.all([
    import("app/frontend/components/bill/list-layouts/BannerBillListLayout"),
    import("app/frontend/components/bill/list-layouts/BallotBillListLayout"),
    import("app/frontend/components/bill/list-layouts/CornerstoreBillListLayout"),
    import("app/frontend/components/bill/list-layouts/MonochromeBillListLayout"),
    import("app/frontend/components/bill/list-layouts/ServiceManualBillListLayout"),
    import("app/frontend/components/bill/list-layouts/SwissGridBillListLayout"),
]);

const SAMPLE_BILLS: sway.IBill[] = [
    {
        id: 101,
        external_id: "26-0101",
        title: "Clean Air and Green Canopy Act FOR the purpose of expanding urban forestry and tracking particulate matter in industrial zones.",
        summary: "Expands urban tree canopy and tracks industrial particulate emissions.",
        chamber: "council",
        categories: ["Environment", "Health"],
        legislator_id: 5,
        introduced_date_time_utc: "2026-03-15T10:00:00Z",
        scheduled_release_date_utc: "2026-09-08",
        active: true,
        bill_score: {
            for: 1420000,
            against: 310000,
            comparison_suppressed: false,
            voters_needed: 0,
        } as unknown as sway.IBillScore,
        user_vote: {
            support: Support.For,
        } as unknown as sway.IApiUserVote,
    } as unknown as sway.IBill,
    {
        id: 102,
        external_id: "26-0102",
        title: "Commercial Corridor Revitalization Act – Facade Improvement Grants",
        summary: "Provides capital grants for facade repairs on commercial thoroughfares.",
        chamber: "senate",
        categories: ["Economic Development"],
        legislator_id: 8,
        introduced_date_time_utc: "2026-04-01T14:30:00Z",
        active: true,
        bill_score: {
            for: 85,
            against: 92,
            comparison_suppressed: false,
            voters_needed: 0,
        } as unknown as sway.IBillScore,
    } as unknown as sway.IBill,
];

const READABILITY_LIST_THEMES: {
    themeId: ThemeId;
    name: string;
    Component: React.ComponentType<BillListLayoutProps>;
    cssFile: string;
}[] = [
    {
        themeId: "monochrome",
        name: "MonochromeBillListLayout",
        Component: MonochromeBillListLayout,
        cssFile: "monochrome-list-layout.css",
    },
    {
        themeId: "service-manual",
        name: "ServiceManualBillListLayout",
        Component: ServiceManualBillListLayout,
        cssFile: "service-manual-list-layout.css",
    },
    {
        themeId: "swiss-grid",
        name: "SwissGridBillListLayout",
        Component: SwissGridBillListLayout,
        cssFile: "swiss-grid-list-layout.css",
    },
];

const ALL_LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

const SESSIONS: ILegislativeSessionOption[] = [
    { id: 10, name: "2026 Regular Session", active: true },
    { id: 9, name: "2025 Regular Session", active: false },
];

const CATEGORIES = ["Environment", "Health", "Economic Development"];

const createProps = (overrides: Partial<BillListLayoutProps> = {}): BillListLayoutProps => ({
    bills: SAMPLE_BILLS,
    formattedSwayLocaleName: "Baltimore City",
    localeOptions: [
        { value: 1, label: "Baltimore City" },
        { value: 2, label: "Maryland" },
    ],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(swayLocaleId: number) => void>(),
    allCategories: CATEGORIES,
    selectedCategories: ["Environment"],
    onToggleCategory: vi.fn<(category: string) => void>(),
    onClearCategories: vi.fn<() => void>(),
    hasMoreBills: true,
    isLoadingMoreBills: false,
    onLoadMoreBills: vi.fn<() => void>(),
    sortValue: DEFAULT_BILLS_SORT,
    onSortChange: vi.fn<(value: BillListLayoutProps["sortValue"]) => void>(),
    searchValue: "",
    onSearchChange: vi.fn<(term: string) => void>(),
    listMode: "all_bills",
    legislativeSessions: SESSIONS,
    selectedLegislativeSessionId: 10,
    onLegislativeSessionChange: vi.fn<(sessionId: number) => void>(),
    ...overrides,
});

describe("Empirical Challenge: Readability Bill List Layouts (Add Monochrome, Service Manual, Swiss Notice bill list layouts)", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        deferredResolved = true;
        mockUser = null;
        document.documentElement.dataset.theme = "sway";
    });

    afterEach(cleanup);

    describe("1. Distinct Layout Resolution across all registered themes", () => {
        it("resolves distinct layout components for all 6 registered themes and Default for sway", () => {
            const allThemeIds = THEMES.map((t) => t.id);
            expect(allThemeIds).toContain("monochrome");
            expect(allThemeIds).toContain("service-manual");
            expect(allThemeIds).toContain("swiss-grid");

            expect(billListLayoutFor("sway")).toBe(DefaultBillListLayout);
            expect(billListLayoutFor("monochrome")).not.toBe(DefaultBillListLayout);
            expect(billListLayoutFor("service-manual")).not.toBe(DefaultBillListLayout);
            expect(billListLayoutFor("swiss-grid")).not.toBe(DefaultBillListLayout);

            const resolvedList = allThemeIds.map((id) => billListLayoutFor(id));
            const uniqueSet = new Set(resolvedList);
            expect(uniqueSet.size).toBe(7);
        });

        it("lazy-resolves monochrome, service-manual, and swiss-grid via Suspense", async () => {
            for (const { themeId } of READABILITY_LIST_THEMES) {
                const Layout = billListLayoutFor(themeId);
                const props = createProps();

                render(
                    <React.Suspense fallback={<div data-testid="lazy-loading" />}>
                        <Layout {...props} />
                    </React.Suspense>,
                );

                await waitFor(() => expect(screen.queryByTestId("lazy-loading")).toBeNull());
                expect(screen.getByTestId("input-search-bills")).toBeInTheDocument();
                cleanup();
            }
        });

        it("gracefully falls back to DefaultBillListLayout for unknown or empty theme IDs", () => {
            expect(billListLayoutFor("" as ThemeId)).toBe(DefaultBillListLayout);
            expect(billListLayoutFor("unknown-theme" as ThemeId)).toBe(DefaultBillListLayout);
            expect(billListLayoutFor("custom" as ThemeId)).toBe(DefaultBillListLayout);
        });
    });

    describe("2. Token Reference Integrity Oracle", () => {
        const THEMES_DIR = resolve(__dirname, "../../../../styles/themes");
        const TOKENS_CSS = resolve(THEMES_DIR, "..", "tokens.css");
        const declared = new Set<string>();

        const declaredIn = (css: string): Set<string> => new Set(css.match(/--[a-z0-9-]+(?=\s*:)/g) ?? []);
        const referencedIn = (css: string): Set<string> =>
            new Set((css.match(/var\(\s*--[a-z0-9-]+/g) ?? []).map((m) => m.replace(/var\(\s*/, "")));

        for (const file of [
            "sway.css",
            "banner.css",
            "ballot.css",
            "cornerstore.css",
            "monochrome.css",
            "service-manual.css",
            "swiss-grid.css",
        ]) {
            const css = readFileSync(resolve(THEMES_DIR, file), "utf8");
            for (const token of declaredIn(css)) declared.add(token);
        }
        for (const token of declaredIn(readFileSync(TOKENS_CSS, "utf8"))) {
            declared.add(token);
        }

        it.each(READABILITY_LIST_THEMES)("stylesheet $cssFile references only declared tokens", ({ cssFile }) => {
            const cssPath = resolve(__dirname, "..", cssFile);
            const content = readFileSync(cssPath, "utf8");
            const locals = declaredIn(content);
            const dead = [...referencedIn(content)].filter((t) => !declared.has(t) && !locals.has(t));

            expect(dead).toEqual([]);
        });
    });

    describe("3. Deferred First Paint & Fallback Contract (All 7 Layouts)", () => {
        describe.each(ALL_LAYOUTS)("%s", (_name, Layout) => {
            it("renders loading fallback with aria-busy, aria-live, loading copy, and >= 6 placeholders while deferred", () => {
                deferredResolved = false;
                const props = createProps({ bills: [] });
                const { container } = render(<Layout {...props} />);

                expect(screen.getByText(PARITY_COPY.bills.loading)).toBeInTheDocument();
                expect(screen.queryByText(PARITY_COPY.bills.noneFound(props.formattedSwayLocaleName))).toBeNull();

                const busyContainer = container.querySelector("[aria-busy='true']");
                expect(busyContainer).not.toBeNull();
                expect(busyContainer).toHaveAttribute("aria-live", "polite");

                const placeholders = container.querySelectorAll(".placeholder-block");
                expect(placeholders.length).toBeGreaterThanOrEqual(6);
            });

            it("renders empty state copy and removes skeletons once resolved with zero bills", () => {
                deferredResolved = true;
                const props = createProps({ bills: [] });
                const { container } = render(<Layout {...props} />);

                expect(
                    screen.getByText(PARITY_COPY.bills.noneFound(props.formattedSwayLocaleName)),
                ).toBeInTheDocument();
                expect(screen.queryByText(PARITY_COPY.bills.loading)).toBeNull();

                expect(container.querySelectorAll(".placeholder-block")).toHaveLength(0);
                expect(container.querySelector("[aria-busy='true']")).toBeNull();
            });

            it("renders count and bill rows once resolved with bills", () => {
                deferredResolved = true;
                const props = createProps();
                const { container } = render(<Layout {...props} />);

                expect(
                    screen.getByText(
                        PARITY_COPY.bills.showingCount(SAMPLE_BILLS.length, props.formattedSwayLocaleName),
                    ),
                ).toBeInTheDocument();

                expect(container.querySelectorAll(".placeholder-block")).toHaveLength(0);
                expect(container.querySelector("[aria-busy='true']")).toBeNull();
            });

            // @lat: [[voter-privacy-threshold#Bill lists print one line for a hidden tally]]
            it("prints one line and no count for a bill under ten voters, and leaves other rows as they were", () => {
                deferredResolved = true;
                const hiddenScore = {
                    for: 7777,
                    against: 3333,
                    comparison_suppressed: true,
                    voters_needed: 4,
                } as unknown as sway.IBillScore;
                const bills = [{ ...SAMPLE_BILLS[0], bill_score: hiddenScore }, SAMPLE_BILLS[1]];

                const { container } = render(<Layout {...createProps({ bills })} />);

                expect(
                    screen.getAllByText("Visual comparisons will be shown when 4 more users have voted."),
                ).toHaveLength(1);
                const text = container.textContent ?? "";
                expect(text).not.toMatch(/7,?777/);
                expect(text).not.toMatch(/3,?333/);
                expect(text).toContain("85");
                expect(text).toContain("92");
                expect(text).not.toContain("Invite others by sharing Sway");
                expect(screen.queryByRole("button", { name: "Copy invite link" })).toBeNull();
                expect(screen.queryByRole("link", { name: "Sign up" })).toBeNull();
            });

            it("says 'Not enough votes yet' for a row whose score carries no flag", () => {
                deferredResolved = true;
                const unflaggedScore = { for: 7777, against: 3333 } as unknown as sway.IBillScore;

                const { container } = render(
                    <Layout {...createProps({ bills: [{ ...SAMPLE_BILLS[0], bill_score: unflaggedScore }] })} />,
                );

                expect(screen.getAllByText("Not enough votes yet")).toHaveLength(1);
                expect(container.textContent ?? "").not.toMatch(/7,?777/);
            });

            it("renders the Bill of the Month featured date on each card in past_bills_of_the_month mode and omits it in all_bills mode", () => {
                deferredResolved = true;
                const { container, unmount } = render(
                    <Layout {...createProps({ listMode: "past_bills_of_the_month" })} />,
                );

                const timeEl = container.querySelector("time[datetime='2026-09-08']");
                expect(timeEl).not.toBeNull();
                expect(timeEl?.textContent).toContain("Featured September 08, 2026");
                unmount();

                const { container: allBillsContainer } = render(<Layout {...createProps({ listMode: "all_bills" })} />);
                expect(allBillsContainer.querySelector("time[datetime='2026-09-08']")).toBeNull();
            });
        });
    });

    describe.each(READABILITY_LIST_THEMES)(
        "4. Interactive Controls & Event Forwarding for $name ($themeId)",
        ({ Component, themeId }) => {
            it("forwards search changes from BillsSearchInput", () => {
                const onSearchChange = vi.fn<(term: string) => void>();
                const props = createProps({ onSearchChange, searchValue: "initial" });
                render(<Component {...props} />);

                const input = screen.getByTestId("input-search-bills") as HTMLInputElement;
                expect(input.value).toBe("initial");
                expect(input.placeholder).toBe(BILLS_SEARCH_PLACEHOLDER);

                fireEvent.change(input, { target: { value: "housing" } });
                expect(onSearchChange).toHaveBeenCalledTimes(1);
                expect(onSearchChange).toHaveBeenCalledWith("housing");
            });

            it("forwards sort changes from BillsSortSelect", () => {
                const onSortChange = vi.fn<(value: BillListLayoutProps["sortValue"]) => void>();
                const props = createProps({ onSortChange, sortValue: DEFAULT_BILLS_SORT });
                render(<Component {...props} />);

                const select = screen.getByTestId("select-sort-bills") as HTMLSelectElement;
                expect(select.value).toBe(DEFAULT_BILLS_SORT);

                fireEvent.change(select, { target: { value: "title:asc" } });
                expect(onSortChange).toHaveBeenCalledTimes(1);
                expect(onSortChange).toHaveBeenCalledWith("title:asc");
            });

            it("forwards session changes when legislativeSessions exist in all_bills mode", () => {
                const onLegislativeSessionChange = vi.fn<(sessionId: number) => void>();
                const props = createProps({
                    listMode: "all_bills",
                    legislativeSessions: SESSIONS,
                    selectedLegislativeSessionId: 10,
                    onLegislativeSessionChange,
                });
                render(<Component {...props} />);

                const select = screen.getByTestId("select-legislative-session") as HTMLSelectElement;
                expect(select.value).toBe("10");

                fireEvent.change(select, { target: { value: "9" } });
                expect(onLegislativeSessionChange).toHaveBeenCalledTimes(1);
                expect(onLegislativeSessionChange).toHaveBeenCalledWith(9);
            });

            it("omits session select in past_bills_of_the_month mode", () => {
                const props = createProps({
                    listMode: "past_bills_of_the_month",
                    legislativeSessions: SESSIONS,
                });
                render(<Component {...props} />);

                expect(screen.queryByTestId("select-legislative-session")).toBeNull();
            });

            it("omits session select when legislativeSessions array is empty", () => {
                const props = createProps({
                    listMode: "all_bills",
                    legislativeSessions: [],
                });
                render(<Component {...props} />);

                expect(screen.queryByTestId("select-legislative-session")).toBeNull();
            });

            it("forwards locale changes from SwayLocalePicker", () => {
                const onLocaleChange = vi.fn<(swayLocaleId: number) => void>();
                const props = createProps({ onLocaleChange, selectedSwayLocaleId: 1 });
                const { container } = render(<Component {...props} />);

                const select = container.querySelector("select[id$='-locale']") as HTMLSelectElement;
                expect(select).not.toBeNull();
                expect(select.value).toBe("1");

                fireEvent.change(select, { target: { value: "2" } });
                expect(onLocaleChange).toHaveBeenCalledTimes(1);
                expect(onLocaleChange).toHaveBeenCalledWith(2);
            });

            it("forwards category selection and clear from CategoryMultiSelect", () => {
                const onToggleCategory = vi.fn<(category: string) => void>();
                const onClearCategories = vi.fn<() => void>();
                const props = createProps({
                    allCategories: CATEGORIES,
                    selectedCategories: ["Environment"],
                    onToggleCategory,
                    onClearCategories,
                });
                render(<Component {...props} />);

                const filterButton = screen.getByTestId("bills-category-filter");
                expect(filterButton).toHaveTextContent("Environment");

                fireEvent.click(filterButton);

                const healthBox = screen.getByRole("checkbox", { name: "Health" });
                expect(healthBox).not.toBeChecked();
                fireEvent.click(healthBox);
                expect(onToggleCategory).toHaveBeenCalledWith("Health");

                const clearBtn = screen.getByRole("button", { name: "Clear all" });
                fireEvent.click(clearBtn);
                expect(onClearCategories).toHaveBeenCalledTimes(1);
            });

            it("renders load-more button and forwards clicks when hasMoreBills is true", () => {
                const onLoadMoreBills = vi.fn<() => void>();
                const props = createProps({
                    hasMoreBills: true,
                    isLoadingMoreBills: false,
                    onLoadMoreBills,
                });
                render(<Component {...props} />);

                const button = screen.getByTestId("btn-load-more-bills");
                expect(button).toBeEnabled();
                expect(button).toHaveTextContent(BILLS_LOAD_MORE_LABEL);

                fireEvent.click(button);
                expect(onLoadMoreBills).toHaveBeenCalledTimes(1);
            });

            it("disables load-more button and renders loading label when isLoadingMoreBills is true", () => {
                const props = createProps({
                    hasMoreBills: true,
                    isLoadingMoreBills: true,
                });
                render(<Component {...props} />);

                const button = screen.getByTestId("btn-load-more-bills");
                expect(button).toBeDisabled();
                expect(button).toHaveTextContent(BILLS_LOADING_MORE_LABEL);
            });

            it("omits load-more button when hasMoreBills is false", () => {
                const props = createProps({
                    hasMoreBills: false,
                });
                render(<Component {...props} />);

                expect(screen.queryByTestId("btn-load-more-bills")).toBeNull();
            });

            it("uses theme-specific select class name on controls", () => {
                document.documentElement.dataset.theme = themeId;
                const props = createProps({
                    legislativeSessions: SESSIONS,
                });
                const { container } = render(<Component {...props} />);

                const expectedClass = `${themeId}-select`;
                const selects = container.querySelectorAll("select");
                expect(selects.length).toBeGreaterThan(0);
                for (const select of selects) {
                    expect(select.className).toContain(expectedClass);
                }
            });
        },
    );

    describe.each(READABILITY_LIST_THEMES)("5. Admin Edit Link Authorization Gating for $name", ({ Component }) => {
        it("renders distinctly named edit links pointing to admin creator when signed in as admin", () => {
            mockUser = { is_admin: true };
            const props = createProps();
            render(<Component {...props} />);

            const editLink1 = screen.getByRole("link", { name: "Edit bill 26-0101" });
            const editLink2 = screen.getByRole("link", { name: "Edit bill 26-0102" });

            expect(editLink1).toHaveAttribute("href", "/admin/bill_creator/101/creator");
            expect(editLink2).toHaveAttribute("href", "/admin/bill_creator/102/creator");
        });

        it("omits edit links when signed in as non-admin", () => {
            mockUser = { is_admin: false };
            const props = createProps();
            render(<Component {...props} />);

            expect(screen.queryByRole("link", { name: /Edit bill/ })).toBeNull();
        });

        it("omits edit links when signed out", () => {
            mockUser = null;
            const props = createProps();
            render(<Component {...props} />);

            expect(screen.queryByRole("link", { name: /Edit bill/ })).toBeNull();
        });
    });

    describe.each(READABILITY_LIST_THEMES)("6. Copy Authenticity & Resilience for $name", ({ Component }) => {
        it("renders authentic PARITY_COPY.bills.allBillsTitle for all_bills listMode", () => {
            render(<Component {...createProps({ listMode: "all_bills" })} />);
            expect(screen.getAllByText(PARITY_COPY.bills.allBillsTitle).length).toBeGreaterThan(0);
        });

        it("renders authentic PARITY_COPY.bills.pastBillsOfTheMonthTitle for past_bills_of_the_month", () => {
            render(<Component {...createProps({ listMode: "past_bills_of_the_month" })} />);
            expect(screen.getAllByText(PARITY_COPY.bills.pastBillsOfTheMonthTitle).length).toBeGreaterThan(0);
        });

        it("renders showingCount when bills are present and noneFound when empty", () => {
            const { unmount } = render(<Component {...createProps({ bills: SAMPLE_BILLS })} />);
            expect(
                screen.getByText(PARITY_COPY.bills.showingCount(SAMPLE_BILLS.length, "Baltimore City")),
            ).toBeInTheDocument();
            unmount();

            render(<Component {...createProps({ bills: [] })} />);
            expect(screen.getByText(PARITY_COPY.bills.noneFound("Baltimore City"))).toBeInTheDocument();
        });

        it("contains zero forbidden editorial kickers", () => {
            render(<Component {...createProps()} />);
            const text = document.body.textContent ?? "";

            expect(text).not.toContain("Accountability Ledger");
            expect(text).not.toContain("The Legislative Record");
            expect(text).not.toContain("Official ballot");
            expect(text).not.toContain("On the floor");
            expect(text).not.toContain("You & the vote");
            expect(text).not.toContain("Why it matters");
            expect(text).not.toContain("Cut through the noise");
        });

        it("strips Maryland boilerplate and displays short title in BillEntryTitle", () => {
            const props = createProps();
            render(<Component {...props} />);

            expect(screen.getByText("Clean Air and Green Canopy Act")).toBeInTheDocument();
            expect(document.body.textContent).not.toContain("FOR the purpose of expanding");
        });

        it("formats large vote tally numbers with locale commas", () => {
            const props = createProps();
            render(<Component {...props} />);

            expect(document.body.textContent).toContain("1,420,000 for · 310,000 against");
        });

        it("indicates when user vote is recorded", () => {
            const props = createProps();
            render(<Component {...props} />);

            expect(document.body.textContent).toContain("Vote recorded");
        });

        it("safely handles bills with missing optional fields without runtime errors", () => {
            const strippedBill = {
                id: 999,
                external_id: "26-9999",
                title: "Bare Minimal Title",
                chamber: undefined,
                summary: undefined,
                introduced_date_time_utc: undefined,
                bill_score: undefined,
                user_vote: undefined,
            } as unknown as sway.IBill;

            const props = createProps({ bills: [strippedBill] });
            const { container } = render(<Component {...props} />);

            expect(screen.getByText("Bare Minimal Title")).toBeInTheDocument();
            expect(container.querySelector(".placeholder-block")).toBeNull();
        });
    });
});
