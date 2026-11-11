// @lat: [[bills-test-category-filter-design#Why categoryFilterHref.ts builds the URL the way it does]]

import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, screen } from "@testing-library/react";

import { renderV2, resetInertiaStubs, type InertiaStubs } from "app/frontend/__tests__/test-utils";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

// --- Inertia stubs (hoisted above all imports) ---

const inertia: InertiaStubs = vi.hoisted(() => ({
    usePage: vi.fn<() => { props: Record<string, unknown>; url: string }>(() => ({
        props: {} as Record<string, unknown>,
        url: "/bills",
    })),
    router: {
        visit: vi.fn<(...args: unknown[]) => void>(),
        post: vi.fn<(...args: unknown[]) => void>(),
        put: vi.fn<(...args: unknown[]) => void>(),
        patch: vi.fn<(...args: unknown[]) => void>(),
        delete: vi.fn<(...args: unknown[]) => void>(),
        get: vi.fn<(...args: unknown[]) => void>(),
        reload: vi.fn<(...args: unknown[]) => void>(),
        on: vi.fn<(type: string, callback: (event: Event) => void) => () => void>((type, callback) => {
            const eventName = `inertia:${type}`;
            document.addEventListener(eventName, callback as EventListener);
            return () => document.removeEventListener(eventName, callback as EventListener);
        }),
    },
}));

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = await importActual<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: inertia.usePage,
        router: inertia.router,
        // Replace Deferred with something that renders its children immediately. The
        // real Deferred waits until Inertia says the delayed prop has arrived, which
        // never happens in a unit test. Without this, no bill card ever appears and
        // the filter checks quietly compare zero against zero.
        Deferred: ({ children }: { children: React.ReactNode }) => <>{children}</>,
        Link: ({ children, href, ...rest }: { children: unknown; href: string; [key: string]: unknown }) => (
            <a href={href} data-inertia-link {...(rest as Record<string, unknown>)}>
                {children as React.ReactNode}
            </a>
        ),
    };
});

// --- Hook mocks ---

vi.mock("app/frontend/hooks/useScoreSubscription", () => ({
    useScoreSubscription: () => false,
}));

vi.mock("app/frontend/hooks/useSwayLocales", () => ({
    useSwayLocale: () => [null, vi.fn<() => void>()],
    useSwayLocales: () => ({ options: [] }),
}));

// Force the "sway" theme so we always get DefaultBillListLayout.
vi.mock("app/frontend/hooks/useActiveThemeId", () => ({
    useActiveThemeId: () => "sway",
}));

import Bills from "app/frontend/pages/Bills";
import type { sway } from "sway";

// --- Test data ---

// The single category field is "infrastructure" on ALL bills, deliberately unlike
// the categories[] arrays. So the old broken check, `categories.includes(bill.category)`,
// finds nothing when filtering by "health" or "housing", while the correct `.some`
// check finds the expected number.
const makeBill = (id: number, title: string, categories: string[]): sway.IBill => ({
    id,
    external_id: `SB-${id}`,
    external_version: "0",
    title,
    link: `/bills/${id}`,
    chamber: "senate",
    vote_date_time_utc: "",
    introduced_date_time_utc: "",
    withdrawn_date_time_utc: "",
    house_vote_date_time_utc: "",
    senate_vote_date_time_utc: "",
    // Deliberately "infrastructure", which is not in ["health","housing"], so the
    // old `categories.includes(bill.category)` check is always false.
    category: "infrastructure",
    categories,
    status: "passed",
    active: true,
    legislator_id: 1,
    sway_locale_id: 1,
    scheduled_release_date_utc: "",
});

// @lat: [[bills-test-category-filter-design#Why categoryFilterHref.ts builds the URL the way it does]]
const billA = makeBill(1, "Bill A", ["Health"]);
const billB = makeBill(2, "Bill B", ["Housing"]);
const billC = makeBill(3, "Bill C", ["Health", "Housing"]);

