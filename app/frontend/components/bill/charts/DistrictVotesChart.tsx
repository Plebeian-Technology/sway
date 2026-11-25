import { router, usePage } from "@inertiajs/react";
import { useEffect, useRef } from "react";
import { sway } from "sway";

import DistrictLabel from "app/frontend/components/bill/charts/DistrictLabel";
import { selectDistrictVoteSplits } from "app/frontend/components/bill/sway_utils/billPositions";
import VoteComparisonPlaceholder from "app/frontend/components/bill/VoteComparisonPlaceholder";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

interface IProps {
    score: sway.IBillScore;
    title?: string;
}

interface IPageProps {
    user?: sway.IUser | null;
    districts?: sway.IDistrict[];
    [key: string]: unknown;
}

const districtLabel = (district: sway.IDistrict) => `District ${district.number}`;

// @lat: [[bill-vote-charts-design#DistrictVotesChart.tsx]]
const DistrictVotesChart: React.FC<IProps> = ({ score, title }) => {
    const { user, districts: readerDistricts } = usePage<IPageProps>().props;
    const requested = useRef(false);
    const declined = useRef(false);

    // @lat: [[bill-vote-charts-design#The reader's own district is asked for when the chart is drawn]]
    useEffect(() => {
        if (!user || readerDistricts !== undefined || requested.current || declined.current) return;

        requested.current = true;
        router.reload({
            only: ["districts"],
            onSuccess: (page) => {
                declined.current = page.props.districts === undefined;
            },
            onFinish: () => {
                requested.current = false;
            },
        });
    }, [user, readerDistricts]);

    const rows = selectDistrictVoteSplits(score);
    const drawnNumbers = new Set(rows.map((row) => row.district.number));
    const hiddenReaderDistricts = (readerDistricts ?? []).filter(
        (district) => district.number !== 0 && !drawnNumbers.has(district.number),
    );

    if (rows.length === 0 && hiddenReaderDistricts.length === 0) {
        return (
            <div
                data-testid="district-votes-chart-empty"
                className="rounded-xl border-neo border-border bg-surface-3 px-4 py-6 text-center text-sm font-semibold text-muted-foreground shadow-neo"
            >
                <VoteComparisonPlaceholder />
            </div>
        );
    }

    return (
        <div data-testid="district-votes-chart" className="grid gap-3">
            {title && <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>}
            <div className="grid gap-2">
                {rows.map((row) => {
                    const label = districtLabel(row.district);
                    return (
                        <div
                            key={row.district.name}
                            className="grid grid-cols-[var(--chart-label-gutter)_minmax(0,1fr)] items-center gap-3"
                        >
                            <DistrictLabel
                                district={row.district}
                                label={label}
                                className="text-xs font-black uppercase tracking-widest text-muted-foreground"
                            />
                            <div className="grid gap-1">
                                <div
                                    className="flex h-4 items-center overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
                                    aria-label={`${label} support ${row.forPercent}%`}
                                >
                                    <div className="h-full bg-vote-for" style={{ width: `${row.forPercent}%` }} />
                                    <span className="ml-2 text-xs font-black text-foreground tabular-nums lining-nums">
                                        {row.forPercent}%
                                    </span>
                                </div>
                                <div
                                    className="flex h-4 items-center overflow-hidden rounded-lg border-neo border-border-strong bg-muted shadow-neo"
                                    aria-label={`${label} oppose ${row.againstPercent}%`}
                                >
                                    <div
                                        className="h-full bg-vote-against"
                                        style={{ width: `${row.againstPercent}%` }}
                                    />
                                    <span className="ml-2 text-xs font-black text-foreground tabular-nums lining-nums">
                                        {row.againstPercent}%
                                    </span>
                                </div>
                            </div>
                        </div>
                    );
                })}
                {hiddenReaderDistricts.map((district) => (
                    <div
                        key={district.name}
                        data-testid={`district-votes-chart-reader-district-${district.number}`}
                        className="grid grid-cols-[var(--chart-label-gutter)_minmax(0,1fr)] items-center gap-3"
                    >
                        <span className="truncate text-xs font-black uppercase tracking-widest text-muted-foreground">
                            {districtLabel(district)}
                        </span>
                        <span className="text-xs font-semibold text-muted-foreground">
                            {PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes}
                        </span>
                    </div>
                ))}
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
