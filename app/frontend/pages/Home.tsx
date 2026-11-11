import { createElement, useEffect } from "react";

import { homeLayoutFor } from "app/frontend/components/home/layouts";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { captureReferralAttribution, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

// @lat: [[theme-tokens#Theme tokens#Why the active theme is watched rather than passed down]]
const Home: React.FC = () => {
    useEffect(() => {
        captureReferralAttribution();
        trackFunnelStepOnce("landing");
    }, []);

    return createElement(homeLayoutFor(useActiveThemeId()));
};

export default Home;
