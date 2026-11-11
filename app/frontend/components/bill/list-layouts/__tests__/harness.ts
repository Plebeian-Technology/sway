import { vi } from "vitest";

import BallotBillListLayout from "app/frontend/components/bill/list-layouts/BallotBillListLayout";
import BannerBillListLayout from "app/frontend/components/bill/list-layouts/BannerBillListLayout";
import CornerstoreBillListLayout from "app/frontend/components/bill/list-layouts/CornerstoreBillListLayout";
import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import MonochromeBillListLayout from "app/frontend/components/bill/list-layouts/MonochromeBillListLayout";
import ServiceManualBillListLayout from "app/frontend/components/bill/list-layouts/ServiceManualBillListLayout";
import SwissGridBillListLayout from "app/frontend/components/bill/list-layouts/SwissGridBillListLayout";
import { DEFAULT_BILLS_SORT, type BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";
import type { sway } from "sway";

export const LAYOUTS = [
    ["DefaultBillListLayout", DefaultBillListLayout],
    ["BannerBillListLayout", BannerBillListLayout],
    ["BallotBillListLayout", BallotBillListLayout],
    ["CornerstoreBillListLayout", CornerstoreBillListLayout],
    ["MonochromeBillListLayout", MonochromeBillListLayout],
    ["ServiceManualBillListLayout", ServiceManualBillListLayout],
    ["SwissGridBillListLayout", SwissGridBillListLayout],
] as const;

export const createBaseProps = (overrides: Partial<BillListLayoutProps> = {}): BillListLayoutProps => ({
    bills: [],
    formattedSwayLocaleName: "Baltimore",
    localeSlug: "baltimore-maryland-united_states",
    localeOptions: [],
    selectedSwayLocaleId: 1,
    onLocaleChange: vi.fn<(swayLocaleId: number) => void>(),
    allCategories: [],
    selectedCategories: [],
    onToggleCategory: vi.fn<(category: string) => void>(),
    onClearCategories: vi.fn<() => void>(),
    hasMoreBills: false,
    isLoadingMoreBills: false,
    onLoadMoreBills: vi.fn<() => void>(),
    sortValue: DEFAULT_BILLS_SORT,
    onSortChange: vi.fn<(value: BillListLayoutProps["sortValue"]) => void>(),
    searchValue: "",
    onSearchChange: vi.fn<(term: string) => void>(),
    ...overrides,
});

export const baseProps: BillListLayoutProps = createBaseProps();

export const makeBill = (id: number, externalId: string, title: string, chamber: string = "council"): sway.IBill =>
    ({
        id,
        external_id: externalId,
        title,
        chamber,
    }) as unknown as sway.IBill;
