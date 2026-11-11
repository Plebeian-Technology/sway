import { sway } from "sway";

interface IProps {
    scores?: sway.scoring.ILegislatorDistrictScore | null;
    title?: string;
}

const numberFormatter = new Intl.NumberFormat();

// @lat: [[voter-agreement-chart-legacy-parity#VoterDistrictAgreementChart]]
const VoterDistrictAgreementChart: React.FC<IProps> = ({ scores, title }) => {
    const rawAgreed = scores?.count_agreed;
    const rawDisagreed = scores?.count_disagreed;
    const agreedScore = typeof rawAgreed === "number" && isFinite(rawAgreed) ? rawAgreed : 0;
    const disagreedScore = typeof rawDisagreed === "number" && isFinite(rawDisagreed) ? rawDisagreed : 0;
    const max = Math.max(agreedScore, disagreedScore);

    if (agreedScore === 0 && disagreedScore === 0) {
        return (
            <div
                data-testid="voter-district-agreement-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                No votes recorded yet.
            </div>
        );
    }

    const agreedPct = max > 0 ? (agreedScore / max) * 100 : 0;
    const disagreedPct = max > 0 ? (disagreedScore / max) * 100 : 0;

    return (
        <div data-testid="voter-district-agreement-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-2">
                <div className="grid grid-cols-[6rem_minmax(0,1fr)_3rem] items-center gap-3">
                    <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">Agreed</div>
                    <div className="h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                        <div className="h-full bg-vote-for" style={{ width: `${agreedPct}%` }} />
                    </div>
                    <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                        {numberFormatter.format(agreedScore)}
                    </div>
                </div>
                <div className="grid grid-cols-[6rem_minmax(0,1fr)_3rem] items-center gap-3">
                    <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">Disagreed</div>
                    <div className="h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                        <div className="h-full bg-vote-against" style={{ width: `${disagreedPct}%` }} />
                    </div>
                    <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                        {numberFormatter.format(disagreedScore)}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default VoterDistrictAgreementChart;
