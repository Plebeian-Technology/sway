// @lat: [[legislator-directory-layouts#Legislator directory layout props contract]]

import type { sway } from "sway";
import type { LocaleSelectOption } from "app/frontend/components/ui/LocaleSelect";

export interface ILegislatorsLayoutProps {
    legislators: sway.ILegislator[];
    activeLegislators: sway.ILegislator[];
    activeTab: "current" | "lifetime" | "history";
    onTabChange: (tab: string) => void;
    currentLocale: sway.ISwayLocale | undefined;
    localeOptions: LocaleSelectOption[];
    selectedLocaleId: number | undefined;
    onLocaleChange: (localeId: number) => void;
    waitingForNewTerm: boolean;
    onFindLegislators: () => void;
    currentHistory: sway.legislatorHistory.IHistory | undefined;
    isHistoryLoading: boolean;
    historyFailed: boolean;
    onRetryHistory: () => void;
    termRange: string | null;
}
