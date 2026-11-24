import { sway } from "sway";

import DistrictLabel from "app/frontend/components/bill/charts/DistrictLabel";
import { selectDistrictVoteSplits } from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";

interface IProps {
    score: sway.IBillScore;
    title?: string;
}

type DistrictAmount = { key: string; district: sway.IDistrict; label: string; amount: number };

const signed = (amount: number) => `${amount > 0 ? "+" : ""}${amount}%`;

// @lat: [[bill-vote-charts-design#AffinityDistrictChart.tsx]]
const AffinityDistrictChart: React.FC<IProps> = ({ score, title }) => {
    // @lat: [[bill-vote-charts-design#AffinityDistrictChart.tsx]]
    const rows: DistrictAmount[] = selectDistrictVoteSplits(score).map(({ district, forPercent, againstPercent }) => {
        const amount = forPercent - againstPercent;
        return {
            key: district.name,
            district,
            label: `D-${district.number} (${signed(amount)})`,
            amount,
        };
    });

    if (rows.length === 0) {
        return (
            <div
                data-testid="affinity-district-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                <VoteComparisonPlaceholder />
            </div>
        );
    }

    return (
        <div data-testid="affinity-district-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-1.5">
                {rows.map((row) => {
                    const pct = Math.abs(row.amount) / 2;
                    const positive = row.amount >= 0;
                    return (
                        <div
                            key={row.key}
                            className="grid grid-cols-[var(--chart-label-gutter)_minmax(0,1fr)_4rem] items-center gap-3"
                            aria-label={row.label}
                        >
                            <DistrictLabel
                                district={row.district}
                                label={row.label}
                                className="text-xs font-black uppercase tracking-widest text-muted-foreground"
                            />
                            <div className="relative h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                                <div
                                    aria-hidden="true"
                                    className="pointer-events-none absolute inset-y-0 left-1/2 w-px bg-border-strong"
                                />
                                <div
                                    className={`absolute top-0 h-full ${positive ? "bg-vote-for" : "bg-vote-against"}`}
                                    style={{
                                        width: `${pct}%`,
                                        left: positive ? "50%" : `${50 - pct}%`,
                                    }}
                                />
                            </div>
                            <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                                {signed(row.amount)}
                            </div>
                        </div>
                    );
                })}
            </div>
            <div className="flex items-center gap-4 text-xs font-black uppercase tracking-widest text-muted-foreground">
                <span className="inline-flex items-center gap-2">
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-against" />
                    Net oppose
                </span>
                <span className="inline-flex items-center gap-2">
                    <span className="inline-block size-3 border-neo border-border-strong bg-vote-for" />
                    Net support
                </span>
            </div>
        </div>
    );
};

export default AffinityDistrictChart;
