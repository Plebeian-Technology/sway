import { sway } from "sway";

import DistrictLabel from "app/frontend/components/bill/charts/DistrictLabel";

interface IProps {
    score: sway.IBillScore;
    title?: string;
}

const numberFormatter = new Intl.NumberFormat();

// @lat: [[bill-vote-charts-design#DistrictVotesChart.tsx]]
const DistrictVotesChart: React.FC<IProps> = ({ score, title }) => {
    const districts = Array.isArray(score?.districts) ? score.districts : [];

    const rows = districts
        // @lat: [[bill-vote-charts-design#DistrictVotesChart.tsx]]
        .filter((d) => d?.district?.number !== 0)
        .map((d) => {
            const support = Number(d?.for || 0);
            const oppose = Number(d?.against || 0);
            return {
                key: d?.district?.name ?? `d-${d?.district?.number ?? "?"}`,
                district: d?.district,
                number: d?.district?.number ?? 0,
                label: `District ${d?.district?.number ?? d?.district?.name ?? "?"}`,
                support,
                oppose,
                total: support + oppose,
            };
        })
        .sort((a, b) => a.number - b.number);

    const max = rows.reduce((acc, r) => Math.max(acc, r.support, r.oppose), 0);

    if (rows.length === 0 || max === 0) {
        return (
            <div
                data-testid="district-votes-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                No votes recorded yet.
            </div>
        );
    }

    return (
        <div data-testid="district-votes-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-2">
                {rows.map((row) => {
                    const supportPct = max > 0 ? (row.support / max) * 100 : 0;
                    const opposePct = max > 0 ? (row.oppose / max) * 100 : 0;
                    return (
                        <div
                            key={row.key}
                            className="grid grid-cols-[var(--chart-label-gutter)_minmax(0,1fr)] items-center gap-3"
                        >
                            <DistrictLabel
                                district={row.district}
                                label={row.label}
                                className="text-xs font-black uppercase tracking-widest text-muted-foreground"
                            />
                            <div className="grid gap-1">
                                <div
                                    className="flex h-4 items-center overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
                                    aria-label={`${row.label} support ${numberFormatter.format(row.support)}`}
                                >
                                    <div className="h-full bg-vote-for" style={{ width: `${supportPct}%` }} />
                                    <span className="ml-2 text-xs font-black text-foreground tabular-nums lining-nums">
                                        {numberFormatter.format(row.support)}
                                    </span>
                                </div>
                                <div
                                    className="flex h-4 items-center overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
                                    aria-label={`${row.label} oppose ${numberFormatter.format(row.oppose)}`}
                                >
                                    <div className="h-full bg-vote-against" style={{ width: `${opposePct}%` }} />
                                    <span className="ml-2 text-xs font-black text-foreground tabular-nums lining-nums">
                                        {numberFormatter.format(row.oppose)}
                                    </span>
                                </div>
                            </div>
                        </div>
                    );
                })}
            </div>
            <div className="flex items-center gap-4 text-xs font-black uppercase tracking-widest text-muted-foreground">
                <span className="inline-flex items-center gap-2">
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-for" />
                    Support
                </span>
                <span className="inline-flex items-center gap-2">
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-against" />
                    Oppose
                </span>
            </div>
        </div>
    );
};

export default DistrictVotesChart;
