import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/home/layouts/banner-home-layout.css";

const PROMISES = [
    {
        title: "Cut through the noise",
        text: "Vote on the issues that matter — skip the meaningless legislation.",
    },
    {
        title: "Cast your vote",
        text: "Support or opposition, fast and readable on the first screen.",
    },
    {
        title: "Hold them to it",
        text: "See whether your representative voted the way you did.",
    },
];

const BannerHomeLayout: React.FC = () => (
    <div className="bnh-stage">
        <header className="bnh-masthead">
            <span className="bnh-wordmark">
                SWAY<span className="bnh-dot">.</span>
            </span>
            <span className="bnh-tagline">Vote the same bills your representatives do.</span>
        </header>

        <main className="bnh-main">
            <section className="bnh-lead">
                <h1 className="bnh-headline">{PARITY_COPY.auth.hero.headline}</h1>
                <p className="bnh-dek">{PARITY_COPY.auth.hero.paragraph}</p>
            </section>

            <div className="bnh-grid">
                <section className="bnh-entrance">
                    <div className="bnh-eyebrow">Get started</div>
                    <PasskeyPanel />
                </section>

                <aside className="bnh-rail">
                    <div className="bnh-eyebrow">Why it matters</div>
                    <ol className="bnh-promises">
                        {PROMISES.map((promise, index) => (
                            <li key={promise.title} className="bnh-promise">
                                <span className="bnh-num" aria-hidden="true">
                                    {index + 1}
                                </span>
                                <div>
                                    <h3 className="bnh-promise__title">{promise.title}</h3>
                                    <p className="bnh-promise__text">{promise.text}</p>
                                </div>
                            </li>
                        ))}
                    </ol>
                </aside>
            </div>
        </main>

        <footer className="bnh-foot">
            <p>
                <span className="bnh-mark">Sway</span> — vote on the same legislation as your representatives, then see
                whether you agreed.
            </p>
        </footer>
    </div>
);

export default BannerHomeLayout;
