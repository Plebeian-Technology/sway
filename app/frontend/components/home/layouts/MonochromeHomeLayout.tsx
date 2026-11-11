import { useEffect } from "react";

import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { captureReferralAttribution, trackFunnelStepOnce } from "app/frontend/sway_utils/funnelTracker";

import "app/frontend/components/home/layouts/monochrome-home-layout.css";

// @lat: [[home-layout-theme-concepts#MonochromeHomeLayout]]
const MonochromeHomeLayout: React.FC = () => {
    useEffect(() => {
        captureReferralAttribution();
        trackFunnelStepOnce("landing");
    }, []);

    return (
        <div className="mch-stage">
            <header className="mch-header">
                <span className="mch-wordmark">Sway</span>
                <h1 className="mch-headline">{PARITY_COPY.auth.hero.headline}</h1>
                <p className="mch-paragraph">{PARITY_COPY.auth.hero.paragraph}</p>
            </header>

            <section className="mch-section">
                <h2 className="mch-section__title">Civic tally specimen</h2>
                <div className="mch-tally">
                    <div className="mch-tally__row">
                        <div className="mch-tally__meta">
                            <span className="mch-tally__label">{PARITY_COPY.votePanel.forLabel}</span>
                            <span className="mch-tally__pct">68%</span>
                        </div>
                        <div className="mch-tally__track">
                            <div className="mch-tally__bar--for" style={{ width: "68%" }} />
                        </div>
                    </div>

                    <div className="mch-tally__row">
                        <div className="mch-tally__meta">
                            <span className="mch-tally__label">{PARITY_COPY.votePanel.againstLabel}</span>
                            <span className="mch-tally__pct">32%</span>
                        </div>
                        <div className="mch-tally__track">
                            <div className="mch-tally__bar--against" style={{ width: "32%" }} />
                        </div>
                    </div>
                </div>
            </section>

            <section className="mch-signin">
                <PasskeyPanel />
            </section>
        </div>
    );
};

export default MonochromeHomeLayout;
