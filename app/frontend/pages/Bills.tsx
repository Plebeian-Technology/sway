import { router, usePage } from "@inertiajs/react";
import { createElement, Suspense, useCallback, useState } from "react";

import { billListLayoutFor } from "app/frontend/components/bill/list-layouts";
import ThemeLayoutPlaceholder from "app/frontend/components/bill/ThemeLayoutPlaceholder";
import categoryFilterHref, { CATEGORY_PARAM } from "app/frontend/sway_utils/categoryFilterHref";
import { setQueryParamCleared } from "app/frontend/sway_utils/queryParamClearedSignal";
import {
    BILLS_SORT_VALUES,
    DEFAULT_BILLS_SORT,
    type BillsListMode,
    type ILegislativeSessionOption,
} from "app/frontend/components/bill/list-layouts/types";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { useDebouncedUrlSearch } from "app/frontend/hooks/useDebouncedUrlSearch";
import { useSwayLocale, useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { useUrlSort } from "app/frontend/hooks/useUrlSort";
import { notify, toFormattedLocaleName } from "app/frontend/sway_utils";
import { sway } from "sway";

interface IProps {
    bills: sway.IBill[];
    all_categories: string[];
    bills_total: number;
    list_mode?: BillsListMode;
    legislative_sessions?: ILegislativeSessionOption[];
    selected_legislative_session_id?: number | null;
    filters: {
        search?: string;
        sort?: string;
        direction?: string;
    };
}

const SCORE_PROPS = ["bills"];

const readSelectedCategories = (): string[] => {
    if (typeof window === "undefined") return [];
    const raw = new URLSearchParams(window.location.search).get(CATEGORY_PARAM);
    return raw
        ? raw
              .split(",")
              .map((entry) => entry.trim())
              .filter(Boolean)
        : [];
};

// @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#How much of the list is shown lives in the URL too]]
const BILLS_PAGE_PARAM = "bills_page";
const LEGACY_PAGE_PARAM = "page";
const BILLS_SESSION_PARAM = "bills_legislative_session_id";
const LEGACY_SESSION_PARAM = "legislative_session_id";

const readPage = (): number => {
    if (typeof window === "undefined") return 1;
    const searchParams = new URLSearchParams(window.location.search);
    const raw = Number(searchParams.get(BILLS_PAGE_PARAM) ?? searchParams.get(LEGACY_PAGE_PARAM));
    return Number.isInteger(raw) && raw > 1 ? raw : 1;
};

// @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#How much of the list is shown lives in the URL too]]
const BILLS_RELOAD_PROPS = ["bills", "bills_total", "selected_legislative_session_id"];

const WINDOW_RESET_PARAMS = [BILLS_PAGE_PARAM, LEGACY_PAGE_PARAM];

// @lat: [[bills-controller-design#Testing search, sort, and load-more interactions#Why Bills.tsx declares reload-prop lists at module level]]
const LOCALE_SWITCH_PROPS = [
    "bills",
    "bills_total",
    "all_categories",
    "sway_locale",
    "legislative_sessions",
    "selected_legislative_session_id",
];

const Bills: React.FC<IProps> = ({
    bills,
    all_categories,
    bills_total,
    list_mode = "all_bills",
    legislative_sessions = [],
    selected_legislative_session_id,
}) => {
    const user = usePage<sway.IPageProps>().props?.user;
    useScoreSubscription(SCORE_PROPS, Boolean(user));
    const [swayLocale, getSwayLocale, pendingSwayLocaleId] = useSwayLocale(LOCALE_SWITCH_PROPS);
    const { options } = useSwayLocales();
    const categories = readSelectedCategories();

    // @lat: [[query-parameter-namespaces#Backward compatibility and dual-reading]]
    const { value: sortValue, onChange: sortBills } = useUrlSort({
        options: BILLS_SORT_VALUES,
        defaultValue: DEFAULT_BILLS_SORT,
        only: BILLS_RELOAD_PROPS,
        resetParams: WINDOW_RESET_PARAMS,
        sortParam: "bills_sort",
        directionParam: "bills_direction",
        legacySortAliases: ["sort"],
        legacyDirectionAliases: ["direction"],
        errorTitle: "Could not sort the bills.",
    });
    const { value: searchValue, onChange: searchBills } = useDebouncedUrlSearch({
        param: "bills_search",
        legacyAliases: ["search"],
        only: BILLS_RELOAD_PROPS,
        resetParams: WINDOW_RESET_PARAMS,
        errorTitle: "Could not search the bills.",
    });
    const formattedSwayLocaleName = swayLocale?.name ? toFormattedLocaleName(swayLocale.name) : "your locale";
    const [isLoadingMoreBills, setLoadingMoreBills] = useState(false);

    const hasMoreBills = (bills ?? []).length < (bills_total ?? 0);

    const filteredBills = (bills ?? []).filter(
        (bill) => !categories.length || bill.categories?.some((c) => categories.includes(c)),
    );

    const toggleCategory = useCallback((category: string) => {
        const current = readSelectedCategories();
        const next = current.includes(category)
            ? current.filter((entry) => entry !== category)
            : [...current, category];

        // @lat: [[bills-controller-design#Testing search, sort, and load-more interactions#Why toggleCategory request only asks for all_categories]]
        router.get(
            categoryFilterHref(next, window.location.pathname, window.location.search),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                only: ["all_categories"],
                onError: () => notify({ level: "error", title: "Could not update the category filter." }),
            },
        );
    }, []);

    const clearCategories = useCallback(() => {
        router.get(
            categoryFilterHref([], window.location.pathname, window.location.search),
            {},
            {
                preserveScroll: true,
                preserveState: true,
                only: ["all_categories"],
                onError: () => notify({ level: "error", title: "Could not clear the category filter." }),
            },
        );
    }, []);

    // @lat: [[bills-category-filter#Bills category filter#Why the selection stays in the URL#How much of the list is shown lives in the URL too]]
    const loadMoreBills = useCallback(() => {
        const params = new URLSearchParams(window.location.search);
        params.set(BILLS_PAGE_PARAM, String(readPage() + 1));
        params.delete(LEGACY_PAGE_PARAM);

        router.get(
            `${window.location.pathname}?${params.toString()}`,
            {},
            {
                preserveScroll: true,
                preserveState: true,
                only: BILLS_RELOAD_PROPS,
                onStart: () => setLoadingMoreBills(true),
                onFinish: () => setLoadingMoreBills(false),
                onError: () => notify({ level: "error", title: "Could not load more bills." }),
            },
        );
    }, []);

    const changeLegislativeSession = useCallback(
        (sessionId: number) => {
            const params = new URLSearchParams(window.location.search);
            const defaultActiveSession = legislative_sessions.find((session) => session.active);
            if (defaultActiveSession?.id === sessionId) {
                if (params.has(BILLS_SESSION_PARAM)) {
                    setQueryParamCleared(params, BILLS_SESSION_PARAM);
                }
            } else {
                params.set(BILLS_SESSION_PARAM, String(sessionId));
            }
            for (const key of [LEGACY_SESSION_PARAM, ...WINDOW_RESET_PARAMS]) {
                if (params.has(key)) {
                    setQueryParamCleared(params, key);
                }
            }

            const queryString = params.toString();
            const href = queryString ? `${window.location.pathname}?${queryString}` : window.location.pathname;

            router.get(
                href,
                {},
                {
                    preserveScroll: true,
                    preserveState: true,
                    replace: true,
                    only: BILLS_RELOAD_PROPS,
                    onError: () => notify({ level: "error", title: "Could not switch the legislative session." }),
                },
            );
        },
        [legislative_sessions],
    );

    // @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
    const layout = billListLayoutFor(useActiveThemeId());

    return (
        <Suspense fallback={<ThemeLayoutPlaceholder shape="list" />}>
            {createElement(layout, {
                bills: filteredBills,
                formattedSwayLocaleName,
                localeSlug: swayLocale?.name,
                localeOptions: options,
                selectedSwayLocaleId: pendingSwayLocaleId ?? swayLocale?.id,
                onLocaleChange: getSwayLocale,
                allCategories: all_categories,
                selectedCategories: categories,
                onToggleCategory: toggleCategory,
                onClearCategories: clearCategories,
                hasMoreBills,
                isLoadingMoreBills,
                onLoadMoreBills: loadMoreBills,
                sortValue,
                onSortChange: sortBills,
                searchValue,
                onSearchChange: searchBills,
                listMode: list_mode,
                legislativeSessions: legislative_sessions,
                selectedLegislativeSessionId: selected_legislative_session_id,
                onLegislativeSessionChange: changeLegislativeSession,
            })}
        </Suspense>
    );
};

export default Bills;
