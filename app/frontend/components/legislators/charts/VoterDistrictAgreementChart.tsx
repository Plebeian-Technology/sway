import { sway } from "sway";

import { isVoteComparisonSuppressed } from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";

interface IProps {
    scores?: sway.scoring.IGroupAgreeable | null;
    title?: string;
}

// @lat: [[voter-privacy-threshold#Legislator charts draw percentages or the placeholder]]
const VoterDistrictAgreementChart: React.FC<IProps> = ({ scores, title }) => {
    const titleRow = title && (
        <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>
    );

    if (!scores || isVoteComparisonSuppressed(scores)) {
        return (
            <div data-testid="voter-district-agreement-chart-suppressed" className="grid gap-3">
                {titleRow}
                <VoteComparisonPlaceholder />
            </div>
        );
    }

    const agreedPercent = scores.agreed_percent ?? 0;
    const disagreedPercent = scores.disagreed_percent ?? 0;

    return (
        <div data-testid="voter-district-agreement-chart" className="grid gap-3">
            {titleRow}
            <div className="grid gap-2">
                <div className="grid grid-cols-[6rem_minmax(0,1fr)_3rem] items-center gap-3">
                    <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">Agreed</div>
                    <div className="h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                        <div className="h-full bg-vote-for" style={{ width: `${agreedPercent}%` }} />
                    </div>
                    <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                        {agreedPercent}%
                    </div>
                </div>
                <div className="grid grid-cols-[6rem_minmax(0,1fr)_3rem] items-center gap-3">
                    <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">Disagreed</div>
                    <div className="h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                        <div className="h-full bg-vote-against" style={{ width: `${disagreedPercent}%` }} />
                    </div>
                    <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                        {disagreedPercent}%
                    </div>
                </div>
            </div>
        </div>
    );
};

export default VoterDistrictAgreementChart;
