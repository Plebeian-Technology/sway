// @lat: [[registration-funnel-telemetry#Client-side telemetry dispatch and step mapping]]
import { useCallback, useEffect } from "react";
import {
    captureReferralAttribution,
    getOrCreateVisitorToken,
    trackFunnelStep,
    trackFunnelStepOnce,
} from "app/frontend/sway_utils/funnelTracker";

export function useFunnelTracker() {
    useEffect(() => {
        captureReferralAttribution();
    }, []);

    const trackStep = useCallback((step: string, metadata: Record<string, unknown> = {}) => {
        trackFunnelStep(step, metadata);
    }, []);

    const trackStepOnce = useCallback((step: string, metadata: Record<string, unknown> = {}) => {
        trackFunnelStepOnce(step, metadata);
    }, []);

    return {
        trackStep,
        trackStepOnce,
        visitorToken: getOrCreateVisitorToken(),
    };
}
