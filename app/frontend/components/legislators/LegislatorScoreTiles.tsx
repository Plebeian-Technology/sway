import React from "react";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import ScoreTile from "app/frontend/components/legislators/ScoreTile";
import { sway } from "sway";

interface IProps {
    score?: sway.scoring.IAgreeable | null;
    className?: string;
}

const LegislatorScoreTiles: React.FC<IProps> = ({ score, className = "grid gap-3 sm:grid-cols-3" }) => {
    if (!score) return null;

    return (
        <div className={className}>
            <ScoreTile label={PARITY_COPY.legislators.scoreAgreed} value={score.count_agreed} tone="primary" />
            <ScoreTile
                label={PARITY_COPY.legislators.scoreDisagreed}
                value={score.count_disagreed}
                tone="destructive"
            />
            <ScoreTile
                label={PARITY_COPY.legislators.scoreNoVote}
                value={score.count_no_legislator_vote}
                tone="neutral"
            />
        </div>
    );
};

export default LegislatorScoreTiles;
