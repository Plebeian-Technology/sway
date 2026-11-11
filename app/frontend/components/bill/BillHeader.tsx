import { formatDate } from "app/frontend/sway_utils/datetimes";
import BillCategoryTags from "app/frontend/components/bill/BillCategoryTags";
import BillSponsorLink from "app/frontend/components/bill/BillSponsorLink";
import BillEntryTitle from "app/frontend/components/bill/list-layouts/BillEntryTitle";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    sponsor: sway.ILegislator;
    children?: React.ReactNode;
}

// @lat: [[user-vote-submission#Themed web vote controls#Where the default control sits]]
const BillHeader: React.FC<IProps> = ({ bill, sponsor, children }) => {
    const voteLabel = (() => {
        if (!bill.vote_date_time_utc) {
            return "Legislators have not yet voted on a final version of this bill. Until they do, Sway records the sponsor and any co-sponsors as voting For.";
        }
        if (bill.house_vote_date_time_utc && bill.senate_vote_date_time_utc) {
            return `House voted on ${formatDate(bill.house_vote_date_time_utc)}. Senate voted on ${formatDate(bill.senate_vote_date_time_utc)}.`;
        }
        if (bill.house_vote_date_time_utc) return `House voted on ${formatDate(bill.house_vote_date_time_utc)}.`;
        if (bill.senate_vote_date_time_utc) return `Senate voted on ${formatDate(bill.senate_vote_date_time_utc)}.`;
        return `Legislators voted on ${formatDate(bill.vote_date_time_utc)}.`;
    })();

    return (
        <Card className="bg-card/95" data-testid="bill-hero">
            <CardHeader className="gap-4">
                <div className="flex flex-wrap items-center gap-3">
                    <span className="rounded-full border-neo border-border bg-accent px-3 py-1 text-xs font-black uppercase tracking-widest text-accent-foreground shadow-neo">
                        {bill.external_id}
                    </span>
                    <span className="rounded-full border-neo border-border bg-card px-3 py-1 text-xs font-semibold uppercase tracking-widest text-muted-foreground shadow-neo">
                        {bill.chamber}
                    </span>
                </div>

                <CardTitle
                    className="text-2xl font-black leading-tight sm:text-3xl md:text-4xl"
                    data-testid="bill-title"
                >
                    <BillEntryTitle title={bill.title} qualifierClassName="font-normal text-muted-foreground" />
                </CardTitle>

                <BillCategoryTags categories={bill.categories} />
            </CardHeader>

            <CardContent className="space-y-1 text-sm leading-6 text-muted-foreground">
                {sponsor && (
                    <p className="text-base text-foreground">
                        Sponsored by{" "}
                        <BillSponsorLink
                            legislatorId={bill.legislator_id}
                            className="font-black text-primary underline-offset-4 hover:underline"
                        >
                            {sponsor.full_name}
                        </BillSponsorLink>
                    </p>
                )}
                <p>{voteLabel}</p>
                {!bill.active && bill.vote_date_time_utc && (
                    <p className="font-semibold text-destructive">
                        Legislators that voted on this bill may no longer be in office.
                    </p>
                )}
            </CardContent>

            {children && (
                <div className="border-t-neo border-border pt-5">
                    <CardContent>{children}</CardContent>
                </div>
            )}
        </Card>
    );
};

export default BillHeader;
