import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

import "app/frontend/components/home/layouts/ballot-home-layout.css";

// @lat: [[home-layout-theme-concepts#BallotHomeLayout]]
const INSTRUCTIONS = [
    {
        title: "Read the measure",
        text: "Every bill arrives in plain language, with the legal text kept underneath it rather than in front of it.",
    },
    {
        title: "Mark your choice",
        text: "Fill the oval for or against. Your position is recorded the moment you mark it.",
    },
    {
        title: "Compare the record",
        text: "See how the representatives who answer to you voted on the very same measure.",
    },
];

// @lat: [[home-layout-theme-concepts#BallotHomeLayout]]
const BallotHomeLayout: React.FC = () => (
    <div className="balh-sheet">
        <header className="balh-header">
            <p className="balh-header__kind">Sample ballot</p>
            <h1 className="balh-header__title">{PARITY_COPY.auth.hero.headline}</h1>
            <p className="balh-header__deck">{PARITY_COPY.auth.hero.paragraph}</p>
        </header>

        <section className="balh-section">
            <h2 className="balh-sectionlabel">Instructions to voters</h2>
            <ol className="balh-instructions">
                {INSTRUCTIONS.map((instruction, index) => (
                    <li key={instruction.title} className="balh-instruction">
                        <span className="balh-instruction__n" aria-hidden="true">
                            {index + 1}
                        </span>
                        <div>
                            <h3 className="balh-instruction__title">{instruction.title}</h3>
                            <p className="balh-instruction__text">{instruction.text}</p>
                        </div>
                    </li>
                ))}
            </ol>
        </section>

        <section className="balh-section">
            <h2 className="balh-sectionlabel">Check in to vote</h2>
            <PasskeyPanel />
        </section>
    </div>
);

export default BallotHomeLayout;
