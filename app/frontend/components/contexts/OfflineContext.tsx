import { createContext } from "react";

export type OfflineBannerState = "hidden" | "visible" | "asserted";

export interface OfflineContextValue {
    isOnline: boolean;
    lastChecked: Date;
    bannerState: OfflineBannerState;
    dismissBanner: () => void;
    assertBanner: () => void;
}

const OfflineContext = createContext<OfflineContextValue | undefined>(undefined);

export default OfflineContext;
