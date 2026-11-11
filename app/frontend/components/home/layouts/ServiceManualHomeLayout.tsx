import { useEffect } from "react";

import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { captureReferralAttribution, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

import "app/frontend/components/home/layouts/service-manual-home-layout.css";

// @lat: [[home-layout-theme-concepts#ServiceManualHomeLayout]]
const ServiceManualHomeLayout: React.FC = () => {
    useEffect(() => {
        captureReferralAttribution();
        trackFunnelStepOnce("landing");
    }, []);

    return (
        <div className="smh-stage">
            <div className="smh-grid">
                <header className="smh-masthead">
                    <span className="smh-wordmark">Sway</span>
                    <h1 className="smh-headline">{PARITY_COPY.auth.hero.headline}</h1>
                    <div className="smh-callout">
                        <p className="smh-callout__paragraph">{PARITY_COPY.auth.hero.paragraph}</p>
                    </div>
                </header>

                <section className="smh-signin">
                    <PasskeyPanel />
                </section>
            </div>
        </div>
    );
};

export default ServiceManualHomeLayout;
