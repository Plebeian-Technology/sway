import { ShieldCheck } from "lucide-react";
import { useEffect } from "react";

import HomeHero from "app/frontend/components/auth/HomeHero";
import { captureReferralAttribution, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

// @lat: [[home-layout-theme-concepts#DefaultHomeLayout]]
const DefaultHomeLayout: React.FC = () => {
    useEffect(() => {
        captureReferralAttribution();
        trackFunnelStepOnce("landing");
    }, []);

    return (
        <div className="space-y-6">
            <HomeHero />
            <div className="flex items-start gap-3 rounded-xl border-neo border-border-soft bg-surface-3 px-4 py-3.5 text-sm text-foreground sm:items-center sm:px-5">
                <ShieldCheck className="mt-0.5 size-5 shrink-0 text-primary sm:mt-0" aria-hidden="true" />
                <p className="leading-relaxed">
                    <span className="font-semibold text-foreground">Empower your vote.</span>{" "}
                    <span className="text-muted-foreground">
                        Reach the people who represent you on important issues without digging through the clutter.
                    </span>
                </p>
            </div>
        </div>
    );
};

export default DefaultHomeLayout;
