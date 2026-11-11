import { sway } from "sway";

import DistrictLabel from "app/frontend/components/bill/charts/DistrictLabel";

interface IProps {
    score: sway.IBillScore;
    title?: string;
}

const numberFormatter = new Intl.NumberFormat();

type DistrictAmount = { key: string; district?: sway.IDistrict; label: string; number: number; amount: number };

// @lat: [[bill-vote-charts-design#AffinityDistrictChart.tsx]]
const AffinityDistrictChart: React.FC<IProps> = ({ score, title }) => {
    const districts = Array.isArray(score?.districts) ? score.districts : [];

    // @lat: [[bill-vote-charts-design#AffinityDistrictChart.tsx]]
    const rows: DistrictAmount[] = districts
        .filter((d) => d?.district?.number !== 0)
        .map((d) => {
            const amount = Number(d?.for || 0) - Number(d?.against || 0);
            const num = d?.district?.number ?? 0;
            const symbol = amount > 0 ? "+" : "";
            return {
                key: d?.district?.name ?? `d-${num}`,
                district: d?.district,
                label: `D-${num} (${symbol}${numberFormatter.format(amount)})`,
                number: num,
                amount,
            };
        });

    rows.sort((a, b) => a.number - b.number);

    const absMax = rows.reduce((acc, r) => Math.max(acc, Math.abs(r.amount)), 0);

    if (rows.length === 0 || absMax === 0) {
        return (
            <div
                data-testid="affinity-district-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                No votes recorded yet.
            </div>
        );
    }

    return (
        <div data-testid="affinity-district-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-1.5">
                {rows.map((row) => {
                    const pct = absMax > 0 ? (Math.abs(row.amount) / absMax) * 50 : 0;
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
                                {row.amount > 0 ? "+" : ""}
                                {numberFormatter.format(row.amount)}
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
