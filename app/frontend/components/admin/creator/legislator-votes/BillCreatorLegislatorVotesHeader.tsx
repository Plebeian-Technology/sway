import { LEDGER_COLUMNS } from "app/frontend/components/admin/creator/legislator-votes/utils";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

const BillCreatorLegislatorVotesHeader: React.FC = () => {
    return (
        <div
            // oxlint-disable-next-line jsx-a11y/prefer-tag-over-role -- This is a div-based grid (CSS Grid), not an HTML table, so <tr> is not valid here
            role="row"
            className="min-w-[420px] grid grid-cols-[1fr_repeat(3,minmax(4.5rem,5.5rem))] items-end gap-2 border-b-neo border-border-soft bg-muted/40 px-4 py-3 sm:min-w-0"
        >
            <div className="text-left text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                <span className="flex items-center gap-1.5">
                    Legislator
                    <FeatureInfo note="creator.legislatorVoteLedger" />
                </span>
            </div>
            {LEDGER_COLUMNS.map((col) => (
                <div
                    key={`header-${col.key}`}
                    className="text-center text-xs font-semibold uppercase tracking-widest text-muted-foreground"
                >
                    {col.label}
                </div>
            ))}
        </div>
    );
};

export default BillCreatorLegislatorVotesHeader;
