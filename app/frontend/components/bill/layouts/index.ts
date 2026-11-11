import type { ThemeId } from "app/frontend/styles/themes";

import { lazy } from "react";

import DefaultBillLayout from "app/frontend/components/bill/layouts/DefaultBillLayout";
import type { BillLayout } from "app/frontend/components/bill/layouts/types";

// @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
const BannerBillLayout = lazy(() => import("app/frontend/components/bill/layouts/BannerBillLayout"));
const BallotBillLayout = lazy(() => import("app/frontend/components/bill/layouts/BallotBillLayout"));
const CornerstoreBillLayout = lazy(() => import("app/frontend/components/bill/layouts/CornerstoreBillLayout"));
const MonochromeBillLayout = lazy(() => import("app/frontend/components/bill/layouts/MonochromeBillLayout"));
const ServiceManualBillLayout = lazy(() => import("app/frontend/components/bill/layouts/ServiceManualBillLayout"));
const SwissGridBillLayout = lazy(() => import("app/frontend/components/bill/layouts/SwissGridBillLayout"));

const BILL_LAYOUTS: Partial<Record<ThemeId, BillLayout>> = {
    banner: BannerBillLayout,
    ballot: BallotBillLayout,
    cornerstore: CornerstoreBillLayout,
    monochrome: MonochromeBillLayout,
    "service-manual": ServiceManualBillLayout,
    "swiss-grid": SwissGridBillLayout,
};

export function billLayoutFor(themeId: ThemeId): BillLayout {
    return BILL_LAYOUTS[themeId] ?? DefaultBillLayout;
}

export type { BillLayout, BillLayoutProps } from "app/frontend/components/bill/layouts/types";
