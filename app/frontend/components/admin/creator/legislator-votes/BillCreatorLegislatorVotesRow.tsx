import { LEDGER_COLUMNS, legislatorDisplayName } from "app/frontend/components/admin/creator/legislator-votes/utils";
import { memo, useCallback } from "react";
import { sway } from "sway";
import { type TSupport } from "app/frontend/sway_constants";
import { Badge } from "app/frontend/components/ui/badge";
import { RadioGroup, RadioGroupItem } from "app/frontend/components/ui/radio-group";

interface IProps {
    legislator: sway.ILegislator;
    current: TSupport | "";
    onSelectSupport: (legislator_id: number, support: TSupport) => void;
}

// @lat: [[legislator-votes-row-memoization#Why BillCreatorLegislatorVotesRow is wrapped in memo]]
const BillCreatorLegislatorVotesRow: React.FC<IProps> = ({ legislator, current, onSelectSupport }) => {
    const name = `legislator-vote-${legislator.id}`;
    const displayName = legislatorDisplayName(legislator);

    const onValueChange = useCallback(
        (v: string) => onSelectSupport(legislator.id, v as TSupport),
        [legislator.id, onSelectSupport],
    );

    return (
        <div
            // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- This is a div-based grid (CSS Grid), not an HTML table, so <tr> is not valid here
            role="row"
            className="min-w-[420px] grid grid-cols-[1fr_repeat(3,minmax(4.5rem,5.5rem))] items-center gap-2 border-b-neo border-border-soft px-4 py-3 last:border-b-0 odd:bg-muted/15 sm:min-w-0"
        >
            <div className="flex flex-col">
                <span className="flex items-center gap-2 text-sm font-semibold">
                    {displayName}
                    {!legislator.active && (
                        <Badge variant="stamp" tone="neutral" data-testid="legislator-former-stamp">
                            Former
                        </Badge>
                    )}
                </span>
                {legislator.district ? (
                    <span className="text-xs text-muted-foreground">
                        {legislator.district.region_code}
                        <span className="mx-1">&middot;</span>
                        <span className="tabular-nums lining-nums">District {legislator.district.number}</span>
                    </span>
                ) : null}
            </div>
            <RadioGroup
                value={current}
                onValueChange={onValueChange}
                className="col-span-3 grid grid-cols-3 gap-2"
                aria-label={`${displayName} vote`}
            >
                {LEDGER_COLUMNS.map((col) => (
                    <div key={`cell-${legislator.id}-${col.key}`} className="flex items-center justify-center">
                        <label
                            htmlFor={`${name}-${col.key}`}
                            className="flex min-h-11 min-w-11 cursor-pointer items-center justify-center rounded-md hover:bg-accent/15"
                        >
                            <RadioGroupItem
                                id={`${name}-${col.key}`}
                                value={col.key}
                                aria-label={`${col.label} for ${displayName}`}
                            />
                        </label>
                    </div>
                ))}
            </RadioGroup>
        </div>
    );
};

export default memo(BillCreatorLegislatorVotesRow);
