import { memo } from "react";
import { sway } from "sway";
import { Badge } from "app/frontend/components/ui/badge";
import { calendarDayToDate, formatDate } from "app/frontend/sway_utils/datetimes";
import { shortBillTitle } from "app/frontend/components/bill/sway_utils/billTitle";

interface IProps {
    bill: sway.IBillPickerOption;
}

// @lat: [[bill-creator-picker-mechanics#Why SIGNAL_BADGE_ORDER is a fixed order, independent of interesting_badges]]
const SIGNAL_BADGE_ORDER = ["controversial", "close", "live"] as const;

// @lat: [[bill-creator-picker-mechanics#Why BillPickerRow shows the fuller row inside the open dropdown]]
const BillPickerRow: React.FC<IProps> = ({ bill }) => {
    const meta: string[] = [];
    if (bill.sponsor_name) meta.push(bill.sponsor_name);
    if (bill.category) meta.push(bill.category);
    if (bill.introduced_date_time_utc) meta.push(`Introduced ${formatDate(bill.introduced_date_time_utc)}`);
    if (bill.scheduled_release_date_utc) {
        meta.push(`Scheduled ${formatDate(calendarDayToDate(bill.scheduled_release_date_utc))}`);
    }
    if (bill.legislator_vote_count > 0) {
        meta.push(`${bill.legislator_vote_count} ${bill.legislator_vote_count === 1 ? "vote" : "votes"}`);
    }
    if (bill.organization_position_count > 0) {
        meta.push(
            `${bill.organization_position_count} ${bill.organization_position_count === 1 ? "position" : "positions"}`,
        );
    }

    return (
        <div className="flex flex-col gap-1">
            <div className="flex flex-wrap items-center gap-1.5">
                <span className="font-mono text-xs font-semibold">{bill.external_id}</span>
                {bill.status && (
                    <Badge variant="stamp" tone="info">
                        {bill.status}
                    </Badge>
                )}
                {bill.chamber && <Badge variant="outline">{bill.chamber}</Badge>}
                {SIGNAL_BADGE_ORDER.filter((signal) => bill.interesting_badges?.includes(signal)).map((signal) => {
                    if (signal === "controversial") {
                        return (
                            <Badge
                                key={signal}
                                variant="stamp"
                                tone="warning"
                                title="Cross-party defection or organization position split"
                            >
                                Split
                            </Badge>
                        );
                    }
                    if (signal === "close") {
                        return (
                            <Badge
                                key={signal}
                                variant="stamp"
                                tone="danger"
                                title="Close final-vote margin (Congress and Maryland only)"
                            >
                                Narrow
                            </Badge>
                        );
                    }
                    return (
                        <Badge
                            key={signal}
                            variant="stamp"
                            tone="success"
                            title="Recent legislative activity within 30 days"
                        >
                            Live
                        </Badge>
                    );
                })}
            </div>
            <span className="text-sm leading-snug">{shortBillTitle(bill.title)}</span>
            {meta.length > 0 && <span className="text-xs text-muted-foreground">{meta.join("  ·  ")}</span>}
        </div>
    );
};

export default memo(BillPickerRow);
