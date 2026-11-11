import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/home/layouts/cornerstore-home-layout.css";

// @lat: [[home-layout-theme-concepts#BallotHomeLayout]]
const PROMISES = [
    {
        title: "Plain language",
        text: "Bills arrive in words you can read, with the statutory text kept where it belongs — underneath.",
    },
    {
        title: "Your position, recorded",
        text: "Say where you stand while the vote is still live, not after the fact.",
    },
    {
        title: "The receipt",
        text: "See how the people who represent you voted on the same measure you did.",
    },
];

const CornerstoreHomeLayout: React.FC = () => (
    <div className="csh-stage">
        <h1 className="csh-headline">{PARITY_COPY.auth.hero.headline}</h1>
        <p className="csh-deck">{PARITY_COPY.auth.hero.paragraph}</p>

        <div className="csh-signin">
            <PasskeyPanel />
        </div>

        <div className="csh-blocks">
            {PROMISES.map((promise) => (
                <section key={promise.title} className="csh-block">
                    <h2 className="csh-block__title">{promise.title}</h2>
                    <p className="csh-block__text">{promise.text}</p>
                </section>
            ))}
        </div>
    </div>
);

export default CornerstoreHomeLayout;
