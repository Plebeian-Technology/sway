import type { ComponentType } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import type { ISelectOption, sway } from "sway";

// @lat: [[bill-list-layout-props-contract#Load more constants]]
export const BILLS_LOAD_MORE_LABEL = "Load more bills";
export const BILLS_LOADING_MORE_LABEL = "Loading more bills…";

// @lat: [[bill-list-layout-props-contract#Sort constants]]
export const BILLS_SORT_LABEL = PARITY_COPY.bills.sortLabel;
export const BILLS_SORT_OPTIONS = PARITY_COPY.bills.sortOptions;
export type BillsSortValue = (typeof BILLS_SORT_OPTIONS)[number]["value"];
export const DEFAULT_BILLS_SORT: BillsSortValue = "introduced_date_time_utc:desc";
export const BILLS_SORT_VALUES: readonly BillsSortValue[] = BILLS_SORT_OPTIONS.map((option) => option.value);

// @lat: [[bill-list-layout-props-contract#Search constants]]
export const BILLS_SEARCH_LABEL = PARITY_COPY.bills.searchLabel;
export const BILLS_SEARCH_PLACEHOLDER = PARITY_COPY.bills.searchPlaceholder;
export const BILLS_SESSION_LABEL = PARITY_COPY.bills.sessionLabel;

// @lat: [[bills-filter-header#Why sort and categories collapse only on mobile]]
export const BILLS_MORE_OPTIONS_LABEL = "More options";

export type BillsListMode = "all_bills" | "past_bills_of_the_month";

export interface ILegislativeSessionOption {
    id: number;
    name: string;
    active: boolean;
}

// @lat: [[bill-list-layout-props-contract#BillListLayoutProps contract]]
export interface BillListLayoutProps {
    bills: sway.IBill[];
    formattedSwayLocaleName: string;
    // @lat: [[locale-flag-not-seal-design#Where flag files live]]
    localeSlug?: string;
    localeOptions: ISelectOption[];
    selectedSwayLocaleId?: number;
    onLocaleChange: (swayLocaleId: number) => void;
    allCategories: readonly string[];
    selectedCategories: string[];
    onToggleCategory: (category: string) => void;
    onClearCategories: () => void;
    hasMoreBills: boolean;
    isLoadingMoreBills: boolean;
    onLoadMoreBills: () => void;
    sortValue: BillsSortValue;
    onSortChange: (value: BillsSortValue) => void;
    searchValue: string;
    onSearchChange: (term: string) => void;
    listMode?: BillsListMode;
    legislativeSessions?: readonly ILegislativeSessionOption[];
    selectedLegislativeSessionId?: number | null;
    onLegislativeSessionChange?: (sessionId: number) => void;
}

export type BillListLayout = ComponentType<BillListLayoutProps>;