const ALL_BILLS = [billA, billB, billC];
// Category names arrive from the server already capitalised for display and are
// shown exactly as they come; nothing re-cases them. The option label, the
// bill.categories arrays and the URL parameter all carry the same values.
const ALL_CATEGORIES = ["Health", "Housing"];

// The fake browser starts at http://localhost/. Each test sets the URL it wants
// with pushState, and beforeEach resets to a plain /bills so one test's filter does
// not leak into the next.
const setUrl = (url: string) => window.history.pushState({}, "", url);

beforeEach(() => {
    resetInertiaStubs(inertia);
    setUrl("/bills");
});

describe("Bills — renders filtered from the URL", () => {
    it("(a) no categories param → all bills render", () => {
        const { getByText, queryByText } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        expect(getByText(/Showing 3 bills/)).toBeTruthy();
        expect(queryByText("Bill A")).not.toBeNull();
        expect(queryByText("Bill B")).not.toBeNull();
        expect(queryByText("Bill C")).not.toBeNull();
    });

    it("(b) ?categories=Health → only bills matching that category render (OR-intersection, not .every / not bill.category)", () => {
        setUrl("/bills?categories=Health");
        const { getByText, queryByText } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        // billA (["health"]) ✓; billB (["housing"]) ✗; billC (["health","housing"]) ✓
        // .every would give 1 bill; categories.includes(bill.category) would give 0
        expect(getByText(/Showing 2 bills/)).toBeTruthy();
        expect(queryByText("Bill A")).not.toBeNull();
        expect(queryByText("Bill B")).toBeNull();
        expect(queryByText("Bill C")).not.toBeNull();
    });

    it("(c) ?categories=Health,Housing → OR union of both", () => {
        setUrl("/bills?categories=Health,Housing");
        const { getByText, queryByText } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        expect(getByText(/Showing 3 bills/)).toBeTruthy();
        expect(queryByText("Bill A")).not.toBeNull();
        expect(queryByText("Bill B")).not.toBeNull();
        expect(queryByText("Bill C")).not.toBeNull();
    });
});

// Opening the multi-select is a prerequisite for every toggle below: the options
// only exist while the popover is open.
const openCategoryFilter = () => fireEvent.click(screen.getByTestId("bills-category-filter"));

describe("Bills — ticking a category pushes the URL via router.get", () => {
    it("selecting a category navigates to a URL carrying it + preserves the deferred list", () => {
        renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        openCategoryFilter();
        fireEvent.click(screen.getByRole("checkbox", { name: "Health" }));

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url, data, options] = inertia.router.get.mock.calls[0];
        expect(url).toContain("categories=Health");
        expect(data).toEqual({});
        expect(options).toMatchObject({
            preserveScroll: true,
            preserveState: true,
            only: ["all_categories"],
        });
    });

    it("clearing the last category navigates to a URL with no categories param", () => {
        setUrl("/bills?categories=Health");
        renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        // "Health" is currently ticked; unticking it removes the only value.
        openCategoryFilter();
        fireEvent.click(screen.getByRole("checkbox", { name: "Health" }));

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        expect(url).not.toContain("categories=");
    });

    it("selecting a second category appends to the existing selection", () => {
        setUrl("/bills?categories=Health");
        renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        openCategoryFilter();
        fireEvent.click(screen.getByRole("checkbox", { name: "Housing" }));

        const [url] = inertia.router.get.mock.calls[0];
        // URLSearchParams escapes the comma, so decode before checking both values are there.
        const decoded = decodeURIComponent(url as string);
        expect(decoded).toContain("categories=Health,Housing");
    });
});

