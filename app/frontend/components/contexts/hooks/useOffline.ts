import { useContext } from "react";
import OfflineContext, { OfflineContextValue } from "app/frontend/components/contexts/OfflineContext";

export const useOffline = (): OfflineContextValue => {
    const ctx = useContext(OfflineContext);
    if (!ctx) {
        throw new Error("useOffline must be used within OfflineContext.Provider");
    }
    return ctx;
};
