interface IProps {
    reachedChars: number;
    removedChars: number;
    repairAddedChars: number;
    leftOutChars: number;
    totalChars: number;
}

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const MIN_SEGMENT_PERCENT = 1;

type TSegmentKey = "reached" | "removed" | "leftOut";

type TSegmentPercents = Record<TSegmentKey, number>;

// @lat: [[testimony-coverage-report-invariants#removed_chars clamps to zero; repair_added_chars is the separate growth field]]
const barBasis = (reachedChars: number, removedChars: number, leftOutChars: number): number =>
    reachedChars + removedChars + leftOutChars;

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const segmentPercents = (reachedChars: number, removedChars: number, leftOutChars: number): TSegmentPercents => {
    const basis = barBasis(reachedChars, removedChars, leftOutChars);
    const counts: TSegmentPercents = { reached: reachedChars, removed: removedChars, leftOut: leftOutChars };
    const raw: TSegmentPercents = {
        reached: (reachedChars / basis) * 100,
        removed: (removedChars / basis) * 100,
        leftOut: (leftOutChars / basis) * 100,
    };

    const floored: TSegmentPercents = { ...raw };
    let bump = 0;
    (Object.keys(counts) as TSegmentKey[]).forEach((key) => {
        if (counts[key] > 0 && floored[key] < MIN_SEGMENT_PERCENT) {
            bump += MIN_SEGMENT_PERCENT - floored[key];
            floored[key] = MIN_SEGMENT_PERCENT;
        }
    });

    if (bump > 0) {
        const widestKey = (Object.keys(raw) as TSegmentKey[]).reduce((a, b) => (raw[a] >= raw[b] ? a : b));
        floored[widestKey] -= bump;
    }

    return floored;
};

// @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
const TestimonyRecordBar: React.FC<IProps> = ({
    reachedChars,
    removedChars,
    repairAddedChars,
    leftOutChars,
    totalChars,
}) => {
    const basis = barBasis(reachedChars, removedChars, leftOutChars);
    if (basis === 0) return null;

    const percents = segmentPercents(reachedChars, removedChars, leftOutChars);
    // @lat: [[campaign-letter-disclosure#How the pipeline testimony report renders coverage, campaigns, and pasted text]]
    const removedClause = removedChars > 0 ? `${removedChars.toLocaleString()} were removed as repeated text. ` : "";
    const repairAddedClause =
        repairAddedChars > 0
            ? `${repairAddedChars.toLocaleString()} were added when broken characters were repaired. `
            : "";

    return (
        <div className="flex flex-col gap-1" data-testid="testimony-record-bar">
            <div className="flex h-3 w-full overflow-hidden rounded-sm" aria-hidden="true">
                <div
                    className="bg-primary"
                    data-segment="reached"
                    style={{ width: `${percents.reached.toFixed(4)}%` }}
                />
                <div className="bg-muted" data-segment="removed" style={{ width: `${percents.removed.toFixed(4)}%` }} />
                <div
                    className="bg-warning"
                    data-segment="left-out"
                    style={{ width: `${percents.leftOut.toFixed(4)}%` }}
                />
            </div>
            <p className="text-xs text-muted-foreground tabular-nums lining-nums">
                {`${reachedChars.toLocaleString()} of ${totalChars.toLocaleString()} characters reached the model. ` +
                    removedClause +
                    repairAddedClause +
                    `${leftOutChars.toLocaleString()} were left out.`}
            </p>
        </div>
    );
};

export default TestimonyRecordBar;