// The default theme routes each bill through BillCard, which is where
// BillEditLink lives on this layout. resetInertiaStubs leaves
// usePage returning no user, so a test that doesn't opt in stays signed-out.
describe("Bills — admin edit link on each row", () => {
    it("shows an edit link naming each bill to a sway admin", () => {
        inertia.usePage.mockReturnValue({ props: { user: { is_admin: true } }, url: "/bills" });
        const { getByRole } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        expect(getByRole("link", { name: "Edit bill SB-1" })).toHaveAttribute("href", "/admin/bill_creator/1/creator");
        expect(getByRole("link", { name: "Edit bill SB-2" })).toBeTruthy();
        expect(getByRole("link", { name: "Edit bill SB-3" })).toBeTruthy();
    });

    it("shows no edit link to a signed-in non-admin", () => {
        inertia.usePage.mockReturnValue({ props: { user: { is_admin: false } }, url: "/bills" });
        const { queryByRole } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        expect(queryByRole("link", { name: /Edit bill/ })).toBeNull();
    });

    it("shows no edit link to a signed-out reader", () => {
        const { queryByRole } = renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        expect(queryByRole("link", { name: /Edit bill/ })).toBeNull();
    });
});

describe("Bills — sorting, searching, and pagination with namespaced query parameters", () => {
    it("choosing default order removes both sort names from the address", () => {
        setUrl("/bills?bills_sort=title&bills_direction=asc&sort=title&direction=asc");
        renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        const sortSelect = screen.getByTestId("select-sort-bills");
        fireEvent.change(sortSelect, { target: { value: "introduced_date_time_utc:desc" } });

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        const search = (url as string).split("?")[1] ? `?${(url as string).split("?")[1]}` : "";
        const params = new URLSearchParams(search);
        expect(isQueryParamCleared(params, "bills_sort")).toBe(true);
        expect(isQueryParamCleared(params, "bills_direction")).toBe(true);
        expect(isQueryParamCleared(params, "sort")).toBe(true);
        expect(isQueryParamCleared(params, "direction")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills");
    });

    it("choosing a non-default order writes canonical bills_sort and bills_direction and removes legacy aliases", () => {
        setUrl("/bills?sort=introduced_date_time_utc&direction=desc");
        renderV2(
            <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
        );

        const sortSelect = screen.getByTestId("select-sort-bills");
        fireEvent.change(sortSelect, { target: { value: "title:asc" } });

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("bills_sort")).toBe("title");
        expect(params.get("bills_direction")).toBe("asc");
        expect(isQueryParamCleared(params, "sort")).toBe(true);
        expect(isQueryParamCleared(params, "direction")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills?bills_sort=title&bills_direction=asc");
    });

    it("searching writes bills_search and removes legacy search", () => {
        vi.useFakeTimers();
        try {
            setUrl("/bills?search=old_query");
            renderV2(
                <Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={ALL_BILLS.length} filters={{}} />,
            );

            const searchInput = screen.getByTestId("input-search-bills");
            expect(searchInput).not.toBeNull();
            fireEvent.change(searchInput, { target: { value: "education" } });

            vi.advanceTimersByTime(400);

            expect(inertia.router.get).toHaveBeenCalledTimes(1);
            const [url] = inertia.router.get.mock.calls[0];
            const params = new URLSearchParams((url as string).split("?")[1]);
            expect(params.get("bills_search")).toBe("education");
            expect(isQueryParamCleared(params, "search")).toBe(true);
            expect(stripClearedQueryParams(url as string)).toBe("/bills?bills_search=education");
        } finally {
            vi.useRealTimers();
        }
    });

    it("loading more bills increments bills_page and deletes legacy page", () => {
        setUrl("/bills?bills_page=1&page=1");
        renderV2(<Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={10} filters={{}} />);

        const loadMoreButton = screen.getByTestId("btn-load-more-bills");
        fireEvent.click(loadMoreButton);

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("bills_page")).toBe("2");
        expect(params.get("page")).toBeNull();
    });

    it("loading more bills respects legacy page if bills_page is absent", () => {
        setUrl("/bills?page=2");
        renderV2(<Bills bills={ALL_BILLS} all_categories={ALL_CATEGORIES} bills_total={10} filters={{}} />);

        const loadMoreButton = screen.getByTestId("btn-load-more-bills");
        fireEvent.click(loadMoreButton);

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("bills_page")).toBe("3");
        expect(params.get("page")).toBeNull();
    });
});

