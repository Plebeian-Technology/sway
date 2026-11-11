import { sway } from "sway";

interface IProps {
    scores?: sway.scoring.IAgreeable | null;
    title?: string;
}

const numberFormatter = new Intl.NumberFormat();

type Row = { key: string; label: string; value: number; tone: "for" | "against" | "muted" | "primary" };

// @lat: [[voter-agreement-chart-legacy-parity#VoterAgreementChart]]
const VoterAgreementChart: React.FC<IProps> = ({ scores, title }) => {
    const rows: Row[] = [
        { key: "agreed", label: "Agreed", value: Number(scores?.count_agreed || 0), tone: "for" },
        { key: "disagreed", label: "Disagreed", value: Number(scores?.count_disagreed || 0), tone: "against" },
        {
            key: "abstained",
            label: "Legislator Abstained",
            value: Number(scores?.count_legislator_abstained || 0),
            tone: "muted",
        },
        {
            key: "no-vote",
            label: "No Legislator Vote",
            value: Number(scores?.count_no_legislator_vote || 0),
            tone: "muted",
        },
    ];
    const max = rows.reduce((acc, r) => Math.max(acc, r.value), 0);

    if (max === 0) {
        return (
            <div
                data-testid="voter-agreement-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                No votes recorded yet.
            </div>
        );
    }

    const toneClass = (tone: Row["tone"]) => {
        switch (tone) {
            case "for":
                return "bg-vote-for";
            case "against":
                return "bg-vote-against";
            case "primary":
                return "bg-primary";
            default:
                return "bg-chart-muted";
        }
    };

    return (
        <div data-testid="voter-agreement-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-2">
                {rows.map((row) => {
                    const pct = max > 0 ? (row.value / max) * 100 : 0;
                    return (
                        <div
                            key={row.key}
                            className="grid grid-cols-[8rem_minmax(0,1fr)_3rem] items-center gap-3"
                            aria-label={`${row.label} ${numberFormatter.format(row.value)}`}
                        >
                            <div className="truncate text-xs font-black uppercase tracking-widest text-muted-foreground">
                                {row.label}
                            </div>
                            <div className="h-4 overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo">
                                <div className={`h-full ${toneClass(row.tone)}`} style={{ width: `${pct}%` }} />
                            </div>
                            <div className="text-right text-xs font-black text-foreground tabular-nums lining-nums">
                                {numberFormatter.format(row.value)}
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
};

export default VoterAgreementChart;
