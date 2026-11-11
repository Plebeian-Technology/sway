import { sway } from "sway";

interface IProps {
    score: sway.IBillScore;
    title?: string;
}

const numberFormatter = new Intl.NumberFormat();

// @lat: [[bill-vote-charts-design#TotalVotesChart.tsx]]
const TotalVotesChart: React.FC<IProps> = ({ score, title }) => {
    const support = Number(score?.for || 0);
    const oppose = Number(score?.against || 0);
    const total = support + oppose;

    if (total === 0) {
        return (
            <div
                data-testid="total-votes-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                No votes recorded yet.
            </div>
        );
    }

    const supportPct = total ? (support / total) * 100 : 0;
    const opposePct = total ? (oppose / total) * 100 : 0;

    return (
        <figure data-testid="total-votes-chart" className="grid gap-3">
            {title && (
                <figcaption className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                    {title}
                </figcaption>
            )}
            <div
                className="flex h-9 w-full overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
                aria-label={`${numberFormatter.format(support)} support, ${numberFormatter.format(oppose)} oppose`}
            >
                {supportPct > 0 && (
                    <div
                        className="flex items-center justify-start bg-vote-for px-2 text-xs font-black text-foreground tabular-nums lining-nums"
                        style={{ width: `${supportPct}%` }}
                    >
                        {supportPct >= 12 && numberFormatter.format(support)}
                    </div>
                )}
                {opposePct > 0 && (
                    <div
                        className="flex items-center justify-end bg-vote-against px-2 text-xs font-black text-foreground tabular-nums lining-nums"
                        style={{ width: `${opposePct}%` }}
                    >
                        {opposePct >= 12 && numberFormatter.format(oppose)}
                    </div>
                )}
            </div>
            <div className="flex items-center justify-between text-xs font-black uppercase tracking-widest text-muted-foreground">
                <span className="inline-flex items-center gap-2">
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-for" />
                    <span>
                        Support&nbsp;
                        <span className="ml-2 text-foreground tabular-nums lining-nums">
                            {numberFormatter.format(support)}
                        </span>
                    </span>
                </span>
                <span className="inline-flex items-center gap-2">
                    <span>
                        Oppose&nbsp;
                        <span className="mr-2 text-foreground tabular-nums lining-nums">
                            {numberFormatter.format(oppose)}
                        </span>
                    </span>
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-against" />
                </span>
            </div>
        </figure>
    );
};

export default TotalVotesChart;
