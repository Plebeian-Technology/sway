import { useCallback, useState } from "react";
import type { OfflineBannerState } from "app/frontend/components/contexts/OfflineContext";

export interface UseOfflineBannerStateReturn {
    bannerState: OfflineBannerState;
    dismissBanner: () => void;
    assertBanner: () => void;
}

export const useOfflineBannerState = (isOnline: boolean): UseOfflineBannerStateReturn => {
    const [bannerState, setBannerState] = useState<OfflineBannerState>(isOnline ? "hidden" : "visible");

    // @lat: [[offline-banner-state-during-render#Why useOfflineBannerState resets its state during render]]
    const [prevOnline, setPrevOnline] = useState<boolean>(isOnline);
    if (prevOnline !== isOnline) {
        setPrevOnline(isOnline);
        setBannerState(isOnline ? "hidden" : "visible");
    }

    const dismissBanner = useCallback(() => {
        setBannerState((prev) => (prev === "visible" ? "hidden" : prev));
    }, []);

    const assertBanner = useCallback(() => {
        setBannerState((prev) => (prev === "hidden" && !isOnline ? "asserted" : prev));
    }, [isOnline]);

    return { bannerState, dismissBanner, assertBanner };
};
