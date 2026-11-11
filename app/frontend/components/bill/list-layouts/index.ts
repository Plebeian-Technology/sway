import type { ThemeId } from "app/frontend/styles/themes";

import { lazy } from "react";

import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import type { BillListLayout } from "app/frontend/components/bill/list-layouts/types";

// @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
const BannerBillListLayout = lazy(() => import("app/frontend/components/bill/list-layouts/BannerBillListLayout"));
const BallotBillListLayout = lazy(() => import("app/frontend/components/bill/list-layouts/BallotBillListLayout"));
const CornerstoreBillListLayout = lazy(
    () => import("app/frontend/components/bill/list-layouts/CornerstoreBillListLayout"),
);
const MonochromeBillListLayout = lazy(
    () => import("app/frontend/components/bill/list-layouts/MonochromeBillListLayout"),
);
const ServiceManualBillListLayout = lazy(
    () => import("app/frontend/components/bill/list-layouts/ServiceManualBillListLayout"),
);
const SwissGridBillListLayout = lazy(() => import("app/frontend/components/bill/list-layouts/SwissGridBillListLayout"));

// @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
const BILL_LIST_LAYOUTS: Partial<Record<ThemeId, BillListLayout>> = {
    banner: BannerBillListLayout,
    ballot: BallotBillListLayout,
    cornerstore: CornerstoreBillListLayout,
    monochrome: MonochromeBillListLayout,
    "service-manual": ServiceManualBillListLayout,
    "swiss-grid": SwissGridBillListLayout,
};

// @lat: [[theme-driven-bill-layout-selection#Theme-driven layout selection on Bill.tsx and Bills.tsx]]
export function billListLayoutFor(themeId: ThemeId): BillListLayout {
    return BILL_LIST_LAYOUTS[themeId] ?? DefaultBillListLayout;
}

export type { BillListLayout, BillListLayoutProps } from "app/frontend/components/bill/list-layouts/types";
