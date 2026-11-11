import type { ThemeId } from "app/frontend/styles/themes";

import BallotHomeLayout from "app/frontend/components/home/layouts/BallotHomeLayout";
import BannerHomeLayout from "app/frontend/components/home/layouts/BannerHomeLayout";
import CornerstoreHomeLayout from "app/frontend/components/home/layouts/CornerstoreHomeLayout";
import DefaultHomeLayout from "app/frontend/components/home/layouts/DefaultHomeLayout";
import MonochromeHomeLayout from "app/frontend/components/home/layouts/MonochromeHomeLayout";
import ServiceManualHomeLayout from "app/frontend/components/home/layouts/ServiceManualHomeLayout";
import SwissGridHomeLayout from "app/frontend/components/home/layouts/SwissGridHomeLayout";
import type { HomeLayout } from "app/frontend/components/home/layouts/types";

// @lat: [[home-layout-theme-concepts#Themed home layout design concepts]]
const HOME_LAYOUTS: Partial<Record<ThemeId, HomeLayout>> = {
    banner: BannerHomeLayout,
    ballot: BallotHomeLayout,
    cornerstore: CornerstoreHomeLayout,
    monochrome: MonochromeHomeLayout,
    "service-manual": ServiceManualHomeLayout,
    "swiss-grid": SwissGridHomeLayout,
};

export function homeLayoutFor(themeId: ThemeId): HomeLayout {
    return HOME_LAYOUTS[themeId] ?? DefaultHomeLayout;
}

export type { HomeLayout } from "app/frontend/components/home/layouts/types";