describe("Bills — list modes and legislative session selector", () => {
    const SESSIONS = [
        { id: 10, name: "2026 Regular Session", active: true },
        { id: 9, name: "2025 Regular Session", active: false },
    ];

    it("renders 'All Bills' heading and legislative session selector in all_bills mode", () => {
        renderV2(
            <Bills
                bills={ALL_BILLS}
                all_categories={ALL_CATEGORIES}
                bills_total={ALL_BILLS.length}
                list_mode="all_bills"
                legislative_sessions={SESSIONS}
                selected_legislative_session_id={10}
                filters={{}}
            />,
        );

        expect(screen.getByRole("heading", { level: 1, name: "All Bills" })).toBeTruthy();
        const sessionSelect = screen.getByTestId("select-legislative-session") as HTMLSelectElement;
        expect(sessionSelect.value).toBe("10");
    });

    it("renders 'Past Bills of the Month' heading and hides session selector in past_bills_of_the_month mode", () => {
        renderV2(
            <Bills
                bills={ALL_BILLS}
                all_categories={ALL_CATEGORIES}
                bills_total={ALL_BILLS.length}
                list_mode="past_bills_of_the_month"
                legislative_sessions={SESSIONS}
                selected_legislative_session_id={null}
                filters={{}}
            />,
        );

        expect(screen.getByRole("heading", { level: 1, name: "Past Bills of the Month" })).toBeTruthy();
        expect(screen.queryByTestId("select-legislative-session")).toBeNull();
    });

    it("selecting a historical session writes bills_legislative_session_id and resets pagination", () => {
        setUrl("/bills?bills_page=2&legislative_session_id=10");
        renderV2(
            <Bills
                bills={ALL_BILLS}
                all_categories={ALL_CATEGORIES}
                bills_total={ALL_BILLS.length}
                list_mode="all_bills"
                legislative_sessions={SESSIONS}
                selected_legislative_session_id={10}
                filters={{}}
            />,
        );

        const sessionSelect = screen.getByTestId("select-legislative-session");
        fireEvent.change(sessionSelect, { target: { value: "9" } });

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url, , options] = inertia.router.get.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(params.get("bills_legislative_session_id")).toBe("9");
        expect(isQueryParamCleared(params, "legislative_session_id")).toBe(true);
        expect(isQueryParamCleared(params, "bills_page")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills?bills_legislative_session_id=9");
        expect(options).toMatchObject({
            only: ["bills", "bills_total", "selected_legislative_session_id"],
            preserveScroll: true,
            preserveState: true,
            replace: true,
        });
    });

    it("selecting the active session clears bills_legislative_session_id from the URL", () => {
        setUrl("/bills?bills_legislative_session_id=9");
        renderV2(
            <Bills
                bills={ALL_BILLS}
                all_categories={ALL_CATEGORIES}
                bills_total={ALL_BILLS.length}
                list_mode="all_bills"
                legislative_sessions={SESSIONS}
                selected_legislative_session_id={9}
                filters={{}}
            />,
        );

        const sessionSelect = screen.getByTestId("select-legislative-session");
        fireEvent.change(sessionSelect, { target: { value: "10" } });

        expect(inertia.router.get).toHaveBeenCalledTimes(1);
        const [url] = inertia.router.get.mock.calls[0];
        const params = new URLSearchParams((url as string).split("?")[1]);
        expect(isQueryParamCleared(params, "bills_legislative_session_id")).toBe(true);
        expect(stripClearedQueryParams(url as string)).toBe("/bills");
    });
});
