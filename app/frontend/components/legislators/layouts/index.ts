// @lat: [[legislator-directory-layouts#Legislator directory layout selection]]

import type { ThemeId } from "app/frontend/styles/themes";
import React, { lazy } from "react";

import DefaultLegislatorsLayout from "app/frontend/components/legislators/layouts/DefaultLegislatorsLayout";
import type { ILegislatorsLayoutProps } from "app/frontend/components/legislators/layouts/types";

const MonochromeLegislatorsLayout = lazy(
    () => import("app/frontend/components/legislators/layouts/MonochromeLegislatorsLayout"),
);
const ServiceManualLegislatorsLayout = lazy(
    () => import("app/frontend/components/legislators/layouts/ServiceManualLegislatorsLayout"),
);
const SwissGridLegislatorsLayout = lazy(
    () => import("app/frontend/components/legislators/layouts/SwissGridLegislatorsLayout"),
);

const LEGISLATOR_LIST_LAYOUTS: Partial<Record<ThemeId, React.ComponentType<ILegislatorsLayoutProps>>> = {
    monochrome: MonochromeLegislatorsLayout,
    "service-manual": ServiceManualLegislatorsLayout,
    "swiss-grid": SwissGridLegislatorsLayout,
};

export function legislatorsLayoutFor(themeId: ThemeId): React.ComponentType<ILegislatorsLayoutProps> {
    return LEGISLATOR_LIST_LAYOUTS[themeId] ?? DefaultLegislatorsLayout;
}

export { legislatorsLayoutFor as legislatorListLayoutFor };
export { DefaultLegislatorsLayout };
export type { ILegislatorsLayoutProps };
