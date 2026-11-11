import { useEffect } from "react";

import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { captureReferralAttribution, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

import "app/frontend/components/home/layouts/swiss-grid-home-layout.css";

// @lat: [[home-layout-theme-concepts#SwissGridHomeLayout]]
const SwissGridHomeLayout: React.FC = () => {
    useEffect(() => {
        captureReferralAttribution();
        trackFunnelStepOnce("landing");
    }, []);

    return (
        <div className="sgh-stage">
            <div className="sgh-grid">
                <header className="sgh-row">
                    <div className="sgh-index">01 / IDENTIFIER</div>
                    <div className="sgh-content">
                        <span className="sgh-wordmark">Sway</span>
                    </div>
                </header>

                <section className="sgh-row">
                    <div className="sgh-index">02 / MANDATE</div>
                    <div className="sgh-content">
                        <h1 className="sgh-headline">{PARITY_COPY.auth.hero.headline}</h1>
                        <p className="sgh-paragraph">{PARITY_COPY.auth.hero.paragraph}</p>
                    </div>
                </section>

                <section className="sgh-row">
                    <div className="sgh-index">03 / AUTHENTICATE</div>
                    <div className="sgh-content">
                        <PasskeyPanel />
                    </div>
                </section>
            </div>
        </div>
    );
};

export default SwissGridHomeLayout;
