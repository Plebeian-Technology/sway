import {
    isVoteComparisonSuppressed,
    suppressedVoteComparisonLine,
} from "app/frontend/components/bill/sway_utils/billPositions";
import { isArchivedHistoricalBill } from "app/frontend/components/bill/sway_utils/billArchiving";
import { briefSummary } from "app/frontend/components/bill/sway_utils/billTitle";
import BillCategoryTags from "app/frontend/components/bill/BillCategoryTags";
import BillEditLink from "app/frontend/components/bill/BillEditLink";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import type { BillsListMode } from "app/frontend/components/bill/list-layouts/types";
import BillRowLink from "app/frontend/components/bill/BillRowLink";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { formatCalendarDay } from "app/frontend/sway_utils/datetimes";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill & { user_vote?: sway.IApiUserVote };
    listMode?: BillsListMode;
}

// @lat: [[bill-list-layouts-design#Featured release dates on Past Bills of the Month]]
const BillCard: React.FC<IProps> = ({ bill, listMode }) => {
    const releaseDate =
        listMode === "past_bills_of_the_month" ? formatCalendarDay(bill.scheduled_release_date_utc) : null;

    return (
        <Card className="bg-card/95">
            <CardHeader className="gap-3">
                <div className="flex flex-wrap items-center gap-3">
                    <span className="rounded-full border-neo border-border bg-accent px-3 py-1 text-xs font-black uppercase tracking-widest text-accent-foreground shadow-neo">
                        {bill.external_id}
                    </span>
                    {releaseDate && (
                        <time
                            dateTime={bill.scheduled_release_date_utc}
                            className="text-xs font-semibold uppercase tracking-wider text-muted-foreground"
                        >
                            Featured {releaseDate}
                        </time>
                    )}
                    <BillCategoryTags categories={bill.categories} />
                    {bill.user_vote?.support && (
                        <span className="rounded-full border-neo border-border bg-primary px-3 py-1 text-xs font-black uppercase tracking-widest text-primary-foreground shadow-neo">
                            You voted {bill.user_vote.support}
                        </span>
                    )}
                </div>
                {/* @lat: [[bill-title-display]] */}
                <CardTitle className="text-2xl font-black leading-tight">
                    <BillEntryTitle title={bill.title} qualifierClassName="font-normal text-muted-foreground" />
                </CardTitle>
            </CardHeader>

            <CardContent className="space-y-4">
                <p className="max-w-2xl text-sm leading-6 text-muted-foreground">
                    {briefSummary(bill.summary, 180) ||
                        "Open the bill to review the full summary, vote totals, and arguments."}
                </p>

                {isVoteComparisonSuppressed(bill.bill_score) ? (
                    <p className="text-sm font-semibold text-muted-foreground">{suppressedVoteComparisonLine()}</p>
                ) : (
                    <div className="grid gap-3 sm:grid-cols-2">
                        <div className="rounded-xl border-neo border-border bg-surface-3 px-4 py-4 shadow-neo">
                            <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                For
                            </div>
                            <div className="mt-2 text-3xl font-black text-vote-for">{bill.bill_score?.for ?? 0}</div>
                        </div>
                        <div className="rounded-xl border-neo border-border bg-surface-3 px-4 py-4 shadow-neo">
                            <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">
                                Against
                            </div>
                            <div className="mt-2 text-3xl font-black text-vote-against">
                                {bill.bill_score?.against ?? 0}
                            </div>
                        </div>
                    </div>
                )}

                <div className="flex flex-wrap items-center justify-end gap-4">
                    <BillEditLink
                        billId={bill.id}
                        billIdentifier={bill.external_id}
                        isArchived={isArchivedHistoricalBill(bill)}
                    />
                    <BillRowLink
                        billId={bill.id}
                        className="inline-flex rounded-xl border-neo border-border bg-primary px-4 py-3 text-sm font-semibold text-primary-foreground shadow-neo transition hover:-translate-x-0.5 hover:-translate-y-0.5"
                    >
                        Open bill
                    </BillRowLink>
                </div>
            </CardContent>
        </Card>
    );
};

export default BillCard;
